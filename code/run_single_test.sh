#!/bin/bash
set -euo pipefail

source "$(dirname "$0")/env.sh"
source "$(dirname "$0")/common.sh"

[[ $# -gt 0 ]] || error_exit "Usage: $0 <test_id>"
test_id="$1"
#libname="$2" ->from parent
#regression_dir="$3" ->from parent

[[ "${test_id}" =~ ^[0-9]+$ ]] || error_exit "test_id must be a positive integer: ${test_id}"
[[ -n "${libname:-}"        ]] || error_exit "libname is not exported from caller"
[[ -n "${regression_dir:-}" ]] || error_exit "regression_dir is not exported from caller"

num=$(format_num "${test_id}")
testdir="$(pwd)/${regression_dir}/test_${num}"

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
    run_cmd "../../code/init.sh ${libname}"

    #######################################
    # workspace path
    #######################################
    workspace_name="${WS_PREFIX}_${uniquetestid}"

    #######################################
    # link
    #######################################
    log "[TEST ${num}] Linking cdsLibMgr.il to ${workspace_name}"
    run_cmd "ln -sf ${CDS_LIB_MGR} ${workspace_name}"

    #######################################
    # run
    #######################################
    cd "${workspace_name}"

    log "[TEST ${num}] Running virtuoso replay (replay_${num}.il)"
    run_cmd "mkdir -p ../../../CDS_log/${uniquetestid}"
    vse_out=$(run_cmd "vse_sub \
        -v ${VSE_VERSION} \
        -env ${ICM_ENV} \
        -replay ../replay_${num}.il \
        -log ../../../CDS_log/${uniquetestid}/CDS_${num}.log")
    job_id=$(awk -F'[<>]' '{print $2}' <<< "${vse_out}")

    log "[TEST ${num}] Waiting for job to finish (job_id=${job_id})"
    run_cmd "bwait -w \"ended(${job_id})\""
)

log "[TEST ${num}] DONE"

if [[ -n "${teardown_queue_file:-}" ]]; then
    log "[TEST ${num}] Queuing teardown: ${uniquetestid}"
    echo "${uniquetestid}" >> "${teardown_queue_file}"
fi
