#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
export script_dir

source "${script_dir}/code/env.sh"
source "${script_dir}/code/common.sh"

# -h only prints help: decide before the log file is created
_help_only=false
for _a in "$@"; do [[ "${_a}" == "-h" || "${_a}" == "--help" ]] && _help_only=true; done

#######################################
# Log file
#######################################
if [[ "${_help_only}" != true ]]; then
mkdir -p "${script_dir}/log"
logfile="${script_dir}/log/main.log.$(date +%Y%m%d_%H%M%S).txt"
exec > >(tee "${logfile}") 2>&1
log "Logging to ${logfile}"
fi

#######################################
# Defaults
#######################################
max=${MAX_CASES}
cases=""
libname="${LIBNAME}"
cellname="${CELLNAME}"

max_set=false
cases_set=false
jobs=4
do_teardown=true        # legacy: every test is torn down; -k/--keep skips it
keep_artifacts=false    # legacy -debug: keep regression_test_NNN and code/replay_files_*
teardown_worker_pid=""
main_done_flag=""
dryrun_queue_dir=""
tests_rc=0
summary_rc=0
teardown_rc=0

#######################################
# Trap: ensure worker is always cleaned
# up on exit (normal, error, or signal)
#######################################
_cleanup() {
    if [[ -n "${main_done_flag}" && ! -f "${main_done_flag}" ]]; then
        log "TRAP: signaling teardown worker (main_done_flag=${main_done_flag})"
        touch "${main_done_flag}" 2>/dev/null || true
    fi
    if [[ -n "${teardown_worker_pid}" ]]; then
        wait "${teardown_worker_pid}" 2>/dev/null || true
    fi
    if [[ -n "${dryrun_queue_dir}" ]]; then
        rm -rf "${dryrun_queue_dir}" 2>/dev/null || true
    fi
    flush_trash || true
}
trap '_cleanup' EXIT INT TERM

#######################################
# Help
#######################################
print_help() {
    cat <<EOF
Usage: $(basename "$0") [options]

Options:
  -h     | --help             Print this help message
  -lib   | --library <name>   Library name           (default: ${libname})
  -ws    | --ws_name <name>   Workspace name         (default: ${WS_PREFIX})
  -proj  | --proj_prefix <p>  Project prefix         (default: ${PROJ_PREFIX})
  -cell  | --cell <name>      Cell name              (default: ${cellname})
  -m     | --max <n>          Max test number 1-${MAX_CASES}  (default: ${MAX_CASES})
  -c     | --cases <list>     Tests: comma-sep or ranges (e.g. 1,3,5-9)
  -j     | --jobs <n>         Parallel jobs          (default: ${jobs})
  -d     | --dry-run [n]      Dry-run level 0/1/2    (default: ${DRY_RUN}; -d alone = 2)
  -k     | --keep             Skip teardown: keep GDP projects/workspaces/p4 clients
                              (alias: --no-teardown; tear down later with
                              code/teardown_all.sh <regression_dir>)
  -t     | --teardown         Teardown after tests (default: on; kept for compatibility)
  -debug | -keep-artifacts    Keep regression_test_NNN and code/replay_files_<id>
                              (default: both are deleted after a successful teardown)

Test numbers are line numbers of code/list: 1-144 are the legacy 144 cases
in legacy order, 145-256 are the Fast-series cases.

Exit status: non-zero if a test could not run (init or Virtuoso failed), the
summary crashed or a teardown failed. PASS/FAIL verdicts are not reflected
(as in legacy); read result/<id>/summary.txt for them.
EOF
}

#######################################
# Parse args
#######################################
# need_arg "$@": the option in $1 must be followed by a value
need_arg() {
    [[ -n "${2:-}" && "${2}" != -* ]] || error_exit "$1 requires a value"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            print_help
            exit 0
            ;;
        -lib|--library)
            need_arg "$@"
            libname="$2"
            shift 2
            ;;
        -ws|--ws_name)
            need_arg "$@"
            WS_PREFIX="$2"
            shift 2
            ;;
        -proj|--proj_prefix)
            need_arg "$@"
            PROJ_PREFIX="$2"
            shift 2
            ;;
        -cell|--cell)
            need_arg "$@"
            cellname="$2"
            shift 2
            ;;
        -d|--dry-run)
            if [[ "${2:-}" =~ ^[012]$ ]]; then
                DRY_RUN="$2"
                shift 2
            else
                DRY_RUN=2
                shift
            fi
            ;;
        -m|--max)
            need_arg "$@"
            max="$2"
            max_set=true
            shift 2
            ;;
        -c|--cases)
            need_arg "$@"
            cases="$2"
            cases_set=true
            shift 2
            ;;
        -j|--jobs)
            [[ "${2:-}" =~ ^[1-9][0-9]*$ ]] || error_exit "-j requires a positive integer"
            jobs="$2"
            shift 2
            if (( jobs > MAX_JOBS )); then
                log "WARNING: -j ${jobs} exceeds MAX_JOBS (${MAX_JOBS}); clamping to ${MAX_JOBS}"
                jobs=${MAX_JOBS}
            fi
            ;;
        -t|--teardown)
            # Teardown is the default; kept so existing callers still work
            do_teardown=true
            shift
            ;;
        -k|--keep|--no-teardown)
            do_teardown=false
            shift
            ;;
        -debug|-keep-artifacts|--keep-artifacts)
            keep_artifacts=true
            shift
            ;;
        *)
            error_exit "Unknown option: $1"
            ;;
    esac
done

export DRY_RUN WS_PREFIX PROJ_PREFIX
export CAT_WS_PREFIX="${WS_PREFIX}" CAT_PROJ_PREFIX="${PROJ_PREFIX}"   # children re-source env.sh

#######################################
# Start condition
#######################################
if [[ "${DRY_RUN}" -lt 2 ]]; then
    [[ -n "${ICM_SkillRoot:-}" ]] || error_exit "ICM_SkillRoot is not set (required for GDP/Virtuoso)"
fi

#######################################
# Validate inputs
#######################################
validate_inputs() {
    if [[ ${max_set} == true && ${cases_set} == true ]]; then
        error_exit "--max and --cases cannot be used together."
    fi

    if [[ ${max_set} == true ]]; then
        [[ ${max} =~ ^[0-9]+$ ]] || error_exit "--max must be a positive integer."
        (( 10#${max} >= 1 && 10#${max} <= MAX_CASES )) || error_exit "--max must be between 1 and ${MAX_CASES}."
    fi

    if [[ ${cases_set} == true ]]; then
        [[ ${cases} =~ ^[0-9]+(-[0-9]+)?(,[0-9]+(-[0-9]+)?)*$ ]] || \
            error_exit "--cases format invalid (e.g. 1,3,5-9)"
        # Any line of code/list may be selected (dev MAX_CASES=144 can still
        # run the Fast-series cases 145-256 with -c)
        local list_lines n
        list_lines=$(grep -c . "${script_dir}/code/list")
        for n in ${cases//[,-]/ }; do
            (( 10#${n} >= 1 && 10#${n} <= list_lines )) \
                || error_exit "--cases: ${n} is out of range (1-${list_lines}, lines of code/list)"
        done
    fi
}

#######################################
# Ensure GDP base folders exist
#######################################
ensure_gdp_folders() {
    local folder
    for folder in "${GDP_BASE}" "${CICO_GDP_BASE}"; do
        if [[ "${DRY_RUN}" -ge 1 ]]; then
            # L2 prints [DRY-RUN:2], L1 prints [SKIP:1]
            run_cmd "gdp create folder \"${folder}\""
            continue
        fi
        log "Checking GDP folder: ${folder}"
        # gdp list is a value lookup, not a state change: called directly
        if [[ -n "$(gdp list "${folder}" 2>/dev/null)" ]]; then
            log "  → exists: ${folder}"
        else
            log "  → not found, creating: ${folder}"
            run_cmd "gdp create folder \"${folder}\"" || error_exit "Failed to create GDP folder: ${folder}"
        fi
    done
}

#######################################
# Generate templates
#######################################
generate_templates() {
    log "Removing date_virtuosoVer.txt"
    run_cmd "rm -f \"${script_dir}/code/date_virtuosoVer.txt\""

    log "Removing previous replay folder: code/${replays_folder}"
    run_cmd "rm -rf \"${script_dir}/code/${replays_folder}\""

    log "Generating replay templates (libname=${libname} cellname=${cellname:-none})"
    if [[ -n "${cellname}" ]]; then
        run_cmd "python3 \"${script_dir}/code/generate_templates.py\" --result_folder ${result_folder_id} --libname ${libname} --results ${replays_folder} --cellname ${cellname}"
    else
        run_cmd "python3 \"${script_dir}/code/generate_templates.py\" --result_folder ${result_folder_id} --libname ${libname} --results ${replays_folder}"
    fi
}

#######################################
# Determine tests
#######################################
get_tests() {
    declare -A seen=()
    tests=()

    if [[ ${cases_set} == true ]]; then
        IFS=',' read -ra tokens <<< "${cases}"

        for token in "${tokens[@]}"; do
            if [[ "${token}" =~ ^([0-9]+)-([0-9]+)$ ]]; then
                local start="${BASH_REMATCH[1]}" end="${BASH_REMATCH[2]}"
                (( 10#${start} <= 10#${end} )) || error_exit "Invalid range in --cases: ${token}"
                for (( n=10#${start}; n<=10#${end}; n++ )); do
                    [[ -z ${seen[${n}]:-} ]] && { tests+=("${n}"); seen[${n}]=1; }
                done
            else
                [[ "${token}" =~ ^[0-9]+$ ]] || error_exit "Invalid case in --cases: ${token}"
                n=$(( 10#${token} ))   # "08" must not be read as octal
                [[ -z ${seen[${n}]:-} ]] && { tests+=("${n}"); seen[${n}]=1; }
            fi
        done
    else
        tests=($(seq 1 "${max}"))
    fi
}

#######################################
# Create regression directory
#######################################
create_regression_dir() {
    # The directory is claimed with an atomic mkdir (no -p), so two runs
    # started together (also by different users of one deployment) can
    # never share a regression dir, its teardown queue or its cleanup.
    local dir n="000" attempt

    if [[ -f "${script_dir}/regression_num.txt" ]]; then
        n=$(<"${script_dir}/regression_num.txt")
        [[ "${n}" =~ ^[0-9]{1,3}$ ]] || n="000"
    fi

    for (( attempt = 0; attempt < 1000; attempt++ )); do
        n=$(printf "%03d" $(( (10#${n} + 1) % 1000 )))
        dir="${script_dir}/regression_test_${n}"
        if [[ "${DRY_RUN}" -ge 2 ]]; then
            [[ -e "${dir}" ]] && continue          # level 2: compute only, create nothing
        else
            mkdir "${dir}" 2>/dev/null || continue # taken (or a racing run won it)
            echo "${n}" > "${script_dir}/regression_num.txt"
        fi
        num="${n}"
        regression_dir="${dir}"
        log "Regression Directory: ${regression_dir}"
        return 0
    done
    error_exit "All regression_test_000..999 exist; remove old ones (./clean.sh or code/teardown_all.sh <dir>)"
}

#######################################
# Prepare test directories
#######################################
prepare_tests() {
    for i in "${tests[@]}"; do
        num=$(format_num "${i}")
        testdir="${regression_dir}/test_${num}"

        log "Preparing test ${num}: ${testdir}"
        run_cmd "mkdir -p ${testdir}"

        log "Moving replay_${num}.il to ${testdir}/"
        run_cmd "mv -f \"${script_dir}/code/${replays_folder}/replay_${num}.il\" \"${testdir}/\""
    done
}

#######################################
# Run tests
#######################################
run_tests() {
    log "Running tests in parallel (jobs=${jobs})"

    # Capture the xargs status instead of letting set -e stop main.sh:
    # the summary must run even when tests fail (legacy behaviour).
    local _rc=0
    printf "%s\n" "${tests[@]}" | \
        xargs -n1 -P"${jobs}" bash "${script_dir}/code/run_single_test.sh" || _rc=$?
    case "${_rc}" in
        0)   ;;
        123) warn "Some tests failed (xargs rc=123); continuing to summary" ;;
        *)   warn "xargs itself failed (rc=${_rc}); continuing to summary" ;;
    esac
    return "${_rc}"
}

#######################################
# Main
#######################################
log "START (dry-run=${DRY_RUN})"

#######################################
# Generate unique ID
#######################################
uniqueid="$(date +%Y%m%d_%H%M%S)_${USER_NAME}_${libname}"
[[ -n "${cellname}" ]] && uniqueid="${uniqueid}_${cellname}"
replays_folder="replay_files_${uniqueid}"
export uniqueid
log "uniqueid: ${uniqueid}"
log "replays_folder: ${replays_folder}"

get_tool_versions
result_folder_id="${uniqueid}"
[[ -n "${gdpver:-}" ]] && result_folder_id="${result_folder_id}_${gdpver}"
[[ -n "${gdmver:-}" ]] && result_folder_id="${result_folder_id}_${gdmver}"
log "result_folder_id: ${result_folder_id}"

validate_inputs
ensure_gdp_folders
generate_templates
get_tests
create_regression_dir
prepare_tests
mkdir -p "${script_dir}/CDS_log"

#######################################
# Teardown queue + background worker
# The queue is always written (run_single_test.sh appends one
# uniquetestid per test), so a -k run can be torn down later:
#   code/teardown_all.sh <regression_dir>
# DRY_RUN=2 creates nothing under regression_dir (its mkdir was only
# printed), so the queue lives in a throwaway dir under log/ there.
#######################################
if [[ "${DRY_RUN}" -ge 2 ]]; then
    dryrun_queue_dir="$(mktemp -d "${script_dir}/log/.dryrun_queue.XXXXXX")"
    queue_dir="${dryrun_queue_dir}"
else
    queue_dir="${regression_dir}"
    mkdir -p "${queue_dir}"
fi
teardown_queue_file="${queue_dir}/teardown_queue.txt"
main_done_flag="${queue_dir}/main_done.flag"
touch "${teardown_queue_file}"
# Prefixes of this run, so teardown_all.sh finds -ws/-proj names later
printf 'WS_PREFIX=%s\nPROJ_PREFIX=%s\n' "${WS_PREFIX}" "${PROJ_PREFIX}" > "${queue_dir}/run_prefixes"

export libname regression_dir teardown_queue_file

if [[ "${do_teardown}" == true ]]; then
    log "Starting background teardown worker"
    bash "${script_dir}/code/teardown_worker.sh" \
        "${teardown_queue_file}" "${main_done_flag}" "${script_dir}/code/teardown.sh" &
    teardown_worker_pid=$!
else
    log "Teardown disabled (-k/--keep): GDP projects/workspaces/p4 clients will be kept"
    # marker for clean.sh / teardown_all.sh: every queued id still needs teardown
    [[ "${DRY_RUN}" -ge 2 ]] || echo "teardown skipped (-k); ids in teardown_queue.txt" \
        > "${regression_dir}/teardown_skipped"
fi

run_tests || tests_rc=$?

log "All tests finished (rc=${tests_rc})."

#######################################
# Detect tests with missing CDS log
#######################################
if [[ "${DRY_RUN}" -eq 0 ]]; then
    _missing=()
    for _t in "${tests[@]}"; do
        _n=$(format_num "${_t}")
        [[ -f "${script_dir}/CDS_log/${uniqueid}/CDS_${_n}.log" ]] || _missing+=("${_n}")
    done
    if [[ ${#_missing[@]} -gt 0 ]]; then
        warn "Tests with no CDS log (Virtuoso did not run): ${_missing[*]}"
    else
        log "All ${#tests[@]} tests produced a CDS log."
    fi
fi

#######################################
# Summary (always runs, even if tests failed)
#######################################
log "Generating summary for CDS_log/${uniqueid}"
bash "${script_dir}/code/summary.sh" -d "${DRY_RUN}" \
    --logdir "${script_dir}/result/${result_folder_id}" "${result_folder_id}" \
    || { summary_rc=$?; warn "summary.sh failed (rc=${summary_rc})"; }

#######################################
# Wait for the teardown worker
#######################################
log "Signaling teardown worker: main done"
touch "${main_done_flag}"
main_done_flag=""  # signaled; the trap need not touch it again (the dir may be removed below)
if [[ -n "${teardown_worker_pid}" ]]; then
    log "Waiting for teardown worker to finish (pid=${teardown_worker_pid})"
    wait "${teardown_worker_pid}" || teardown_rc=$?
    teardown_worker_pid=""  # prevent _cleanup from wait-ing again
    if [[ ${teardown_rc} -ne 0 ]]; then
        warn "Teardown worker exited rc=${teardown_rc}; some teardowns failed (see log above)"
    else
        log "Teardown worker finished."
    fi
fi

#######################################
# Artifacts (legacy: deleted unless -debug)
# Deleted only after a successful teardown: teardown_all.sh needs
# regression_dir to find leftover workspaces.
#######################################
if [[ "${do_teardown}" == true && ${teardown_rc} -eq 0 && "${keep_artifacts}" == false ]]; then
    if [[ "${DRY_RUN}" -eq 0 ]]; then
        log "Removing ${regression_dir} and code/${replays_folder}"
        # Not fatal: the exit status below must still reflect the run
        safe_rm_rf "${regression_dir}" || warn "Could not remove ${regression_dir}"
        safe_rm_rf "${script_dir}/code/${replays_folder}" || warn "Could not remove code/${replays_folder}"
    else
        log "[DRY-RUN:${DRY_RUN}] Would remove ${regression_dir} and code/${replays_folder}"
    fi
else
    log "Artifacts kept: ${regression_dir} and code/${replays_folder}"
    if [[ "${do_teardown}" != true || ${teardown_rc} -ne 0 ]]; then
        log "  GDP leftovers can be torn down with: ${script_dir}/code/teardown_all.sh ${regression_dir}"
    fi
    log "  Remove manually with: rm -rf ${regression_dir} ${script_dir}/code/${replays_folder}"
fi

#######################################
# Exit status: test failures first, then summary, then teardown
#######################################
final_rc=${tests_rc}
[[ ${final_rc} -ne 0 ]] || final_rc=${summary_rc}
[[ ${final_rc} -ne 0 ]] || final_rc=${teardown_rc}
log "DONE (rc=${final_rc})"
exit "${final_rc}"
