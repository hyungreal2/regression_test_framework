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

# ─────────────────────────────────────────────────────────────────────────────
# FUNC: mode constants
# ─────────────────────────────────────────────────────────────────────────────
readonly FUNC_VALID_MODES=(
    checkHier renameRefLib changeRefLib
    replace deleteAllMarkers
    copyHierToEmpty copyHierToNonEmpty
)
readonly FUNC_VALID_PREFIXES=(oo ox xo xx)
readonly FUNC_DATA_DIR="${script_dir}/code"
# ─────────────────────────────────────────────────────────────────────────────

#######################################
# Defaults
#######################################
max=""              # FUNC: determined from list file, not MAX_CASES
cases=""
libname=""          # FUNC: required per mode (no env default)
cellname=""         # FUNC: required per mode (no env default)
max_set=false
cases_set=false
jobs=4
do_teardown=false
teardown_worker_pid=""
main_done_flag=""
# FUNC: additions
mode=""
prefix=""
fromLib="All"
toLib=""
fromCell=""
min=""
min_set=false

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
    rm -f "${script_dir}/.gdp_ws_lock" 2>/dev/null || true
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
  -mode  <mode>               Test mode (required)
                                ${FUNC_VALID_MODES[*]}
  -prefix <prefix>            Variant prefix (optional)
                                ${FUNC_VALID_PREFIXES[*]}
  -lib   | --library <name>   Library name
  -cell  | --cell <name>      Cell name
  -fromLib <name>             Source library name  (default: All)
  -toLib <name>               Destination library name
  -fromCell <name>            Source cell name
  -m  | --min <n>             Minimum test number  (default: 1)
  -M  | --max <n>             Maximum test number  (default: lines in list file)
  -c  | --cases <list>        Tests: comma-sep or ranges (e.g. 1,3,5-9)
  -j  | --jobs <n>            Parallel jobs         (default: ${jobs})
  -d  | --dry-run [n]         Dry-run level 0/1/2   (default: 2)
  -t  | --teardown            Run teardown after all tests

Examples:
  $(basename "$0") -mode checkHier -lib ESD01 -cell FULLCHIP
  $(basename "$0") -mode replace -lib ESD01 -cell FULLCHIP -c 1,3,5-9
  $(basename "$0") -mode copyHierToEmpty -fromLib SrcLib -fromCell myCell -toLib DstLib -t
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
        -lib|--library)
            libname="$2"
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
        -M|--max)
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
            [[ "${2:-}" =~ ^[0-9]+$ ]] || error_exit "-j requires a positive integer"
            jobs="$2"
            shift 2
            if (( jobs > MAX_JOBS )); then
                log "WARNING: -j ${jobs} exceeds MAX_JOBS (${MAX_JOBS}); clamping to ${MAX_JOBS}"
                jobs=${MAX_JOBS}
            fi
            ;;
        -t|--teardown)
            do_teardown=true
            shift
            ;;
        # ── FUNC: additions ───────────────────────────────────────────────────
        -mode|--mode)       mode="$2";     shift 2 ;;
        -prefix|--prefix)   prefix="$2";   shift 2 ;;
        -fromLib)           fromLib="$2";  shift 2 ;;
        -toLib)             toLib="$2";    shift 2 ;;
        -fromCell)          fromCell="$2"; shift 2 ;;
        -m|--min)           min="$2"; min_set=true; shift 2 ;;
        # ─────────────────────────────────────────────────────────────────────
        *)
            error_exit "Unknown option: $1"
            ;;
    esac
done

export DRY_RUN

# ─────────────────────────────────────────────────────────────────────────────
# FUNC: mode validation helpers (called from validate_inputs)
# ─────────────────────────────────────────────────────────────────────────────
_validate_mode() {
    [[ -n "${mode}" ]] || error_exit "-mode is required. Valid: ${FUNC_VALID_MODES[*]}"
    local m found=false
    for m in "${FUNC_VALID_MODES[@]}"; do
        [[ "${mode}" == "${m}" ]] && { found=true; break; }
    done
    [[ "${found}" == true ]] || error_exit "Invalid mode '${mode}'. Valid: ${FUNC_VALID_MODES[*]}"
    if [[ -n "${prefix}" ]]; then
        found=false
        local p
        for p in "${FUNC_VALID_PREFIXES[@]}"; do
            [[ "${prefix}" == "${p}" ]] && { found=true; break; }
        done
        [[ "${found}" == true ]] || error_exit "Invalid prefix '${prefix}'. Valid: ${FUNC_VALID_PREFIXES[*]}"
    fi
}

_validate_mode_args() {
    _req() { [[ -n "${2}" ]] || error_exit "$1 is required for mode '${mode}'"; }
    case "${mode}" in
        checkHier|replace|deleteAllMarkers)
            _req "-lib" "${libname}"; _req "-cell" "${cellname}" ;;
        renameRefLib)
            _req "-lib" "${libname}"; _req "-cell" "${cellname}"
            _req "-fromLib" "${fromLib}"; _req "-toLib" "${toLib}" ;;
        changeRefLib)
            _req "-lib" "${libname}"; _req "-toLib" "${toLib}" ;;
        copyHierToEmpty|copyHierToNonEmpty)
            _req "-fromLib" "${fromLib}"; _req "-fromCell" "${fromCell}"
            _req "-toLib" "${toLib}" ;;
    esac
}
# ─────────────────────────────────────────────────────────────────────────────

#######################################
# Validate inputs
#######################################
validate_inputs() {
    _validate_mode       # FUNC
    _validate_mode_args  # FUNC

    if [[ ${max_set} == true && ${cases_set} == true ]]; then
        error_exit "--max and --cases cannot be used together."
    fi
    if [[ ${min_set} == true && ${cases_set} == true ]]; then  # FUNC
        error_exit "--min and --cases cannot be used together."
    fi
    if [[ ${max_set} == true ]]; then
        [[ ${max} =~ ^[0-9]+$ ]] || error_exit "--max must be a positive integer."
    fi
    if [[ ${min_set} == true ]]; then  # FUNC
        [[ ${min} =~ ^[0-9]+$ ]] || error_exit "--min must be a positive integer."
    fi
    if [[ ${cases_set} == true ]]; then
        [[ ${cases} =~ ^[0-9]+(-[0-9]+)?(,[0-9]+(-[0-9]+)?)*$ ]] || \
            error_exit "--cases format invalid (e.g. 1,3,5-9)"
    fi
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
    for folder in "${GDP_BASE}" "${FUNC_GDP_BASE}"; do  # FUNC: FUNC_GDP_BASE not CICO_GDP_BASE
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
# Generate templates
#######################################
generate_templates() {
    # FUNC: list file and template are mode-specific
    local list_file="${FUNC_DATA_DIR}/list_${mode}${prefix:+_${prefix}}"
    local template_src="${FUNC_DATA_DIR}/func_template.il"
    local template_mode="${FUNC_DATA_DIR}/func_template_${mode}.il"

    [[ -f "${list_file}" ]]    || error_exit "List file not found: ${list_file}"
    [[ -f "${template_src}" ]] || error_exit "Template not found: ${template_src}"

    # FUNC: patch mode variable into template
    log "Generating func_template_${mode}.il from func_template.il"
    run_cmd "sed 's/mode *= *\"[^\"]*\"/mode = \"${mode}\"/g' \
        \"${template_src}\" > \"${template_mode}\""

    log "Removing previous replay folder: code/${replays_folder}"
    run_cmd "rm -rf \"${script_dir}/code/${replays_folder}\""

    log "Generating replay templates (mode=${mode})"
    local py_args="--mode ${mode} --workspace \"${FUNC_DATA_DIR}\" --results ${replays_folder}"
    [[ -n "${prefix}"   ]] && py_args+=" --prefix ${prefix}"
    [[ -n "${libname}"  ]] && py_args+=" --libname ${libname}"
    [[ -n "${cellname}" ]] && py_args+=" --cellname ${cellname}"
    [[ -n "${fromLib}"  ]] && py_args+=" --fromLib ${fromLib}"
    [[ -n "${toLib}"    ]] && py_args+=" --toLib ${toLib}"
    [[ -n "${fromCell}" ]] && py_args+=" --fromCell ${fromCell}"
    run_cmd "python3 \"${script_dir}/code/generate_templates.py\" ${py_args}"
}

#######################################
# Determine tests
#######################################
get_tests() {
    # FUNC: total from list file, not MAX_CASES
    local list_file="${FUNC_DATA_DIR}/list_${mode}${prefix:+_${prefix}}"
    total_lines=$(grep -c '.' "${list_file}")
    pad_width=${#total_lines}

    local effective_min="${min:-1}"
    local effective_max="${max:-${total_lines}}"

    if [[ "${min_set}" == true ]]; then
        (( 10#${effective_min} <= 10#${total_lines} )) || \
            error_exit "--min (${effective_min}) exceeds list length (${total_lines})."
    fi
    if [[ "${max_set}" == true ]]; then
        (( 10#${effective_max} <= 10#${total_lines} )) || \
            error_exit "--max (${effective_max}) exceeds list length (${total_lines})."
        (( 10#${effective_min} <= 10#${effective_max} )) || \
            error_exit "--min (${effective_min}) must be <= --max (${effective_max})."
    fi

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
        mapfile -t tests < <(seq "${effective_min}" "${effective_max}")
    fi
}

#######################################
# Create regression directory
#######################################
create_regression_dir() {
    # FUNC: uniqueid-based naming (not counter)
    regression_dir="${script_dir}/regression_func_${uniqueid}"
    log "Regression Directory: ${regression_dir}"
    run_cmd "mkdir -p \"${regression_dir}\""
}

#######################################
# Prepare test directories
#######################################
prepare_tests() {
    for i in "${tests[@]}"; do
        num=$(format_num_width "${i}" "${pad_width}")
        local testdir="${regression_dir}/${mode}/test_${num}"  # FUNC: mode subdir

        log "Preparing test ${num}: ${testdir}"
        run_cmd "mkdir -p \"${testdir}\""

        log "Moving replay_${num}.il to ${testdir}/"
        run_cmd "mv -f \"${script_dir}/code/${replays_folder}/replay_${num}.il\" \"${testdir}/\""
    done
}

#######################################
# Run tests
#######################################
run_tests() {
    log "Running tests in parallel (jobs=${jobs})"

    printf "%s\n" "${tests[@]}" | \
        xargs -n1 -P"${jobs}" bash "${script_dir}/code/func_run_single.sh"  # FUNC: func_run_single
}

# FUNC: expected rows per mode (for func_summary.sh pass/fail detection)
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
# Main
#######################################
log "START (dry-run=${DRY_RUN})"

#######################################
# Generate unique ID
#######################################
uniqueid="$(date +%Y%m%d_%H%M%S)_${USER_NAME}_${mode}"  # FUNC: mode not libname
[[ -n "${prefix}" ]] && uniqueid="${uniqueid}_${prefix}"
replays_folder="replay_files_${uniqueid}"
export uniqueid
log "uniqueid: ${uniqueid}"
log "replays_folder: ${replays_folder}"

validate_inputs
ensure_gdp_folders
generate_templates
get_tests
log "Tests to run: ${#tests[@]} (pad_width=${pad_width})"
create_regression_dir
prepare_tests
mkdir -p "${script_dir}/CDS_log/${uniqueid}"

# FUNC: export mode-specific vars for func_run_single.sh
export mode prefix libname cellname fromLib toLib fromCell
export regression_dir pad_width

#######################################
# Start background teardown worker
#######################################
teardown_queue_file="${regression_dir}/teardown_queue.txt"
main_done_flag="${regression_dir}/main_done.flag"

if [[ "${do_teardown}" == true ]]; then
    touch "${teardown_queue_file}"
    log "Starting background teardown worker"
    bash "${script_dir}/code/teardown_worker.sh" \
        "${teardown_queue_file}" "${main_done_flag}" \
        "${script_dir}/code/func_teardown.sh" &  # FUNC: func_teardown.sh
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
expected_row=$(get_expected_rows "${mode}")
bash "${script_dir}/code/func_summary.sh" \
    -d "${DRY_RUN}" "${mode}" "${uniqueid}" "${expected_row}"  # FUNC: func_summary.sh

if [[ "${do_teardown}" == true ]]; then
    log "Signaling teardown worker: main done"
    touch "${main_done_flag}"
    log "Waiting for teardown worker to finish (pid=${teardown_worker_pid})"
    wait "${teardown_worker_pid}"
    teardown_worker_pid=""  # prevent _cleanup from wait-ing again
    log "Teardown worker finished."
fi

log "func_main.sh DONE"
