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
