#!/bin/bash

set -euo pipefail

script_dir="${script_dir:-$(cd "$(dirname "$0")/.." && pwd)}"
source "${script_dir}/code/env.sh"
source "${script_dir}/code/common.sh"

#######################################
# Parse args
#######################################
while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--dry-run)
            if [[ "${2:-}" =~ ^[012]$ ]]; then
                DRY_RUN="$2"
                shift 2
            else
                DRY_RUN=2
                shift
            fi
            ;;
        -*)
            error_exit "Unknown option: $1"
            ;;
        *)
            break
            ;;
    esac
done

export DRY_RUN

#######################################
# Resolve time_version
#######################################
if [[ $# -lt 1 ]]; then
    [ -d "result" ] || error_exit "result/ directory not found"
    time_version=$(ls -t result/ | head -1)
    [[ -n "${time_version}" ]] || error_exit "No directories found under result/"
    log "No argument given. Using latest: ${time_version}"
else
    time_version="$1"
fi

summary_name="${2:-summary.txt}"
logdir="result/${time_version}"
summary_file="${logdir}/${summary_name}"

[ -d "${logdir}" ] || error_exit "Directory ${logdir} not found"

#######################################
# DRY_RUN=2: skip all
#######################################
if [[ "${DRY_RUN}" -ge 2 ]]; then
    log "[DRY-RUN:2] Would write summary to ${summary_file}"
    exit 0
fi

#######################################
# Header
#######################################
log "Writing summary to ${summary_file}"

> "${summary_file}"
echo "Regression Summary (${time_version})" >> "${summary_file}"
echo "==================================" >> "${summary_file}"
printf "%-20s %-5s\n" "Test" "Result"    >> "${summary_file}"
echo "----------------------------------" >> "${summary_file}"

#######################################
# Count
#######################################
pass_count=0
fail_count=0
total_count=0

log "Scanning log files in ${logdir}"

for logfile in "${logdir}"/*.log; do
    [ -f "${logfile}" ] || continue
    total_count=$(( total_count + 1 ))

    testname=$(basename "${logfile}" .log)

    if grep -q "FAIL" "${logfile}"; then
        result="FAIL"
        fail_count=$(( fail_count + 1 ))
    else
        result="PASS"
        pass_count=$(( pass_count + 1 ))
    fi

    log "  [${total_count}] ${testname}: ${result}"
    printf "%-20s %-5s\n" "${testname}" "${result}" >> "${summary_file}"
done

log "Scan complete: total=${total_count} pass=${pass_count} fail=${fail_count}"

#######################################
# Footer
#######################################
echo ""                      >> "${summary_file}"
echo "Total: ${total_count}" >> "${summary_file}"
echo "PASS : ${pass_count}"  >> "${summary_file}"
echo "FAIL : ${fail_count}"  >> "${summary_file}"

#######################################
# Fail Details
#######################################
if [[ "${fail_count}" -gt 0 ]]; then
    echo ""                              >> "${summary_file}"
    echo "Fail Details:"                >> "${summary_file}"
    echo "----------------------------------" >> "${summary_file}"

    for logfile in "${logdir}"/*.log; do
        [ -f "${logfile}" ] || continue

        if grep -q "FAIL" "${logfile}"; then
            echo "$(basename "${logfile}"):" >> "${summary_file}"
            grep "FAIL" "${logfile}"         >> "${summary_file}"
        fi
    done
fi

log "Summary written to ${summary_file}"
