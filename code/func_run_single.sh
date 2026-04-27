#!/bin/bash

set -euo pipefail

[[ -n "${script_dir:-}" ]] || { echo "ERROR: script_dir is not set. Run via func_main.sh." >&2; exit 1; }
source "${script_dir}/code/env.sh"
source "${script_dir}/code/common.sh"

[[ $# -ge 1 ]] || error_exit "Usage: $0 <test_id>"
[[ "${1}" =~ ^[0-9]+$ ]] || error_exit "test_id must be a positive integer: $1"

[[ -n "${mode:-}"           ]] || error_exit "mode is not exported from caller"
[[ -n "${uniqueid:-}"       ]] || error_exit "uniqueid is not exported from caller"
[[ -n "${regression_dir:-}" ]] || error_exit "regression_dir is not exported from caller"
[[ -n "${pad_width:-}"      ]] || error_exit "pad_width is not exported from caller"

test_id="$1"
num=$(format_num_width "${test_id}" "${pad_width}")
testdir="${regression_dir}/${mode}/test_${num}"

#######################################
# Per-test uniquetestid: uniqueid + num + PID
# guarantees uniqueness across parallel jobs
#######################################
uniquetestid="${uniqueid}_${num}_$$"
export uniquetestid

echo "${uniquetestid}" > "${testdir}/uniquetestid.txt"
log "[TEST ${num}] uniquetestid=${uniquetestid}"

#######################################
# Determine which libraries go into
# the workspace based on mode
#######################################
case "${mode}" in
    checkHier|renameRefLib|changeRefLib|replace|deleteAllMarkers)
        [[ -n "${libname:-}" ]] || error_exit "[TEST ${num}] libname required for mode=${mode}"
        init_libs=("${libname}")
        ;;
    copyHierToEmpty|copyHierToNonEmpty)
        [[ -n "${fromLib:-}" ]] || error_exit "[TEST ${num}] fromLib required for mode=${mode}"
        init_libs=("${fromLib}")
        ;;
    *)
        error_exit "[TEST ${num}] Unknown mode: ${mode}"
        ;;
esac

# Set mock hints for DRY_RUN=1
export MOCK_GDP_LIBS="${init_libs[*]}"
export MOCK_GDP_CELL="${cellname:-mock_cell}"

workspace_name="${FUNC_WS_PREFIX}_${uniquetestid}"

(
    cd "${testdir}" || exit 1

    #######################################
    # Init: create GDP project + workspace
    #######################################
    log "[TEST ${num}] Running func_init.sh (libs=${init_libs[*]})"
    run_cmd "${script_dir}/code/func_init.sh ${init_libs[*]}"

    #######################################
    # Link helpers into workspace
    #######################################
    log "[TEST ${num}] Linking cdsLibMgr.il → ${workspace_name}"
    run_cmd "ln -sf \"${CDS_LIB_MGR}\" \"${workspace_name}\""

    log "[TEST ${num}] Linking .cdsenv → ${workspace_name}/.cdsenv"
    run_cmd "ln -sf \"${script_dir}/code/.cdsenv\" \"${workspace_name}/.cdsenv\""

    #######################################
    # Enter workspace and run Virtuoso
    # (guard bare cd for DRY_RUN < 2)
    #######################################
    if [[ "${DRY_RUN:-0}" -lt 2 ]]; then
        cd "${workspace_name}" || exit 1
    fi

    log "[TEST ${num}] Running Virtuoso replay"
    run_cmd "mkdir -p \"${script_dir}/CDS_log/${uniqueid}\""
    run_vse "${testdir}/replay_${num}.il" \
        "${script_dir}/CDS_log/${uniqueid}/CDS_${mode}_${num}.log"
)

log "[TEST ${num}] DONE"

#######################################
# Queue teardown
#######################################
if [[ -n "${teardown_queue_file:-}" ]]; then
    log "[TEST ${num}] Queuing teardown: ${uniquetestid}"
    echo "${uniquetestid}" >> "${teardown_queue_file}"
fi
