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
do_gen_replay=false
auto_init=false
selected_libs=()
selected_tests=()
selected_modes=(managed unmanaged)
common_libs=()
teardown_worker_pid=""

session_file="${script_dir}/perf_session.txt"
uniqueid=""
session_ws=()   # entries: "testtype lib ws_name"

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

DESCRIPTION
  Performance regression test runner with session-based workspace management.
  By default, init is skipped and the existing session is reused. If no session
  exists, an interactive prompt asks whether to run init first.

OPTIONS
  -h         | --help            Print this help message
  -lib         <lib[,lib,...]>   Comma-separated libraries to test
                                   default: all  (${PERF_LIBS[*]})
  -test        <test[,test,...]> Comma-separated test types to run
                                   default: all  (${PERF_TESTS[*]})
  -common      <lib[,lib,...]>      Comma-separated libraries added to ALL test combos
                                   These are appended to the per-testtype library set
  -mode        <managed|unmanaged>
                                 Workspace mode to run
                                   default: both managed and unmanaged
  -j         | --jobs <n>        Number of parallel jobs          (default: ${jobs})
  -d         | --dry-run [0|1|2] Dry-run level                    (default: ${DRY_RUN})
                                   0 = run everything
                                   1 = skip gdp / xlp4 / rm / vse (mock workspaces)
                                   2 = skip all commands (print only)
  -gen-replay | --gen-replay     Generate replay files only (Phase 1); no init or run
  -no-run    | --no-run          Run init phases only; skip test execution
                                   Saves session to ${session_file}
  -t         | --teardown        Run teardown after tests
                                   Removes session file when done
  -auto-init | --auto-init       If no session exists, run init automatically
                                   without prompting (useful for scripted runs)

SESSION
  The active session is stored in:
    ${session_file}

  Format (one entry per line):
    Line 1   : uniqueid (used for log/result directories)
    Line 2+  : testtype lib ws_name (one workspace per line)

  Session lifecycle:
    init only   perf_main.sh -no-run         → creates session file
    run         perf_main.sh                 → reads session file
    run+cleanup perf_main.sh -t              → reads, then removes session file
    teardown    perf_main.sh -no-run -t      → removes session file (no run)

OPTION COMBINATIONS
  The -lib, -test, and -mode options can be combined freely at run time
  to select a subset of the initialized workspaces.

  Command                                    Tests run
  ─────────────────────────────────────────  ──────────────────────────────────
  $(basename "$0")                                        all session entries × managed + unmanaged
  $(basename "$0") -lib BM02 -test checkHier              checkHier/BM02 × managed + unmanaged  (2)
  $(basename "$0") -lib BM02 -test checkHier -mode managed  checkHier/BM02/managed only          (1)
  $(basename "$0") -mode managed                          all session entries × managed only

  Note: -lib and -test filter the run against the current session.
  The session must already contain the requested lib/test combination
  (i.e. it was included when -no-run was executed).

WORKFLOW EXAMPLES
  # Generate replay files only (no workspace setup)
  $(basename "$0") -gen-replay -lib BM01 -test checkHier

  # Step 1: Set up workspaces (do once)
  $(basename "$0") -no-run -lib BM01 -test checkHier

  # Step 2: Run tests (repeat as needed)
  $(basename "$0")
  $(basename "$0") -lib BM01 -test checkHier
  $(basename "$0") -lib BM01 -test checkHier -mode managed

  # Step 3: Tear down workspaces when done
  $(basename "$0") -no-run -t

  # Run everything in one shot (init → run → teardown)
  $(basename "$0") -auto-init -t

  # Dry-run to preview commands without executing
  $(basename "$0") -d 2
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
        -gen-replay|--gen-replay)
            do_gen_replay=true
            shift
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
        -common|--common)
            IFS=',' read -ra common_libs <<< "$2"
            shift 2
            ;;
        *)
            error_exit "Unknown option: $1"
            ;;
    esac
done

export DRY_RUN
export PERF_COMMON_LIBS="${common_libs[*]:-}"

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

    for cl in "${common_libs[@]}"; do
        found=false
        for pl in "${PERF_LIBS[@]}"; do
            [[ "${cl}" == "${pl}" ]] && { found=true; break; }
        done
        [[ "${found}" == true ]] || error_exit "Unknown common lib: ${cl} (valid: ${PERF_LIBS[*]})"
    done
}

#######################################
# Build combos_init (for generate + init phases only)
#######################################
build_combos() {
    local testtype lib cell

    if [[ ${#selected_libs[@]} -eq 0 ]];  then active_libs=("${PERF_LIBS[@]}");  else active_libs=("${selected_libs[@]}");  fi
    if [[ ${#selected_tests[@]} -eq 0 ]]; then active_tests=("${PERF_TESTS[@]}"); else active_tests=("${selected_tests[@]}"); fi

    combos_init=()  # "testtype lib cell"  — Phase 1 generate + Phase 2 init

    for testtype in "${active_tests[@]}"; do
        for lib in "${active_libs[@]}"; do
            cell=$(get_cell "${lib}")
            combos_init+=("${testtype} ${lib} ${cell}")
        done
    done
}

#######################################
# Session: read from file into memory
#######################################
_read_session() {
    local lines=()
    mapfile -t lines < "${session_file}"
    uniqueid="${lines[0]}"
    session_ws=()
    local i
    for (( i=1; i<${#lines[@]}; i++ )); do
        [[ -n "${lines[$i]}" ]] && session_ws+=("${lines[$i]}")
    done
    log "Session loaded: uniqueid=${uniqueid}, ${#session_ws[@]} workspace(s)"
}

#######################################
# Session: save to file
# Format:
#   line 1  : uniqueid
#   line 2+ : testtype lib ws_name
#######################################
save_session() {
    local testtype lib cell
    {
        echo "${uniqueid}"
        for combo in "${combos_init[@]}"; do
            read -r testtype lib cell <<< "${combo}"
            echo "${testtype} ${lib} ${PERF_PREFIX}_${testtype}_${lib}_${uniqueid}"
        done
    } > "${session_file}"
    log "Session saved: ${session_file}"
    _read_session
}

#######################################
# Session: remove file
#######################################
remove_session() {
    if [[ -f "${session_file}" ]]; then
        rm -f "${session_file}"
        log "Session removed: ${session_file}"
    fi
}

#######################################
# Session: load or prompt init
#######################################
load_or_init_session() {
    if [[ -f "${session_file}" ]]; then
        _read_session
        return
    fi

    local answer
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
# Ensure GDP base folders exist
# Checks GDP_BASE and PERF_GDP_BASE in order;
# creates any that are missing.
# Skipped at DRY_RUN >= 1 (no real GDP calls).
#######################################
ensure_gdp_folders() {
    if [[ "${DRY_RUN}" -ge 1 ]]; then
        log "[DRY-RUN] Would ensure GDP folders: ${GDP_BASE}, ${PERF_GDP_BASE}"
        return
    fi

    local folder
    for folder in "${GDP_BASE}" "${PERF_GDP_BASE}"; do
        log "Checking GDP folder: ${folder}"
        if gdp list "${folder}" > /dev/null 2>&1; then
            log "  → exists: ${folder}"
        else
            log "  → not found, creating: ${folder}"
            gdp create folder "${folder}"
        fi
    done
}

#######################################
# Phase 1: Generate replays (sequential)
#######################################
generate_replays() {
    local testtype lib cell mode

    log "--- Phase 1: Generate replays (managed + unmanaged) ---"
    for combo in "${combos_init[@]}"; do
        read -r testtype lib cell <<< "${combo}"
        for mode in managed unmanaged; do
            bash "${script_dir}/code/perf_generate_replay.sh" \
                "${testtype}" "${lib}" "${cell}" "${mode}" "${uniqueid}" -d "${DRY_RUN}"
        done
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
# Combos built from session_ws × selected_modes.
# Passes ws_name explicitly so perf_run_single
# does not need to reconstruct it from uniqueid.
#######################################
run_tests() {
    local testtype lib ws_name combos_run=()
    local lib_match test_match al at

    for entry in "${session_ws[@]}"; do
        read -r testtype lib ws_name <<< "${entry}"

        # Filter by -lib (if specified)
        lib_match=true
        if [[ ${#selected_libs[@]} -gt 0 ]]; then
            lib_match=false
            for al in "${selected_libs[@]}"; do
                [[ "${lib}" == "${al}" ]] && { lib_match=true; break; }
            done
        fi
        [[ "${lib_match}" == true ]] || continue

        # Filter by -test (if specified)
        test_match=true
        if [[ ${#selected_tests[@]} -gt 0 ]]; then
            test_match=false
            for at in "${selected_tests[@]}"; do
                [[ "${testtype}" == "${at}" ]] && { test_match=true; break; }
            done
        fi
        [[ "${test_match}" == true ]] || continue

        for mode in "${selected_modes[@]}"; do
            combos_run+=("${testtype} ${lib} ${mode} ${ws_name}")
        done
    done

    log "--- Phase 3: Run tests (${#combos_run[@]} jobs, parallelism=${jobs}) ---"
    printf "%s\n" "${combos_run[@]}" | \
        xargs -n4 -P"${jobs}" bash -c "
            bash \"${script_dir}/code/perf_run_single.sh\" \"\$1\" \"\$2\" \"\$3\" \"\$4\" \"${uniqueid}\" -d \"${DRY_RUN}\"
        " _
}

#######################################
# Phase 5: Teardown (parallel)
# ws_names read directly from session_ws.
#######################################
teardown_workspaces() {
    local ws_names=()

    for entry in "${session_ws[@]}"; do
        ws_names+=("$(awk '{print $3}' <<< "${entry}")")
    done

    log "--- Phase 5: Teardown (jobs=${jobs}) ---"
    printf "%s\n" "${ws_names[@]}" | \
        xargs -n1 -P"${jobs}" bash -c "
            bash \"${script_dir}/code/perf_teardown.sh\" \"\$1\" -d \"${DRY_RUN}\"
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

    ensure_gdp_folders
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
log "Init matrix: ${#combos_init[@]} workspace(s) (testtype×lib)"

if [[ "${do_gen_replay}" == true ]]; then
    # -gen-replay: Phase 1 only; uniqueid used as -result value for createReplay.pl
    uniqueid="$(date +%Y%m%d_%H%M%S)_${USER_NAME}"
    log "uniqueid: ${uniqueid}"
    generate_replays
    log "Replay generation complete."

elif [[ "${do_run}" == false && "${do_teardown}" == false ]]; then
    # -no-run: init only
    run_init_phases
    log "Init complete. Run without -no-run to execute tests."

elif [[ "${do_run}" == true ]]; then
    load_or_init_session

    run_tests

    log "All tests finished."
    log "Generating summary for result/${uniqueid}"
    bash "${script_dir}/code/summary.sh" -d "${DRY_RUN}" "${uniqueid}"

    if [[ "${do_teardown}" == true ]]; then
        teardown_workspaces
        remove_session
    fi

elif [[ "${do_run}" == false && "${do_teardown}" == true ]]; then
    # -no-run -t: teardown only
    [[ -f "${session_file}" ]] || error_exit "No session found. Cannot teardown without an active session."
    _read_session
    teardown_workspaces
    remove_session
fi

log "perf_main.sh DONE"
