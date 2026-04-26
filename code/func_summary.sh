#!/bin/bash

set -euo pipefail

[[ -n "${script_dir:-}" ]] || { echo "ERROR: script_dir is not set. Run via func_main.sh." >&2; exit 1; }
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

[[ $# -ge 2 ]] || error_exit "Usage: $0 [-d level] <mode> <uniqueid> [expected_row]"
mode="$1"
uniqueid="$2"
expected_row="${3:-0}"

logdir="${script_dir}/CDS_log/${uniqueid}"
summary_file="${logdir}/func_summary_${mode}.txt"

if [[ "${DRY_RUN}" -ge 2 ]]; then
    log "[DRY-RUN:2] Would write func summary to ${summary_file}"
    exit 0
fi

[[ -d "${logdir}" ]] || error_exit "CDS log directory not found: ${logdir}"

log "Writing func summary to ${summary_file}"

pass_count=0
fail_count=0
total_count=0

{
    echo "Functional Test Summary (${mode} / ${uniqueid})"
    echo "================================================================"
    printf "%-40s %s\n" "Test" "Result"
    echo "----------------------------------------------------------------"

    for logfile in "${logdir}"/CDS_${mode}_*.log; do
        [[ -f "${logfile}" ]] || continue
        (( total_count++ )) || true
        testname=$(basename "${logfile}" .log)

        if (( expected_row > 0 )) && \
           [[ "$(grep -c 'Row_' "${logfile}" 2>/dev/null || echo 0)" -ne "${expected_row}" ]]; then
            result="FAIL"
            (( fail_count++ )) || true
        elif grep -q "FAIL" "${logfile}" 2>/dev/null; then
            result="FAIL"
            (( fail_count++ )) || true
        else
            result="PASS"
            (( pass_count++ )) || true
        fi

        printf "%-40s %s\n" "${testname}" "${result}"
    done

    echo "----------------------------------------------------------------"
    echo ""
    echo "Total : ${total_count}"
    echo "PASS  : ${pass_count}"
    echo "FAIL  : ${fail_count}"

    if (( fail_count > 0 )); then
        echo ""
        echo "Failed Tests:"
        echo "----------------------------------------------------------------"
        for logfile in "${logdir}"/CDS_${mode}_*.log; do
            [[ -f "${logfile}" ]] || continue
            testname=$(basename "${logfile}" .log)
            if (( expected_row > 0 )) && \
               [[ "$(grep -c 'Row_' "${logfile}" 2>/dev/null || echo 0)" -ne "${expected_row}" ]]; then
                echo "  ${testname} : Row count mismatch (expected ${expected_row})"
            elif grep -q "FAIL" "${logfile}" 2>/dev/null; then
                echo "  ${testname} : FAIL detected in log"
            fi
        done
    fi
} | tee "${summary_file}"

log "Func summary written to ${summary_file}"
