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
do_run=true
auto_init=false
selected_libs=()
selected_tests=()
selected_modes=(managed unmanaged)
teardown_worker_pid=""

session_file="${script_dir}/perf_session.txt"

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
  -h         | --help          Print this help message
  -lib         <lib[,lib...]>  Libraries to test    (default: all — ${PERF_LIBS[*]})
  -test        <test[,test...]> Test types          (default: all — ${PERF_TESTS[*]})
  -mode        <managed|unmanaged>  Mode            (default: both)
  -j         | --jobs <n>      Parallel jobs        (default: ${jobs})
  -d         | --dry-run [n]   Dry-run level 0/1/2  (default: ${DRY_RUN})
  -no-run    | --no-run        Init only; skip test execution
  -t         | --teardown      Run teardown after tests
  -auto-init | --auto-init     Auto-run init if no session exists (no prompt)

Session:
  Active session is stored in: ${session_file}
  Default behavior skips init and reuses the existing session.
  If no session exists, an interactive prompt asks whether to run init.
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
        -no-run|--no-run)
            do_run=false
            shift
            ;;
        -t|--teardown)
            do_teardown=true
            shift
            ;;
        -auto-init|--auto-init)
            auto_init=true
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
# Session: load or init
#######################################
load_or_init_session() {
    if [[ -f "${session_file}" ]]; then
        uniqueid=$(<"${session_file}")
        log "Session loaded: ${uniqueid} (from ${session_file})"
        return
    fi

    # No session — ask or auto-init
    local answer="n"
    if [[ "${auto_init}" == true ]]; then
        log "No session found. --auto-init: running init automatically."
        answer="y"
    else
        echo ""
        echo "No active session found (${session_file} does not exist)."
        echo -n "Run init to set up the environment? [y/N] "
        read -r answer
    fi

    if [[ "${answer}" =~ ^[Yy]$ ]]; then
        run_init_phases
    else
        error_exit "No session. Run with -no-run to initialise the environment first."
    fi
}

#######################################
# Save / remove session
#######################################
save_session() {
    echo "${uniqueid}" > "${session_file}"
    log "Session saved: ${uniqueid} → ${session_file}"
}

remove_session() {
    if [[ -f "${session_file}" ]]; then
        rm -f "${session_file}"
        log "Session removed: ${session_file}"
    fi
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
# Init phases (1+2): generate + init
#######################################
run_init_phases() {
    uniqueid="$(date +%Y%m%d_%H%M%S)_${USER_NAME}"
    log "uniqueid: ${uniqueid}"

    run_cmd "mkdir -p WORKSPACES_MANAGED WORKSPACES_UNMANAGED"
    run_cmd "mkdir -p result/${uniqueid} CDS_log/${uniqueid}"

    if [[ "${DRY_RUN}" -lt 2 ]]; then
        echo "${uniqueid}" > "${script_dir}/code/date_virtuosoVer.txt"
    fi

    generate_replays
    init_workspaces
    save_session
}

#######################################
# Main
#######################################
log "START (dry-run=${DRY_RUN})"

validate_inputs
build_combos
log "Matrix: ${#combos_init[@]} (testtype×lib) × ${#selected_modes[@]} modes = ${#combos_run[@]} runs"

if [[ "${do_run}" == false && "${do_teardown}" == false ]]; then
    # --no-run only: always run init phases
    run_init_phases
    log "Init complete. Run without -no-run to execute tests."
elif [[ "${do_run}" == true ]]; then
    load_or_init_session

    log "--- Phase 3: Run tests ---"
    run_tests

    log "All tests finished."
    log "Generating summary for result/${uniqueid}"
    bash "${script_dir}/code/summary.sh" -d "${DRY_RUN}" "${uniqueid}"

    if [[ "${do_teardown}" == true ]]; then
        teardown_workspaces
        remove_session
    fi
elif [[ "${do_run}" == false && "${do_teardown}" == true ]]; then
    # --no-run -t: teardown only using existing session
    if [[ ! -f "${session_file}" ]]; then
        error_exit "No session found. Cannot teardown without an active session."
    fi
    uniqueid=$(<"${session_file}")
    log "Session loaded for teardown: ${uniqueid}"
    teardown_workspaces
    remove_session
fi

log "perf_main.sh DONE"
