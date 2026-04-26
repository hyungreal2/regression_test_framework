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
logfile="${script_dir}/log/func_main.log.$(date +%Y%m%d_%H%M%S).txt"
exec > >(tee "${logfile}") 2>&1
log "Logging to ${logfile}"

#######################################
# Constants
#######################################
readonly FUNC_VALID_MODES=(
    checkHier renameRefLib changeRefLib
    replace deleteAllMarkers
    copyHierToEmpty copyHierToNonEmpty
)
readonly FUNC_VALID_PREFIXES=(oo ox xo xx)
readonly FUNC_DATA_DIR="${script_dir}/code/func"

#######################################
# Defaults
#######################################
mode=""
prefix=""
libname=""
cellname=""
fromLib="All"
toLib=""
fromCell=""

min=""
max=""
cases=""
min_set=false
max_set=false
cases_set=false

jobs=4
do_teardown=false
teardown_worker_pid=""
main_done_flag=""

#######################################
# Trap: clean up worker + lock on exit
#######################################
_cleanup() {
    if [[ -n "${main_done_flag}" && ! -f "${main_done_flag}" ]]; then
        log "TRAP: signaling teardown worker (flag=${main_done_flag})"
        touch "${main_done_flag}" 2>/dev/null || true
    fi
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
  Functional test runner.
  Each test creates its own GDP workspace, runs a Virtuoso replay,
  then queues the workspace for background teardown.

  Test cases are driven by a list file:
    ${FUNC_DATA_DIR}/list_<mode>[_<prefix>]

OPTIONS
  -h  | --help               Print this help message
  -mode  <mode>              Test mode (required)
                               ${FUNC_VALID_MODES[*]}
  -prefix <prefix>           Variant prefix (optional)
                               ${FUNC_VALID_PREFIXES[*]}
  -lib   | --library <name>  Library name
                               (required for: checkHier, renameRefLib,
                                changeRefLib, replace, deleteAllMarkers)
  -cell  | --cell <name>     Cell name
                               (required for: checkHier, renameRefLib,
                                replace, deleteAllMarkers)
  -fromLib <name>            Source library name
                               (required for: renameRefLib, changeRefLib,
                                copyHierToEmpty, copyHierToNonEmpty)
                               (default "All" for changeRefLib)
  -toLib <name>              Destination library name
                               (required for: renameRefLib, changeRefLib,
                                copyHierToEmpty, copyHierToNonEmpty)
  -fromCell <name>           Source cell name
                               (required for: copyHierToEmpty, copyHierToNonEmpty)
  -m  | --min <n>            Minimum test number   (default: 1)
  -M  | --max <n>            Maximum test number   (default: lines in list file)
  -c  | --cases <list>       Specific cases: comma-sep or ranges (e.g. 1,3,5-9)
  -j  | --jobs <n>           Parallel jobs         (default: ${jobs})
  -d  | --dry-run [0|1|2]    Dry-run level
                               0 = run everything
                               1 = skip gdp / xlp4 / rm / vse (mock workspaces)
                               2 = skip all commands (print only)
  -t  | --teardown           Run teardown after all tests

EXAMPLES
  $(basename "$0") -mode checkHier -lib ESD01 -cell FULLCHIP
  $(basename "$0") -mode checkHier -prefix oo -lib ESD01 -cell FULLCHIP
  $(basename "$0") -mode renameRefLib -lib ESD01 -cell FULLCHIP -fromLib ESD01 -toLib ESD_TEST
  $(basename "$0") -mode replace -lib ESD01 -cell FULLCHIP -c 1,3,5-9
  $(basename "$0") -mode copyHierToEmpty -fromLib SrcLib -fromCell myCell -toLib DstLib -t
  $(basename "$0") -mode checkHier -lib ESD01 -cell FULLCHIP -d 2
EOF
}

#######################################
# Parse args
#######################################
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            print_help; exit 0 ;;
        -mode|--mode)
            mode="$2"; shift 2 ;;
        -prefix|--prefix)
            prefix="$2"; shift 2 ;;
        -lib|--library)
            libname="$2"; shift 2 ;;
        -cell|--cell)
            cellname="$2"; shift 2 ;;
        -fromLib)
            fromLib="$2"; shift 2 ;;
        -toLib)
            toLib="$2"; shift 2 ;;
        -fromCell)
            fromCell="$2"; shift 2 ;;
        -m|--min)
            min="$2"; min_set=true; shift 2 ;;
        -M|--max)
            max="$2"; max_set=true; shift 2 ;;
        -c|--cases)
            cases="$2"; cases_set=true; shift 2 ;;
        -j|--jobs)
            [[ "${2:-}" =~ ^[0-9]+$ ]] || error_exit "-j requires a positive integer"
            jobs="$2"; shift 2
            if (( jobs > MAX_JOBS )); then
                log "WARNING: -j ${jobs} exceeds MAX_JOBS (${MAX_JOBS}); clamping to ${MAX_JOBS}"
                jobs=${MAX_JOBS}
            fi
            ;;
        -d|--dry-run)
            if [[ "${2:-}" =~ ^[012]$ ]]; then DRY_RUN="$2"; shift 2
            else DRY_RUN=2; shift; fi ;;
        -t|--teardown)
            do_teardown=true; shift ;;
        *)
            error_exit "Unknown option: $1" ;;
    esac
done

export DRY_RUN

#######################################
# Validate: mode
#######################################
validate_mode() {
    [[ -n "${mode}" ]] || error_exit "-mode is required. Valid modes: ${FUNC_VALID_MODES[*]}"

    local m found=false
    for m in "${FUNC_VALID_MODES[@]}"; do
        [[ "${mode}" == "${m}" ]] && { found=true; break; }
    done
    [[ "${found}" == true ]] || \
        error_exit "Invalid mode: '${mode}'. Valid modes: ${FUNC_VALID_MODES[*]}"

    if [[ -n "${prefix}" ]]; then
        found=false
        local p
        for p in "${FUNC_VALID_PREFIXES[@]}"; do
            [[ "${prefix}" == "${p}" ]] && { found=true; break; }
        done
        [[ "${found}" == true ]] || \
            error_exit "Invalid prefix: '${prefix}'. Valid prefixes: ${FUNC_VALID_PREFIXES[*]}"
    fi
}

#######################################
# Validate: mode-specific required args
#######################################
validate_mode_args() {
    _require() { [[ -n "${2}" ]] || error_exit "$1 is required for mode '${mode}'"; }

    case "${mode}" in
        checkHier|replace|deleteAllMarkers)
            _require "-lib"  "${libname}"
            _require "-cell" "${cellname}"
            ;;
        renameRefLib)
            _require "-lib"     "${libname}"
            _require "-cell"    "${cellname}"
            _require "-fromLib" "${fromLib}"
            _require "-toLib"   "${toLib}"
            ;;
        changeRefLib)
            _require "-lib"   "${libname}"
            _require "-toLib" "${toLib}"
            ;;
        copyHierToEmpty|copyHierToNonEmpty)
            _require "-fromLib"  "${fromLib}"
            _require "-fromCell" "${fromCell}"
            _require "-toLib"    "${toLib}"
            ;;
    esac
}

#######################################
# Validate: min/max/cases
#######################################
validate_range_args() {
    if [[ "${max_set}" == true && "${cases_set}" == true ]]; then
        error_exit "--max and --cases cannot be used together."
    fi
    if [[ "${min_set}" == true && "${cases_set}" == true ]]; then
        error_exit "--min and --cases cannot be used together."
    fi
    if [[ "${min_set}" == true ]]; then
        [[ "${min}" =~ ^[0-9]+$ ]] || error_exit "--min must be a positive integer."
    fi
    if [[ "${max_set}" == true ]]; then
        [[ "${max}" =~ ^[0-9]+$ ]] || error_exit "--max must be a positive integer."
    fi
    if [[ "${cases_set}" == true ]]; then
        [[ "${cases}" =~ ^[0-9]+(-[0-9]+)?(,[0-9]+(-[0-9]+)?)*$ ]] || \
            error_exit "--cases format invalid (e.g. 1,3,5-9)"
    fi
}

#######################################
# Expected row count per mode
# (used by func_summary.sh to detect failures)
#######################################
get_expected_rows() {
    case "$1" in
        checkHier)        echo 6 ;;
        renameRefLib)     echo 4 ;;
        replace)          echo 8 ;;
        deleteAllMarkers) echo 6 ;;
        *)                echo 0 ;;
    esac
}

#######################################
# Ensure GDP base folders exist
#######################################
ensure_gdp_folders() {
    if [[ "${DRY_RUN}" -ge 1 ]]; then
        log "[DRY-RUN] Would ensure GDP folders: ${GDP_BASE}, ${FUNC_GDP_BASE}"
        return
    fi

    local folder
    for folder in "${GDP_BASE}" "${FUNC_GDP_BASE}"; do
        log "Checking GDP folder: ${folder}"
        if [[ -n "$(gdp list "${folder}" 2>/dev/null)" ]]; then
            log "  → exists: ${folder}"
        else
            log "  → not found, creating: ${folder}"
            gdp create folder "${folder}"
        fi
    done
}

#######################################
# Generate replay files from list file
#######################################
generate_templates() {
    local list_file="${FUNC_DATA_DIR}/list_${mode}${prefix:+_${prefix}}"
    local template_src="${FUNC_DATA_DIR}/template.il"
    local template_mode="${FUNC_DATA_DIR}/template_${mode}.il"
    local func_replays="${FUNC_DATA_DIR}/func_replay_files_${uniqueid}"

    [[ -f "${list_file}" ]]    || error_exit "List file not found: ${list_file}"
    [[ -f "${template_src}" ]] || error_exit "Template file not found: ${template_src}"

    log "Generating template_${mode}.il from template.il"
    run_cmd "sed 's/mode *= *\"[^\"]*\"/mode = \"${mode}\"/g' \
        \"${template_src}\" > \"${template_mode}\""

    log "Removing previous replay folder: ${func_replays}"
    run_cmd "rm -rf \"${func_replays}\""

    local python_args="--mode ${mode} --workspace \"${FUNC_DATA_DIR}\" --results func_replay_files_${uniqueid}"
    [[ -n "${prefix}"   ]] && python_args+=" --prefix ${prefix}"
    [[ -n "${libname}"  ]] && python_args+=" --libname ${libname}"
    [[ -n "${cellname}" ]] && python_args+=" --cellname ${cellname}"
    [[ -n "${fromLib}"  ]] && python_args+=" --fromLib ${fromLib}"
    [[ -n "${toLib}"    ]] && python_args+=" --toLib ${toLib}"
    [[ -n "${fromCell}" ]] && python_args+=" --fromCell ${fromCell}"

    log "Generating replay files (mode=${mode})"
    run_cmd "python3 \"${script_dir}/code/func_generate_templates.py\" ${python_args}"
}

#######################################
# Determine test numbers from list file
#######################################
get_tests() {
    local list_file="${FUNC_DATA_DIR}/list_${mode}${prefix:+_${prefix}}"
    total_lines=$(grep -c '' "${list_file}")
    pad_width=${#total_lines}

    local effective_min="${min:-1}"
    local effective_max="${max:-${total_lines}}"

    if [[ "${min_set}" == true ]]; then
        (( effective_min <= total_lines )) || \
            error_exit "--min (${effective_min}) exceeds list file length (${total_lines})."
    fi
    if [[ "${max_set}" == true ]]; then
        (( effective_max <= total_lines )) || \
            error_exit "--max (${effective_max}) exceeds list file length (${total_lines})."
        (( effective_min <= effective_max )) || \
            error_exit "--min (${effective_min}) must be <= --max (${effective_max})."
    fi

    declare -A seen=()
    tests=()

    if [[ "${cases_set}" == true ]]; then
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
        mapfile -t tests < <(seq "${effective_min}" "${effective_max}")
    fi
}

#######################################
# Create regression directory
#######################################
create_regression_dir() {
    regression_dir="${script_dir}/regression_func_${uniqueid}"
    log "Regression directory: ${regression_dir}"
    run_cmd "mkdir -p \"${regression_dir}\""
}

#######################################
# Distribute replay files to test dirs
#######################################
prepare_tests() {
    local func_replays="${FUNC_DATA_DIR}/func_replay_files_${uniqueid}"

    for i in "${tests[@]}"; do
        local num
        num=$(format_num_width "${i}" "${pad_width}")
        local testdir="${regression_dir}/test_${num}"

        log "Preparing test ${num}: ${testdir}"
        run_cmd "mkdir -p \"${testdir}\""
        run_cmd "mv -f \"${func_replays}/replay_${num}.il\" \"${testdir}/\""
    done
}

#######################################
# Run all tests in parallel
#######################################
run_tests() {
    log "Running tests in parallel (jobs=${jobs})"
    printf "%s\n" "${tests[@]}" | \
        xargs -n1 -P"${jobs}" bash "${script_dir}/code/func_run_single.sh"
}

#######################################
# Main
#######################################
log "START (dry-run=${DRY_RUN})"

validate_mode
validate_mode_args
validate_range_args

#######################################
# Generate unique ID
#######################################
uniqueid="$(date +%Y%m%d_%H%M%S)_${USER_NAME}_${mode}"
[[ -n "${prefix}" ]] && uniqueid="${uniqueid}_${prefix}"
export uniqueid
log "uniqueid: ${uniqueid}"

ensure_gdp_folders
generate_templates
get_tests
log "Tests to run: ${#tests[@]} (pad_width=${pad_width})"

create_regression_dir
prepare_tests
run_cmd "mkdir -p \"${script_dir}/CDS_log/${uniqueid}\""

#######################################
# Export vars for func_run_single.sh
#######################################
export mode prefix libname cellname fromLib toLib fromCell
export regression_dir pad_width

#######################################
# Start background teardown worker
#######################################
teardown_queue_file="${regression_dir}/teardown_queue.txt"
main_done_flag="${regression_dir}/main_done.flag"

if [[ "${do_teardown}" == true ]]; then
    touch "${teardown_queue_file}"
    log "Starting background teardown worker (func_teardown.sh)"
    bash "${script_dir}/code/teardown_worker.sh" \
        "${teardown_queue_file}" "${main_done_flag}" \
        "${script_dir}/code/func_teardown.sh" &
    teardown_worker_pid=$!
    export teardown_queue_file
fi

run_tests

log "All tests finished."

#######################################
# Summary
#######################################
expected_row=$(get_expected_rows "${mode}")
log "Generating func summary (mode=${mode} expected_row=${expected_row})"
bash "${script_dir}/code/func_summary.sh" \
    -d "${DRY_RUN}" "${mode}" "${uniqueid}" "${expected_row}"

#######################################
# Signal teardown worker
#######################################
if [[ "${do_teardown}" == true ]]; then
    log "Signaling teardown worker: main done"
    touch "${main_done_flag}"
    log "Waiting for teardown worker to finish (pid=${teardown_worker_pid})"
    wait "${teardown_worker_pid}"
    teardown_worker_pid=""
    log "Teardown worker finished."
fi

log "func_main.sh DONE"
