#!/bin/bash

set -euo pipefail

[[ -n "${script_dir:-}" ]] || { echo "ERROR: script_dir is not set. Run via perf_main.sh." >&2; exit 1; }
source "${script_dir}/code/env.sh"
source "${script_dir}/code/common.sh"

#######################################
# Parse args
#######################################
while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--dry-run)
            if [[ "${2:-}" =~ ^[012]$ ]]; then DRY_RUN="$2"; shift 2
            else DRY_RUN=2; shift; fi ;;
        -*) error_exit "Unknown option: $1" ;;
        *)  break ;;
    esac
done

export DRY_RUN

[[ $# -ge 1 ]] || error_exit "Usage: $0 [-d <level>] <uniqueid>"
uniqueid="$1"

cds_dir="${script_dir}/CDS_log/${uniqueid}"
timing_file="${cds_dir}/timing.tsv"
summary_file="${cds_dir}/perf_summary.txt"

if [[ "${DRY_RUN}" -ge 2 ]]; then
    log "[DRY-RUN:2] Would write perf summary to ${summary_file}"
    exit 0
fi

#######################################
# Legacy result/<uniqueid>/summary.txt (legacy code/summary.sh):
# for every file in the result dir, its name, its content, then " "
# Written before the timing check so failed runs still get it.
#######################################
write_legacy_summary() {
    local result_dir="${script_dir}/result/${uniqueid}"
    local legacy_summary="${result_dir}/summary.txt"
    local f

    if [[ ! -d "${result_dir}" ]]; then
        warn "result dir not found: ${result_dir} — no summary.txt written"
        return 0
    fi

    : > "${legacy_summary}"
    for f in "${result_dir}"/*; do
        [[ "$(basename "${f}")" != "summary.txt" ]] || continue
        [[ -f "${f}" ]] || continue
        {
            basename "${f}"   # log file name
            cat "${f}"        # log file content
            echo " "          # separator line
        } >> "${legacy_summary}"
    done
    log "Summary generated at ${legacy_summary}"
}

write_legacy_summary

[[ -f "${timing_file}" ]] || error_exit "Timing file not found: ${timing_file}"

#######################################
# Format seconds → HH:MM:SS
#######################################
fmt_elapsed() {
    local s="$1"
    printf "%02d:%02d:%02d" $(( s/3600 )) $(( (s%3600)/60 )) $(( s%60 ))
}

log "Writing perf summary to ${summary_file}"

{
    echo "Performance Summary (${uniqueid})"
    echo "================================================================"
    printf "%-28s %-12s %s\n" "Test (testtype/lib)" "Mode" "Elapsed"
    echo "----------------------------------------------------------------"

    total_sec=0
    count=0

    while IFS=$'\t' read -r tt ll mm elapsed; do
        [[ -n "${tt:-}" ]] || continue
        total_sec=$(( total_sec + elapsed ))
        count=$(( count + 1 ))
        printf "%-28s %-12s %s\n" "${tt}/${ll}" "${mm}" "$(fmt_elapsed "${elapsed}")"
    done < <(sort "${timing_file}")

    echo "----------------------------------------------------------------"
    if [[ ${count} -gt 0 ]]; then
        avg=$(( total_sec / count ))
        echo ""
        printf "%-28s %-12s %s\n" "Total  (${count} tests)" "" "$(fmt_elapsed "${total_sec}")"
        printf "%-28s %-12s %s\n" "Average" "" "$(fmt_elapsed "${avg}")"
    fi
} | tee "${summary_file}"

log "Perf summary written to ${summary_file}"

#######################################
# Export metrics as JSON for trend tracking
#
# Source: result/{uniqueid}/Test{N}_{lib}_{mode}_{virtuoso_ver}.log
#         Log line: "Test1_BM01. Performance {desc} {mode} time {elapsed_sec}"
#         elapsed_sec = compareTime(t2 t1) inside the replay, in seconds
#         virtuoso_ver = virtuosoVer() of the Virtuoso that ran the replay
#
# Output:
#   perf_metrics/{uniqueid}.json   — all records for this run (array)
#   perf_metrics/history.jsonl     — append-only, one JSON object per line
#                                    (ready for DB import)
#
# Test number (N) is derived from PERF_TESTS array order (1-based); that order
# must match the Test<N> numbers written by the GenerateReplayScript templates.
#######################################
export_metrics() {
    local result_dir="${script_dir}/result/${uniqueid}"
    local metrics_dir="${script_dir}/perf_metrics"
    local run_file="${metrics_dir}/${uniqueid}.json"
    local history_file="${metrics_dir}/history.jsonl"
    local run_ts
    run_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    if [[ ! -d "${result_dir}" ]]; then
        if [[ "${DRY_RUN}" -ge 1 ]]; then
            log "[DRY-RUN:${DRY_RUN}] result dir not found (Virtuoso skipped): ${result_dir}"
        else
            warn "result dir not found: ${result_dir} — skipping metric export"
        fi
        return 0
    fi

    mkdir -p "${metrics_dir}"

    # Build testtype → 1-based index mapping from PERF_TESTS order
    declare -A testtype_num=()
    for i in "${!PERF_TESTS[@]}"; do
        testtype_num["${PERF_TESTS[$i]}"]=$(( i + 1 ))
    done

    local csv_header="run_time,uniqueid,testtype,lib,mode,tool_ver,virtuoso_ver,elapsed_sec,description"

    local -a records=()     # JSON strings
    local -a csv_rows=()    # CSV strings (no header)
    local count=0 skipped=0

    while IFS=$'\t' read -r tt ll mm _; do
        [[ -n "${tt:-}" ]] || continue

        local test_num="${testtype_num[${tt}]:-}"
        if [[ -z "${test_num}" ]]; then
            warn "Unknown testtype '${tt}' — not in PERF_TESTS; skipping"
            skipped=$(( skipped + 1 ))
            continue
        fi

        # The replay names the file after virtuosoVer(), so match any version suffix
        local log_prefix="Test${test_num}_${ll}_${mm}_"
        local -a log_matches=()
        mapfile -t log_matches < <(compgen -G "${result_dir}/${log_prefix}*.log" || true)
        if [[ ${#log_matches[@]} -eq 0 ]]; then
            warn "Log not found: ${log_prefix}*.log — skipping"
            skipped=$(( skipped + 1 ))
            continue
        fi
        if [[ ${#log_matches[@]} -gt 1 ]]; then
            warn "${#log_matches[@]} logs match ${log_prefix}*.log — using $(basename "${log_matches[0]}")"
        fi
        local log_file="${log_matches[0]}"
        local virtuoso_ver
        virtuoso_ver="$(basename "${log_file}" .log)"
        virtuoso_ver="${virtuoso_ver#${log_prefix}}"

        # Log line format:
        #   "Test1_BM01. Performance Edit-Check-Hierarchy managed time 2000"
        # Fields: $1=id  $2=Performance  $3..NF-3=description  NF-2=mode  NF-1=time  NF=elapsed_sec
        local log_line
        log_line=$(head -1 "${log_file}")
        local elapsed_sec description
        read -r elapsed_sec description <<< "$(
            awk '{
                e = $NF
                d = ""
                for (i = 3; i <= NF-3; i++) d = d (i > 3 ? " " : "") $i
                print e " " d
            }' <<< "${log_line}"
        )"

        if [[ -z "${elapsed_sec}" || ! "${elapsed_sec}" =~ ^[0-9]+$ ]]; then
            warn "No valid timing in $(basename "${log_file}") — skipping"
            skipped=$(( skipped + 1 ))
            continue
        fi

        # JSON: escape backslash and double-quote in description
        local desc_esc="${description//\\/\\\\}"
        desc_esc="${desc_esc//\"/\\\"}"

        records+=(
            "$(printf '{"run_time":"%s","uniqueid":"%s","testtype":"%s","lib":"%s","mode":"%s","tool_ver":"%s","virtuoso_ver":"%s","elapsed_sec":%d,"description":"%s"}' \
                "${run_ts}" "${uniqueid}" "${tt}" "${ll}" "${mm}" \
                "${VSE_VERSION}" "${virtuoso_ver}" "${elapsed_sec}" "${desc_esc}")"
        )

        # CSV: quote fields that may contain commas or spaces
        csv_rows+=(
            "$(printf '"%s","%s","%s","%s","%s","%s","%s",%d,"%s"' \
                "${run_ts}" "${uniqueid}" "${tt}" "${ll}" "${mm}" \
                "${VSE_VERSION}" "${virtuoso_ver}" "${elapsed_sec}" "${description}")"
        )

        count=$(( count + 1 ))
    done < <(sort "${timing_file}")

    if [[ ${count} -eq 0 ]]; then
        warn "No metrics to export (skipped=${skipped})"
        return 0
    fi

    # --- Per-run JSON (pretty array) ---
    {
        printf '{"run_time":"%s","uniqueid":"%s","tool_ver":"%s","results":[\n' \
            "${run_ts}" "${uniqueid}" "${VSE_VERSION}"
        local first=true
        for rec in "${records[@]}"; do
            [[ "${first}" == true ]] && first=false || printf ',\n'
            printf '  %s' "${rec}"
        done
        printf '\n]}\n'
    } > "${run_file}"

    # --- Per-run CSV (with header) ---
    {
        echo "${csv_header}"
        for row in "${csv_rows[@]}"; do echo "${row}"; done
    } > "${metrics_dir}/${uniqueid}.csv"

    # --- history.jsonl: append one flat record per line (DB-import ready) ---
    for rec in "${records[@]}"; do
        echo "${rec}" >> "${history_file}"
    done

    # --- history.csv: write header only on first create, then append rows ---
    local history_csv="${metrics_dir}/history.csv"
    [[ -f "${history_csv}" ]] || echo "${csv_header}" > "${history_csv}"
    for row in "${csv_rows[@]}"; do
        echo "${row}" >> "${history_csv}"
    done

    log "Metrics exported: ${count} record(s)"
    log "  ${run_file}"
    log "  ${metrics_dir}/${uniqueid}.csv"
    log "  ${history_file}"
    log "  ${history_csv}"
    if [[ ${skipped} -gt 0 ]]; then
        warn "  ${skipped} record(s) skipped"
    fi
}

export_metrics
