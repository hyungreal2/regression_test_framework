#!/bin/bash

set -euo pipefail

[[ -n "${script_dir:-}" ]] || { echo "ERROR: script_dir is not set. Run via func_main.sh." >&2; exit 1; }
source "${script_dir}/code/env.sh"
source "${script_dir}/code/common.sh"

#######################################
# Functional test summary.
#
# Judges the per-test RESULT files that the replay writes through fd
# (result/<result_folder_id>/test_<NNN>_<ver>.log, see func_template.il),
# not the vse_run session log in CDS_log/. Same rules, order and messages
# as legacy 3_func_sp/code/summary.sh:
#   1. no "End Time" line                         -> FAIL "Log isn't fully scripted"
#   2. a "=== ... ===" section without any Row_ line -> FAIL "Expected row mismatch"
#   3. a FAIL token                               -> FAIL ("Check out FAIL" / "Check in FAIL"
#                                                    are reported as *WARNING*, others "Fail detected")
#   otherwise PASS.
# Exit status is 0 whatever the verdicts are (as in legacy); it is non-zero
# only when the summary itself could not be produced.
# Addition over legacy: with -t, a selected test that left no result file at
# all (Virtuoso did not start, or died before outfile()) is counted as FAIL.
#######################################

print_help() {
    cat <<EOF
Usage: $(basename "$0") [-d level] [-t "<test numbers>"] <mode> <uniqueid> <result_folder_id> [summary_file_name]

  -d | --dry-run [n]    Dry-run level 0/1/2
  -t | --tests "<n..>"  Selected test numbers (space or comma separated);
                        a test without a result file is reported as FAIL
EOF
}

#######################################
# Parse args
#######################################
expected_tests=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) print_help; exit 0 ;;
        -d|--dry-run)
            if [[ "${2:-}" =~ ^[012]$ ]]; then DRY_RUN="$2"; shift 2
            else DRY_RUN=2; shift; fi ;;
        -t|--tests) expected_tests="${2:-}"; shift 2 ;;
        -*) error_exit "Unknown option: $1" ;;
        *)  break ;;
    esac
done

export DRY_RUN

[[ $# -ge 3 ]] || error_exit "Usage: $0 [-d level] [-t \"<tests>\"] <mode> <uniqueid> <result_folder_id> [summary_file_name]"
mode="$1"
uniqueid="$2"
result_folder_id="$3"
summary_name="${4:-summary.txt}"

resdir="${script_dir}/result/${result_folder_id}"
summary_file="${resdir}/${summary_name}"

if [[ "${DRY_RUN}" -ge 2 ]]; then
    log "[DRY-RUN:2] Would write func summary (${mode} / ${uniqueid}) to ${summary_file}"
    exit 0
fi

if [[ ! -d "${resdir}" ]]; then
    if [[ "${DRY_RUN}" -ge 1 ]]; then
        log "[DRY-RUN:1] result dir not found (Virtuoso skipped): ${resdir}"
        exit 0
    fi
    warn "Result directory not found (no test wrote a result log): ${resdir}"
    mkdir -p "${resdir}"
fi

#######################################
# Legacy section check (3_func_sp/code/summary.sh:31-44, unchanged):
# prints 1 when a "=== ... ===" section has no Row_ line, else 0.
#######################################
_missing_row() {
    awk '
        BEGIN { err=0; in_sec=0; seen=0 }
        /^[[:space:]]*===.*===/ {
                if (in_sec == 1 && seen == 0) { err=1; exit }
                in_sec=1; seen=0
        }
        /Row_/ {
                if (in_sec == 1) seen = 1
        }
        END {
                if (in_sec == 1 && seen == 0) err=1
                print err
        }
    ' "$1"
}

# Verdict reason for one result log (empty = PASS). Order = legacy.
_fail_reason() {
    local f="$1"
    if ! grep -q "End Time" "${f}"; then
        echo "Log isn't fully scripted"
    elif [[ "$(_missing_row "${f}")" == "1" ]]; then
        echo "Expected row mismatch"
    elif grep -q "Check out FAIL" "${f}"; then
        echo "*WARNING* Check out Fail detected"
    elif grep -q "Check in FAIL" "${f}"; then
        echo "*WARNING* Check in Fail detected"
    elif grep -q "FAIL" "${f}"; then
        echo "Fail detected"
    fi
}

#######################################
# Selected tests that left no result file (DRY_RUN=0 only:
# at level 1 Virtuoso is mocked and writes no result logs)
#######################################
missing_tests=()
if [[ -n "${expected_tests}" && "${DRY_RUN}" -eq 0 ]]; then
    declare -A have=()
    for f in "${resdir}"/test_*.log; do
        [[ -f "${f}" ]] || continue
        n=$(basename "${f}")
        n="${n#test_}"; n="${n%%_*}"
        [[ "${n}" =~ ^[0-9]+$ ]] && have[$((10#${n}))]=1
    done
    for t in ${expected_tests//,/ }; do
        [[ -n "${have[$((10#${t}))]:-}" ]] || missing_tests+=("${t}")
    done
fi

log "Writing func summary (${mode} / ${uniqueid}) to ${summary_file}"

pass_count=0
fail_count=0
total_count=0
fail_lines=()

{
    echo "Regression Summary (${result_folder_id})"
    echo "=================================="
    printf "%-20s %-5s\n" "Test" "Result"
    echo "----------------------------------"

    for logfile in "${resdir}"/test_*.log; do
        [[ -f "${logfile}" ]] || continue
        total_count=$(( total_count + 1 ))
        testname=$(basename "${logfile}" .log)
        reason=$(_fail_reason "${logfile}")
        case "${reason}" in
            "")
                result="PASS"; pass_count=$(( pass_count + 1 )) ;;
            *)
                result="FAIL"; fail_count=$(( fail_count + 1 ))
                fail_lines+=("$(basename "${logfile}") : ${reason}") ;;
        esac
        printf "%-20s %-5s\n" "${testname}" "${result}"
    done

    for t in "${missing_tests[@]}"; do
        total_count=$(( total_count + 1 ))
        fail_count=$(( fail_count + 1 ))
        printf "%-20s %-5s\n" "test_${t}" "FAIL"
        fail_lines+=("test_${t} : No result log (Virtuoso did not run or stopped before writing it)")
    done

    echo ""
    echo "Total: ${total_count}"
    echo "PASS : ${pass_count}"
    echo "FAIL : ${fail_count}"

    if [[ "${fail_count}" -gt 0 ]]; then
        echo ""
        echo "Fail Lists:"
        echo "----------------------------------"
        for l in "${fail_lines[@]}"; do
            echo "${l}"
        done
    fi
} | tee "${summary_file}"

log "Func summary written to ${summary_file}"
