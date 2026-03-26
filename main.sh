#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/code/env.sh"
source "$(dirname "$0")/code/common.sh"

#######################################
# Defaults
#######################################
max=${MAX_CASES}
cases=""
libname="MS01"
cellname="XE_FULLCHIP_BASE"

max_set=false
cases_set=false
jobs=4

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
  -c     | --cases <list>     Comma-separated tests  (e.g. 1,2,3)
  -j     | --jobs <n>         Parallel jobs          (default: ${jobs})
  -d     | --dry-run [n]      Dry-run level 0/1/2    (default: 2)
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
        [[ ${cases} =~ ^[0-9]+(,[0-9]+)*$ ]] || \
            error_exit "--cases format invalid (e.g. 1,2,3)"
    fi
}

#######################################
# Generate templates
#######################################
generate_templates() {
    run_cmd "rm -f code/date_virtuosoVer.txt"

    if [[ -n "${cellname}" ]]; then
        run_cmd "python3 code/generate_templates.py --libname ${libname} --cellname ${cellname}"
    else
        run_cmd "python3 code/generate_templates.py --libname ${libname}"
    fi
}

#######################################
# Determine tests
#######################################
get_tests() {
    if [[ ${cases_set} == true ]]; then
        IFS=',' read -ra nums <<< "${cases}"

        declare -A seen=()
        tests=()

        for n in "${nums[@]}"; do
            [[ -z ${seen[$n]:-} ]] && {
                tests+=("${n}")
                seen[$n]=1
            }
        done
    else
        tests=($(seq 1 "${max}"))
    fi
}

#######################################
# Create regression directory
#######################################
create_regression_dir() {
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

        run_cmd "mkdir -p ${testdir}"
        run_cmd "mv -f ./code/replay_files/replay_${num}.il ${testdir}/"
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
# Teardown all tests
#######################################
teardown_all() {
    log "Starting teardown for all tests in ${regression_dir}"

    for testdir in "${regression_dir}"/test_*/; do
        [[ -f "${testdir}/uniqueid.txt" ]] || { warn "No uniqueid.txt in ${testdir}, skipping"; continue; }

        export uniqueid=$(<"${testdir}/uniqueid.txt")
        log "Tearing down ${testdir} (uniqueid=${uniqueid})"

        bash "$(dirname "$0")/code/teardown.sh"
    done

    log "All teardowns completed."
}

#######################################
# Main
#######################################
log "START (dry-run=${DRY_RUN})"

#######################################
# Generate unique ID
#######################################
uniqueid="$(date +%Y%m%d_%H%M%S)_$$"
export uniqueid
log "uniqueid: ${uniqueid}"

validate_inputs
generate_templates
get_tests
create_regression_dir
prepare_tests
export libname
export regression_dir
run_tests

log "All tests finished."

teardown_all
