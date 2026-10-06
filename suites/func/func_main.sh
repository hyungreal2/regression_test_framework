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
logfile="${script_dir}/log/func_main.log.$(date +%Y%m%d_%H%M%S).txt"
exec > >(tee "${logfile}") 2>&1
log "Logging to ${logfile}"
fi

# ─────────────────────────────────────────────────────────────────────────────
# FUNC: mode constants
# ─────────────────────────────────────────────────────────────────────────────
readonly FUNC_VALID_MODES=(
    checkHier renameRefLib changeLibRef
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
do_teardown=true    # legacy: every test is torn down; -k/--keep skips it
tests_rc=0          # xargs rc of the test phase (123 = some test failed)
teardown_rc=0       # rc of the background teardown worker
summary_rc=0        # rc of func_summary.sh (non-zero if it crashed)
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
    if [[ -n "${teardown_worker_pid}" && -n "${main_done_flag}" && ! -f "${main_done_flag}" ]]; then
        log "TRAP: signaling teardown worker (main_done_flag=${main_done_flag})"
        touch "${main_done_flag}" 2>/dev/null || true
    fi
    if [[ -n "${teardown_worker_pid}" ]]; then
        wait "${teardown_worker_pid}" 2>/dev/null || true
    fi
    flush_trash || true
    [[ -z "${_dry_state_dir:-}" ]] || rm -rf "${_dry_state_dir}" 2>/dev/null || true
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
  -d  | --dry-run [n]         Dry-run level 0/1/2   (default: ${DRY_RUN}; -d alone = 2)
  -ws | --ws_name <prefix>    Workspace name prefix (default: ${FUNC_WS_PREFIX})
  -proj | --proj_prefix <p>   GDP project prefix    (default: ${FUNC_PROJ_PREFIX})
  -k  | --keep | --no-teardown
                              Skip teardown: keep GDP projects/workspaces,
                              p4 clients and local workspaces (debug)
  -t  | --teardown            Accepted for compatibility (teardown is the default)

Exit status: non-zero if a test could not run (init or Virtuoso failed), the
summary crashed or a teardown failed. PASS/FAIL verdicts are not reflected
(as in legacy); read result/<id>/summary.txt for them.

Teardown runs after each test by default. After a -k run, clean up with
  bash code/func_teardown_all.sh <regression_dir>
before running clean.sh (clean.sh deletes the regression_test_* dirs that
func_teardown_all.sh reads the test ids from).

Examples:
  $(basename "$0") -mode checkHier -lib ESD01 -cell FULLCHIP
  $(basename "$0") -mode replace -lib ESD01 -cell FULLCHIP -c 1,3,5-9
  $(basename "$0") -mode copyHierToEmpty -fromLib SrcLib -fromCell myCell -toLib DstLib -k
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
        -M|--max)
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
            do_teardown=true    # default; kept for compatibility
            shift
            ;;
        -k|--keep|--no-teardown)
            do_teardown=false
            shift
            ;;
        -ws|--ws_name)
            [[ "${2:-}" =~ ^[A-Za-z0-9_.-]+$ ]] || error_exit "$1 requires a name ([A-Za-z0-9_.-])"
            FUNC_WS_PREFIX="$2"
            shift 2
            ;;
        -proj|--proj_prefix)
            [[ "${2:-}" =~ ^[A-Za-z0-9_.-]+$ ]] || error_exit "$1 requires a name ([A-Za-z0-9_.-])"
            FUNC_PROJ_PREFIX="$2"
            shift 2
            ;;
        # ── FUNC: additions ───────────────────────────────────────────────────
        -mode|--mode) need_arg "$@";       mode="$2";     shift 2 ;;
        -prefix|--prefix) need_arg "$@";   prefix="$2";   shift 2 ;;
        -fromLib) need_arg "$@";           fromLib="$2";  shift 2 ;;
        -toLib) need_arg "$@";             toLib="$2";    shift 2 ;;
        -fromCell) need_arg "$@";          fromCell="$2"; shift 2 ;;
        -m|--min) need_arg "$@";           min="$2"; min_set=true; shift 2 ;;
        # ─────────────────────────────────────────────────────────────────────
        *)
            error_exit "Unknown option: $1"
            ;;
    esac
done

# Children re-source code/env.sh, which keeps an exported FUNC_WS_PREFIX /
# FUNC_PROJ_PREFIX (default-if-unset), so -ws/-proj reach init/run/teardown.
export DRY_RUN FUNC_WS_PREFIX FUNC_PROJ_PREFIX
export CAT_FUNC_WS_PREFIX="${FUNC_WS_PREFIX}" CAT_FUNC_PROJ_PREFIX="${FUNC_PROJ_PREFIX}"   # children re-source env.sh

#######################################
# Start condition
#######################################
if [[ "${DRY_RUN}" -lt 2 ]]; then
    [[ -n "${ICM_SkillRoot:-}" ]] || error_exit "ICM_SkillRoot is not set (required for GDP/Virtuoso)"
fi

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
        changeLibRef)
            _req "-lib" "${libname}"; _req "-cell" "${cellname}"; _req "-toLib" "${toLib}" ;;
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
    local folder
    for folder in "${GDP_BASE}" "${FUNC_GDP_BASE}"; do  # FUNC: FUNC_GDP_BASE not CICO_GDP_BASE
        if [[ "${DRY_RUN}" -ge 1 ]]; then
            # L2 prints [DRY-RUN:2], L1 prints [SKIP:1]; the gdp list lookup is skipped
            run_cmd "gdp create folder \"${folder}\""
            continue
        fi
        log "Checking GDP folder: ${folder}"
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
    py_args+=" --result_folder ${result_folder_id}"
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
        (( 10#${effective_min} >= 1 )) || error_exit "--min must be at least 1."
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
        local c
        for c in ${cases//[,-]/ }; do
            (( 10#${c} >= 1 && 10#${c} <= 10#${total_lines} )) \
                || error_exit "--cases: ${c} is out of range (1-${total_lines}, lines of ${list_file##*/})"
        done
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
        mapfile -t tests < <(seq "${effective_min}" "${effective_max}")
    fi
}

#######################################
# Create regression directory
#######################################
create_regression_dir() {
    # The directory is claimed with an atomic mkdir (no -p), so two runs of
    # the same mode started together can never share a regression dir.
    local dir n="000" attempt
    local num_file="${script_dir}/regression_num_${mode}.txt"

    if [[ -f "${num_file}" ]]; then
        n=$(<"${num_file}")
        [[ "${n}" =~ ^[0-9]+$ ]] || n="000"
    fi

    for (( attempt = 0; attempt < 1000; attempt++ )); do
        n=$(printf "%03d" $(( (10#${n} + 1) % 1000 )))
        dir="${script_dir}/regression_test_${mode}_${n}"
        if [[ "${DRY_RUN:-0}" -ge 2 ]]; then
            [[ -e "${dir}" ]] && continue          # level 2: compute only, create nothing
        else
            mkdir "${dir}" 2>/dev/null || continue # taken (or racing run won it)
        fi
        num="${n}"
        regression_dir="${dir}"
        log "Regression Directory: ${regression_dir}"
        if [[ "${DRY_RUN:-0}" -ge 2 ]]; then
            run_cmd "mkdir -p \"${regression_dir}\""   # print only
        else
            echo "${num}" > "${num_file}"
        fi
        return 0
    done
    error_exit "No free regression number for mode ${mode} (all 1000 regression_test_${mode}_NNN exist)"
}

#######################################
# Prepare test directories
#######################################
prepare_tests() {
    for i in "${tests[@]}"; do
        num=$(format_num_width "${i}" "${pad_width}")
        local testdir="${regression_dir}/test_${num}"

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

    # A failing test must not stop main (set -e): capture the xargs rc,
    # always go on to the summary and teardown, and exit with it at the end.
    printf "%s\n" "${tests[@]}" | \
        xargs -n1 -P"${jobs}" bash "${script_dir}/code/func_run_single.sh" \
        || tests_rc=$?  # FUNC: func_run_single
    case "${tests_rc}" in
        0)   ;;
        123) warn "Some tests failed (xargs rc=123); continuing to summary" ;;
        *)   warn "xargs itself failed (rc=${tests_rc}); continuing to summary" ;;
    esac
}

#######################################
# Record the run arguments next to the
# results (result/ survives clean.sh)
#######################################
record_run_args() {
    local args_line="mode=${mode} prefix=${prefix:-none} lib=${libname:-none} cell=${cellname:-none}"
    args_line+=" fromLib=${fromLib:-none} toLib=${toLib:-none} fromCell=${fromCell:-none}"
    args_line+=" tests=${#tests[@]} pad_width=${pad_width} jobs=${jobs} dry_run=${DRY_RUN}"
    args_line+=" teardown=${do_teardown} ws_prefix=${FUNC_WS_PREFIX} proj_prefix=${FUNC_PROJ_PREFIX}"
    args_line+=" vse_version=${VSE_VERSION} from_lib=${FROM_LIB}"
    log "RUN ARGS: ${args_line}"

    local args_file="${script_dir}/result/${result_folder_id}/run_args.txt"
    if [[ "${DRY_RUN}" -ge 1 ]]; then
        log "[DRY-RUN:${DRY_RUN}] Would write ${args_file}"
        return 0
    fi
    mkdir -p "$(dirname "${args_file}")"
    {
        echo "uniqueid: ${uniqueid}"
        echo "result_folder_id: ${result_folder_id}"
        echo "regression_dir: ${regression_dir}"
        echo "mode: ${mode}"
        echo "prefix: ${prefix}"
        echo "lib: ${libname}"
        echo "cell: ${cellname}"
        echo "fromLib: ${fromLib}"
        echo "toLib: ${toLib}"
        echo "fromCell: ${fromCell}"
        echo "tests: ${tests[*]}"
        echo "pad_width: ${pad_width}"
        echo "teardown: ${do_teardown}"
        echo "FUNC_WS_PREFIX: ${FUNC_WS_PREFIX}"
        echo "FUNC_PROJ_PREFIX: ${FUNC_PROJ_PREFIX}"
        echo "VSE_VERSION: ${VSE_VERSION}"
        echo "FROM_LIB: ${FROM_LIB}"
    } > "${args_file}"
}

#######################################
# Main
#######################################
log "START (dry-run=${DRY_RUN})"

#######################################
# Generate unique ID
#######################################
uniqueid="${mode}_$(date +%Y%m%d_%H%M%S)_${USER_NAME}"  # FUNC: mode_date_user
[[ -n "${prefix}" ]] && uniqueid="${uniqueid}_${prefix}"
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
log "Tests to run: ${#tests[@]} (pad_width=${pad_width})"
create_regression_dir
prepare_tests
mkdir -p "${script_dir}/CDS_log/${uniqueid}"

# FUNC: export mode-specific vars for func_run_single.sh
export mode prefix libname cellname fromLib toLib fromCell
export regression_dir pad_width

record_run_args

#######################################
# Teardown queue + background worker
# Every test always queues its id, so a
# -k run can be torn down later; only the
# worker is gated by -k.
#######################################
if [[ "${DRY_RUN}" -ge 2 ]]; then
    # level 2 creates no regression dir; keep the queue in a temp dir so
    # the preview still shows the teardown commands
    _dry_state_dir=$(mktemp -d "${TMPDIR:-/tmp}/func_main_dry.XXXXXX")
    teardown_queue_file="${_dry_state_dir}/teardown_queue.txt"
    main_done_flag="${_dry_state_dir}/main_done.flag"
else
    teardown_queue_file="${regression_dir}/teardown_queue.txt"
    # Prefixes of this run, so func_teardown_all.sh finds -ws/-proj names later
    printf 'FUNC_WS_PREFIX=%s\nFUNC_PROJ_PREFIX=%s\n' "${FUNC_WS_PREFIX}" "${FUNC_PROJ_PREFIX}" > "${regression_dir}/run_prefixes"
    main_done_flag="${regression_dir}/main_done.flag"
fi
touch "${teardown_queue_file}"
export teardown_queue_file

if [[ "${do_teardown}" == true ]]; then
    log "Starting background teardown worker"
    bash "${script_dir}/code/teardown_worker.sh" \
        "${teardown_queue_file}" "${main_done_flag}" \
        "${script_dir}/code/func_teardown.sh" &  # FUNC: func_teardown.sh
    teardown_worker_pid=$!
else
    log "Teardown skipped (-k): test ids are queued in ${teardown_queue_file}"
    # marker for code/func_teardown_all.sh: every queued id still needs teardown
    [[ "${DRY_RUN}" -ge 2 ]] || echo "teardown skipped (-k); ids in teardown_queue.txt" \
        > "${regression_dir}/teardown_skipped"
fi

export libname regression_dir
run_tests

log "All tests finished."

#######################################
# Detect tests with missing CDS log
#######################################
if [[ "${DRY_RUN}" -eq 0 ]]; then
    _missing=()
    for _t in "${tests[@]}"; do
        _n=$(format_num_width "${_t}" "${pad_width}")
        [[ -f "${script_dir}/CDS_log/${uniqueid}/CDS_${mode}_${_n}.log" ]] || _missing+=("${_n}")
    done
    if [[ ${#_missing[@]} -gt 0 ]]; then
        warn "Tests with no CDS log (Virtuoso did not run): ${_missing[*]}"
    else
        log "All ${#tests[@]} tests produced a CDS log."
    fi
fi

#######################################
# Summary
#######################################
# FUNC: verdicts come from the per-test result logs in result/<id>/
# (legacy 3_func_sp summary rules, see code/func_summary.sh)
log "Generating summary for result/${result_folder_id}"
_padded_tests=()
for _t in "${tests[@]}"; do
    _padded_tests+=("$(format_num_width "${_t}" "${pad_width}")")
done
bash "${script_dir}/code/func_summary.sh" -d "${DRY_RUN}" -t "${_padded_tests[*]}" \
    "${mode}" "${uniqueid}" "${result_folder_id}" \
    || { summary_rc=$?; warn "func_summary.sh failed (rc=${summary_rc})"; }

if [[ "${do_teardown}" == true ]]; then
    log "Signaling teardown worker: main done"
    touch "${main_done_flag}"
    log "Waiting for teardown worker to finish (pid=${teardown_worker_pid})"
    wait "${teardown_worker_pid}" || teardown_rc=$?
    teardown_worker_pid=""  # prevent _cleanup from wait-ing again
    if [[ ${teardown_rc} -ne 0 ]]; then
        warn "Teardown worker exited rc=${teardown_rc}; some teardowns failed (see log above)." \
             "Retry with: bash code/func_teardown_all.sh ${regression_dir}"
    else
        log "Teardown worker finished."
    fi
else
    warn "Teardown skipped (-k): GDP projects/workspaces, p4 clients and local workspaces remain." \
         "Clean up with: bash code/func_teardown_all.sh ${regression_dir} (before clean.sh)"
fi

final_rc=${tests_rc}
[[ ${final_rc} -ne 0 ]] || final_rc=${summary_rc}
[[ ${final_rc} -ne 0 ]] || final_rc=${teardown_rc}
log "func_main.sh DONE (tests_rc=${tests_rc} teardown_rc=${teardown_rc})"
exit "${final_rc}"
