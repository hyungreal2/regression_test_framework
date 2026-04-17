#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
export script_dir

source "${script_dir}/code/env.sh"
source "${script_dir}/code/common.sh"

#######################################
# Log file
#######################################
mkdir -p "${script_dir}/log"
logfile="${script_dir}/log/perf_main.log.$(date +%Y%m%d_%H%M%S).txt"
exec > >(tee "${logfile}") 2>&1
log "Logging to ${logfile}"

#######################################
# Defaults
#######################################
jobs=4
do_teardown=false
selected_libs=()
selected_tests=()
selected_modes=(managed unmanaged)
teardown_worker_pid=""

#######################################
# Trap: ensure any background work
# is always waited on exit
#######################################
_cleanup() {
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
  -h  | --help               Print this help message
  -lib  <lib[,lib...]>       Libraries to test (default: all — ${PERF_LIBS[*]})
  -test <test[,test...]>     Test types     (default: all — ${PERF_TESTS[*]})
  -mode <managed|unmanaged>  Mode           (default: both)
  -j  | --jobs <n>           Parallel jobs  (default: ${jobs})
  -d  | --dry-run [n]        Dry-run level 0/1/2 (default: 2)
  -t  | --teardown           Run teardown after all tests
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
        -lib)
            IFS=',' read -ra selected_libs <<< "$2"
            shift 2
            ;;
        -test)
            IFS=',' read -ra selected_tests <<< "$2"
            shift 2
            ;;
        -mode)
            selected_modes=("$2")
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
        -j|--jobs)
            [[ "${2:-}" =~ ^[0-9]+$ ]] || error_exit "-j requires a positive integer"
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

export DRY_RUN

#######################################
# Helper: cell lookup
#######################################
get_cell() {
    local l="$1"
    for i in "${!PERF_LIBS[@]}"; do
        [[ "${PERF_LIBS[$i]}" == "${l}" ]] && { echo "${PERF_CELLS[$i]}"; return; }
    done
    error_exit "No cell mapping for lib: ${l}"
}

#######################################
# Validate inputs
#######################################
validate_inputs() {
    local sl st found

    for sl in "${selected_libs[@]}"; do
        found=false
        for pl in "${PERF_LIBS[@]}"; do
            [[ "${sl}" == "${pl}" ]] && { found=true; break; }
        done
        [[ "${found}" == true ]] || error_exit "Unknown lib: ${sl} (valid: ${PERF_LIBS[*]})"
    done

    for st in "${selected_tests[@]}"; do
        found=false
        for pt in "${PERF_TESTS[@]}"; do
            [[ "${st}" == "${pt}" ]] && { found=true; break; }
        done
        [[ "${found}" == true ]] || error_exit "Unknown test: ${st} (valid: ${PERF_TESTS[*]})"
    done
}

#######################################
# Build combo arrays
#######################################
build_combos() {
    local testtype lib cell mode

    if [[ ${#selected_libs[@]} -eq 0 ]];  then active_libs=("${PERF_LIBS[@]}");  else active_libs=("${selected_libs[@]}");  fi
    if [[ ${#selected_tests[@]} -eq 0 ]]; then active_tests=("${PERF_TESTS[@]}"); else active_tests=("${selected_tests[@]}"); fi

    combos_init=()      # "testtype lib cell"  — Phase 1 generate + Phase 2 init
    combos_run=()       # "testtype lib mode"  — Phase 3 run
    combos_teardown=()  # "testtype lib"       — Phase 5 teardown

    for testtype in "${active_tests[@]}"; do
        for lib in "${active_libs[@]}"; do
            cell=$(get_cell "${lib}")
            combos_init+=("${testtype} ${lib} ${cell}")
            combos_teardown+=("${testtype} ${lib}")
            for mode in "${selected_modes[@]}"; do
                combos_run+=("${testtype} ${lib} ${mode}")
            done
        done
    done
}

#######################################
# Phase 1: Generate replays (sequential)
#######################################
generate_replays() {
    local testtype lib cell

    log "--- Phase 1: Generate replays ---"
    for combo in "${combos_init[@]}"; do
        read -r testtype lib cell <<< "${combo}"
        bash "${script_dir}/code/perf_generate_replay.sh" \
            "${testtype}" "${lib}" "${cell}" -d "${DRY_RUN}"
    done
}

#######################################
# Phase 2: Init workspaces (parallel)
#######################################
init_workspaces() {
    log "--- Phase 2: Init workspaces (jobs=${jobs}) ---"
    printf "%s\n" "${combos_init[@]}" | \
        xargs -n3 -P"${jobs}" bash -c "
            bash \"${script_dir}/code/perf_init.sh\" \"\$1\" \"\$2\" \"\$3\" \"${uniqueid}\" -d \"${DRY_RUN}\"
        " _
}

#######################################
# Phase 3: Run tests (parallel)
#######################################
run_tests() {
    log "--- Phase 3: Run tests (jobs=${jobs}) ---"
    printf "%s\n" "${combos_run[@]}" | \
        xargs -n3 -P"${jobs}" bash -c "
            bash \"${script_dir}/code/perf_run_single.sh\" \"\$1\" \"\$2\" \"\$3\" \"${uniqueid}\" -d \"${DRY_RUN}\"
        " _
}

#######################################
# Phase 5: Teardown (parallel)
#######################################
teardown_workspaces() {
    log "--- Phase 5: Teardown (jobs=${jobs}) ---"
    printf "%s\n" "${combos_teardown[@]}" | \
        xargs -n2 -P"${jobs}" bash -c "
            bash \"${script_dir}/code/perf_teardown.sh\" \"\$1\" \"\$2\" \"${uniqueid}\" -d \"${DRY_RUN}\"
        " _
    log "All teardowns completed."
}

#######################################
# Main
#######################################
log "START (dry-run=${DRY_RUN})"

uniqueid="perf_$(date +%Y%m%d_%H%M%S)_${USER_NAME}"
log "uniqueid: ${uniqueid}"

validate_inputs
build_combos
log "Matrix: ${#combos_init[@]} (testtype×lib) × ${#selected_modes[@]} modes = ${#combos_run[@]} runs"

run_cmd "mkdir -p WORKSPACES_MANAGED WORKSPACES_UNMANAGED"
run_cmd "mkdir -p result/${uniqueid} CDS_log/${uniqueid}"

if [[ "${DRY_RUN}" -lt 2 ]]; then
    echo "managed"   > WORKSPACES_MANAGED/managed.txt
    echo "unmanaged" > WORKSPACES_UNMANAGED/managed.txt
    echo "${uniqueid}" > "${script_dir}/code/date_virtuosoVer.txt"
fi

generate_replays
init_workspaces
run_tests

log "All tests finished."

log "Generating summary for result/${uniqueid}"
bash "${script_dir}/code/summary.sh" -d "${DRY_RUN}" "${uniqueid}"

if [[ "${do_teardown}" == true ]]; then
    teardown_workspaces
fi

log "perf_main.sh DONE"
