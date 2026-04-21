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

active_ws=()   # "testtype lib ws_name" — populated by scan_workspaces()
uniqueid=""

#######################################
# Trap
#######################################
_cleanup() {
    if [[ -n "${teardown_worker_pid}" ]]; then
        wait "${teardown_worker_pid}" 2>/dev/null || true
    fi
    rm -f "${script_dir}/.gdp_ws_lock" 2>/dev/null || true
}
trap '_cleanup' EXIT INT TERM

#######################################
# Help
#######################################
print_help() {
    cat <<EOF
Usage: $(basename "$0") [options]

DESCRIPTION
  Performance regression test runner.
  Workspaces are tracked by directory — no session file needed.
  Each library/test combination can have at most one workspace at a time.
  Re-running init for an existing combo skips it with a message.

OPTIONS
  -h         | --help            Print this help message
  -lib         <lib[,lib,...]>   Comma-separated libraries to test
                                   default: all  (${PERF_LIBS[*]})
  -test        <test[,test,...]> Comma-separated test types to run
                                   default: all  (${PERF_TESTS[*]})
  -common      <lib[,lib,...]>   Comma-separated libraries added to ALL test combos
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
  -t         | --teardown        Run teardown; -lib/-test filters apply
                                   Can be used standalone: -no-run -t [-lib ...] [-test ...]
  -auto-init | --auto-init       If no workspaces found, run init automatically
                                   without prompting

WORKSPACE TRACKING
  Active workspaces live under:
    ${script_dir}/WORKSPACES_MANAGED/

  Each lib/test combination can exist at most once. If a workspace already
  exists for a combo, init will skip it with a message.

  To list active workspaces:
    ls ${script_dir}/WORKSPACES_MANAGED/

OPTION COMBINATIONS
  -lib, -test, and -mode apply to run AND teardown.

  Command                                              Tests run
  ───────────────────────────────────────────────────  ──────────────────────────────────
  $(basename "$0")                                                  all workspaces × managed + unmanaged
  $(basename "$0") -lib BM02 -test checkHier                        checkHier/BM02 × managed + unmanaged  (2)
  $(basename "$0") -lib BM02 -test checkHier -mode managed          checkHier/BM02/managed only            (1)
  $(basename "$0") -mode managed                                    all workspaces × managed only
  $(basename "$0") -no-run -t -lib BM01                             teardown BM01 workspaces only
  $(basename "$0") -no-run -t                                       teardown all workspaces

WORKFLOW EXAMPLES
  # Generate replay files only
  $(basename "$0") -gen-replay -lib BM01 -test checkHier

  # Step 1: Set up workspaces (skips combos that already exist)
  $(basename "$0") -no-run -lib BM01,BM02 -test checkHier,renameRefLib

  # Step 2: Run tests (repeat with different filters)
  $(basename "$0")
  $(basename "$0") -lib BM01 -test checkHier
  $(basename "$0") -lib BM01 -test checkHier -mode managed

  # Step 3: Tear down specific workspaces
  $(basename "$0") -no-run -t -lib BM01 -test checkHier
  # Or tear down all
  $(basename "$0") -no-run -t

  # One shot: init → run → teardown
  $(basename "$0") -auto-init -t

  # Dry-run preview
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
}

#######################################
# Build combos_init
#######################################
build_combos() {
    local testtype lib cell
    local active_libs active_tests

    if [[ ${#selected_libs[@]} -eq 0 ]];  then active_libs=("${PERF_LIBS[@]}");  else active_libs=("${selected_libs[@]}");  fi
    if [[ ${#selected_tests[@]} -eq 0 ]]; then active_tests=("${PERF_TESTS[@]}"); else active_tests=("${selected_tests[@]}"); fi

    combos_init=()

    for testtype in "${active_tests[@]}"; do
        for lib in "${active_libs[@]}"; do
            cell=$(get_cell "${lib}")
            combos_init+=("${testtype} ${lib} ${cell}")
        done
    done
}

#######################################
# Scan WORKSPACES_MANAGED for existing
# workspaces matching -lib / -test filters.
# Populates active_ws ("testtype lib ws_name").
#######################################
scan_workspaces() {
    local ws_base="${script_dir}/WORKSPACES_MANAGED"
    active_ws=()

    [[ -d "${ws_base}" ]] || return

    local dname rest tt ll al at lib_ok test_ok
    for dname in "${ws_base}"/*/; do
        [[ -d "${dname}" ]] || continue
        dname="$(basename "${dname}")"

        # Must start with PERF_PREFIX_
        rest="${dname#${PERF_PREFIX}_}"
        [[ "${rest}" == "${dname}" ]] && continue

        # Match against known testtype_lib_ combinations
        local matched=false
        for tt in "${PERF_TESTS[@]}"; do
            for ll in "${PERF_LIBS[@]}"; do
                if [[ "${rest}" == "${tt}_${ll}_"* ]]; then
                    matched=true
                    break 2
                fi
            done
        done
        [[ "${matched}" == true ]] || continue

        # Apply -lib filter
        lib_ok=true
        if [[ ${#selected_libs[@]} -gt 0 ]]; then
            lib_ok=false
            for al in "${selected_libs[@]}"; do
                [[ "${ll}" == "${al}" ]] && { lib_ok=true; break; }
            done
        fi
        [[ "${lib_ok}" == true ]] || continue

        # Apply -test filter
        test_ok=true
        if [[ ${#selected_tests[@]} -gt 0 ]]; then
            test_ok=false
            for at in "${selected_tests[@]}"; do
                [[ "${tt}" == "${at}" ]] && { test_ok=true; break; }
            done
        fi
        [[ "${test_ok}" == true ]] || continue

        active_ws+=("${tt} ${ll} ${dname}")
    done

    log "Found ${#active_ws[@]} workspace(s) in WORKSPACES_MANAGED (after filter)"
}

#######################################
# Ensure GDP base folders exist
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
# Skips combos where a workspace already exists.
#######################################
init_workspaces() {
    local testtype lib cell run_combos=()

    for combo in "${combos_init[@]}"; do
        read -r testtype lib cell <<< "${combo}"
        if compgen -G "${script_dir}/WORKSPACES_MANAGED/${PERF_PREFIX}_${testtype}_${lib}_*" > /dev/null 2>&1; then
            log "[SKIP] Workspace already exists for ${testtype}/${lib}"
        else
            run_combos+=("${combo}")
        fi
    done

    if [[ ${#run_combos[@]} -eq 0 ]]; then
        log "All requested workspaces already exist. Nothing to init."
        return
    fi

    log "--- Phase 2: Init workspaces (${#run_combos[@]} new, jobs=${jobs}) ---"
    printf "%s\n" "${run_combos[@]}" | \
        xargs -n3 -P"${jobs}" bash -c "
            bash \"${script_dir}/code/perf_init.sh\" \"\$1\" \"\$2\" \"\$3\" \"${uniqueid}\" -d \"${DRY_RUN}\"
        " _
}

#######################################
# Copy fresh replay files to existing workspaces
# Called at run time after generate_replays() so
# the .au files contain the current run uniqueid.
#######################################
copy_replays_to_workspaces() {
    local testtype lib ws_name managed_ws unmanaged_ws replay_managed replay_unmanaged

    log "--- Copying fresh replay files to workspaces ---"
    for entry in "${active_ws[@]}"; do
        read -r testtype lib ws_name <<< "${entry}"
        managed_ws="${script_dir}/WORKSPACES_MANAGED/${ws_name}"
        unmanaged_ws="${script_dir}/WORKSPACES_UNMANAGED/${ws_name}"
        replay_managed="${script_dir}/GenerateReplayScript/${testtype}_${lib}_managed.au"
        replay_unmanaged="${script_dir}/GenerateReplayScript/${testtype}_${lib}_unmanaged.au"

        log "[REPLAY] → MANAGED:   ${ws_name}"
        run_cmd "cp \"${replay_managed}\" \"${managed_ws}/${testtype}_${lib}.au\""
        log "[REPLAY] → UNMANAGED: ${ws_name}"
        run_cmd "cp \"${replay_unmanaged}\" \"${unmanaged_ws}/${testtype}_${lib}.au\""
    done
}

#######################################
# Phase 3: Run tests (parallel)
#######################################
run_tests() {
    local testtype lib ws_name combos_run=()

    scan_workspaces

    if [[ ${#active_ws[@]} -eq 0 ]]; then
        error_exit "No workspaces found matching the specified filters. Run init first with -no-run."
    fi

    for entry in "${active_ws[@]}"; do
        read -r testtype lib ws_name <<< "${entry}"
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
# Respects -lib / -test filters via scan_workspaces().
#######################################
teardown_workspaces() {
    local ws_names=()

    scan_workspaces

    if [[ ${#active_ws[@]} -eq 0 ]]; then
        log "No workspaces found matching the specified filters. Nothing to teardown."
        return
    fi

    for entry in "${active_ws[@]}"; do
        ws_names+=("$(awk '{print $3}' <<< "${entry}")")
    done

    log "--- Phase 5: Teardown (${#ws_names[@]} workspace(s), jobs=${jobs}) ---"
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

    run_cmd "mkdir -p \"${script_dir}/WORKSPACES_MANAGED\" \"${script_dir}/WORKSPACES_UNMANAGED\""

    if [[ "${DRY_RUN}" -lt 2 ]]; then
        echo "${uniqueid}" > "${script_dir}/code/date_virtuosoVer.txt"
    fi

    ensure_gdp_folders
    generate_replays
    init_workspaces
}

#######################################
# Ensure workspaces exist (or init them)
#######################################
ensure_workspaces() {
    scan_workspaces
    [[ ${#active_ws[@]} -gt 0 ]] && return

    local answer
    if [[ "${auto_init}" == true ]]; then
        log "No workspaces found. --auto-init: running init automatically."
        answer="y"
    else
        echo ""
        echo "No active workspaces found in WORKSPACES_MANAGED/."
        echo -n "Run init to set up the environment? [y/N] "
        read -r answer
    fi

    [[ "${answer}" =~ ^[Yy]$ ]] || \
        error_exit "No workspaces. Run with -no-run to initialise the environment first."

    run_init_phases
}

#######################################
# Main
#######################################
log "START (dry-run=${DRY_RUN})"

validate_inputs
build_combos
log "Init matrix: ${#combos_init[@]} workspace(s) (testtype×lib)"

if [[ "${do_gen_replay}" == true ]]; then
    uniqueid="$(date +%Y%m%d_%H%M%S)_${USER_NAME}"
    log "uniqueid: ${uniqueid}"
    generate_replays
    log "Replay generation complete."

elif [[ "${do_run}" == false && "${do_teardown}" == false ]]; then
    # -no-run: init only
    run_init_phases
    log "Init complete. Run without -no-run to execute tests."

elif [[ "${do_run}" == true ]]; then
    ensure_workspaces  # populates active_ws

    uniqueid="$(date +%Y%m%d_%H%M%S)_${USER_NAME}"
    log "Run uniqueid: ${uniqueid}"
    run_cmd "mkdir -p \"${script_dir}/result/${uniqueid}\" \"${script_dir}/CDS_log/${uniqueid}\""

    generate_replays            # Phase 1: regenerate with current uniqueid
    copy_replays_to_workspaces  # push fresh .au files into each workspace

    run_tests

    log "All tests finished."
    log "Generating perf summary for CDS_log/${uniqueid}"
    bash "${script_dir}/code/perf_summary.sh" -d "${DRY_RUN}" "${uniqueid}"

    if [[ "${do_teardown}" == true ]]; then
        teardown_workspaces
    fi

elif [[ "${do_run}" == false && "${do_teardown}" == true ]]; then
    # -no-run -t: teardown only, with optional -lib/-test filters
    teardown_workspaces
fi

log "perf_main.sh DONE"
