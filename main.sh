#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"

source "${script_dir}/code/env.sh"
source "${script_dir}/code/common.sh"

#######################################
# Log file
#######################################
mkdir -p "${script_dir}/log"
logfile="${script_dir}/log/main.log.$(date +%Y%m%d_%H%M%S).txt"
exec > >(tee "${logfile}") 2>&1
log "Logging to ${logfile}"

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
do_teardown=false
teardown_worker_pid=""
main_done_flag=""

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
  -ws    | --ws_name <name>   Workspace name         (default: ${WS_PREFIX})
  -proj  | --proj_prefix <p>  Project prefix         (default: ${PROJ_PREFIX})
  -cell  | --cell <name>      Cell name              (default: ${cellname})
  -m     | --max <n>          Max test number 1-240  (default: ${MAX_CASES})
  -c     | --cases <list>     Tests: comma-sep or ranges (e.g. 1,3,5-9)
  -j     | --jobs <n>         Parallel jobs          (default: ${jobs})
  -d     | --dry-run [n]      Dry-run level 0/1/2    (default: 2)
  -t     | --teardown         Run teardown after all tests
EOF
}

#######################################
# Parse args
#######################################
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            print_help
            exit 0
            ;;
        -ws|--ws_name)
            WS_PREFIX="$2"
            shift 2
            ;;
        -proj|--proj_prefix)
            PROJ_PREFIX="$2"
            shift 2
            ;;
        -cell|--cell)
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
            max="$2"
            max_set=true
            shift 2
            ;;
        -c|--cases)
            cases="$2"
            cases_set=true
            shift 2
            ;;
        -j|--jobs)
            jobs="$2"
            shift 2
            ;;
        -t|--teardown)
            do_teardown=true
            shift
            ;;
        *)
            error_exit "Unknown option: $1"
            ;;
    esac
done

export DRY_RUN WS_PREFIX PROJ_PREFIX

#######################################
# Validate inputs
#######################################
validate_inputs() {
    if [[ ${max_set} == true && ${cases_set} == true ]]; then
        error_exit "--max and --cases cannot be used together."
    fi

    if [[ ${max_set} == true ]]; then
        [[ ${max} =~ ^[0-9]+$ ]] || error_exit "--max must be a positive integer."
        (( max <= MAX_CASES )) || error_exit "--max cannot exceed ${MAX_CASES}."
    fi

    if [[ ${cases_set} == true ]]; then
        [[ ${cases} =~ ^[0-9]+(-[0-9]+)?(,[0-9]+(-[0-9]+)?)*$ ]] || \
            error_exit "--cases format invalid (e.g. 1,3,5-9)"
    fi
}

#######################################
# Generate templates
#######################################
generate_templates() {
    log "Removing date_virtuosoVer.txt"
    run_cmd "rm -f code/date_virtuosoVer.txt"

    log "Removing previous replay folder: code/${replays_folder}"
    run_cmd "rm -rf code/${replays_folder}"

    log "Generating replay templates (libname=${libname} cellname=${cellname:-none})"
    if [[ -n "${cellname}" ]]; then
        run_cmd "python3 code/generate_templates.py --result_folder ${uniqueid} --libname ${libname} --results ${replays_folder} --cellname ${cellname}"
    else
        run_cmd "python3 code/generate_templates.py --result_folder ${uniqueid} --libname ${libname} --results ${replays_folder}"
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
                [[ -z ${seen[${token}]:-} ]] && { tests+=("${token}"); seen[${token}]=1; }
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
    local dir
    num="000"

    if [[ -f regression_num.txt ]]; then
        num=$(<regression_num.txt)
    fi

    while true; do
        num=$(printf "%03d" $(( (10#${num} + 1) % 1000 )))
        dir="regression_test_${num}"

        [[ ! -d "${dir}" ]] && break
    done

    echo "${num}" > regression_num.txt
    regression_dir="${dir}"

    log "Regression Directory: ${regression_dir}"
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
        run_cmd "mv -f ./code/${replays_folder}/replay_${num}.il ${testdir}/"
    done
}

#######################################
# Run tests
#######################################
run_tests() {
    log "Running tests in parallel (jobs=${jobs})"

    printf "%s\n" "${tests[@]}" | \
	xargs -n1 -P"${jobs}" bash ./code/run_single_test.sh
    #printf "%s\n" "${tests[@]}" | \
        #xargs -n1 -P"${jobs}" -I{} \
        #bash ./code/run_single_test.sh {} "${libname}" "${regression_dir}"
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

validate_inputs
generate_templates
get_tests
create_regression_dir
prepare_tests
mkdir -p CDS_log

#######################################
# Start background teardown worker
#######################################
teardown_queue_file="${regression_dir}/teardown_queue.txt"
main_done_flag="${regression_dir}/main_done.flag"

if [[ "${do_teardown}" == true ]]; then
    touch "${teardown_queue_file}"
    log "Starting background teardown worker"
    bash "${script_dir}/code/teardown_worker.sh" \
        "${teardown_queue_file}" "${main_done_flag}" &
    teardown_worker_pid=$!
    export teardown_queue_file
fi

export libname regression_dir
run_tests

log "All tests finished."

#######################################
# Summary
#######################################
log "Generating summary for result/${uniqueid}"
bash "${script_dir}/code/summary.sh" -d "${DRY_RUN}" "${uniqueid}"

if [[ "${do_teardown}" == true ]]; then
    log "Signaling teardown worker: main done"
    touch "${main_done_flag}"
    log "Waiting for teardown worker to finish (pid=${teardown_worker_pid})"
    wait "${teardown_worker_pid}"
    teardown_worker_pid=""  # prevent _cleanup from wait-ing again
    log "Teardown worker finished."
fi
