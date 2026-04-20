#!/bin/bash
set -euo pipefail

[[ -n "${script_dir:-}" ]] || { echo "ERROR: script_dir is not set. Run via main.sh or perf_main.sh." >&2; exit 1; }
source "${script_dir}/code/env.sh"
source "${script_dir}/code/common.sh"

[[ $# -gt 0 ]] || error_exit "Usage: $0 <test_id>"
test_id="$1"

[[ "${test_id}" =~ ^[0-9]+$ ]] || error_exit "test_id must be a positive integer: ${test_id}"
[[ -n "${libname:-}"        ]] || error_exit "libname is not exported from caller"
[[ -n "${regression_dir:-}" ]] || error_exit "regression_dir is not exported from caller"
[[ -n "${uniqueid:-}"       ]] || error_exit "uniqueid is not exported from caller"

num=$(format_num "${test_id}")
testdir="${regression_dir}/test_${num}"

#######################################
# uniquetestid per test (핵심!)
#######################################
uniquetestid="${num}_$(date +%Y%m%d_%H%M%S)_$$"
export uniquetestid

echo "${uniquetestid}" > "${testdir}/uniquetestid.txt"

log "[TEST ${num}] uniquetestid=${uniquetestid}"

(
    cd "${testdir}" || exit 1

    #######################################
    # init
    #######################################
    log "[TEST ${num}] Running init.sh (libname=${libname})"
    run_cmd "${script_dir}/code/init.sh ${libname}"

    #######################################
    # workspace path
    #######################################
    workspace_name="${WS_PREFIX}_${uniquetestid}"

    #######################################
    # link
    #######################################
    log "[TEST ${num}] Linking cdsLibMgr.il to ${workspace_name}"
    run_cmd "ln -sf ${CDS_LIB_MGR} ${workspace_name}"

    log "[TEST ${num}] Linking .cdsenv to ${workspace_name}"
    run_cmd "ln -sf ${script_dir}/code/.cdsenv ${workspace_name}/.cdsenv"

    #######################################
    # run
    #######################################
    cd "${workspace_name}"

    log "[TEST ${num}] Running virtuoso replay (replay_${num}.il)"
    run_cmd "mkdir -p \"${script_dir}/CDS_log/${uniqueid}\""
    run_vse "${testdir}/replay_${num}.il" "${script_dir}/CDS_log/${uniqueid}/CDS_${num}.log"
)

log "[TEST ${num}] DONE"

if [[ -n "${teardown_queue_file:-}" ]]; then
    log "[TEST ${num}] Queuing teardown: ${uniquetestid}"
    echo "${uniquetestid}" >> "${teardown_queue_file}"
fi
