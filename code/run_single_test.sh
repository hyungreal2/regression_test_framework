#!/bin/bash
set -euo pipefail

source "$(dirname "$0")/env.sh"
source "$(dirname "$0")/common.sh"

test_id="$1"
#libname="$2" ->from parent
#regression_dir="$3" ->from parent

num=$(format_num "${test_id}")
testdir="$(pwd)/${regression_dir}/test_${num}"

#######################################
# uniqueid per test (핵심!)
#######################################
uniqueid="$(date +%Y%m%d_%H%M%S)_${test_id}_$$"
export uniqueid

log "[TEST ${num}] uniqueid=${uniqueid}"

(
    cd "${testdir}" || exit 1

    #######################################
    # init
    #######################################
    run_cmd "../../code/init.sh ${libname}"

    #######################################
    # workspace path
    #######################################
    WS_NAME="${WS_PREFIX}_${uniqueid}"

    #######################################
    # link
    #######################################
    run_cmd "ln -s ${CDS_LIB_MGR} ${WS_NAME}"

    #######################################
    # run
    #######################################
    cd "${WS_NAME}"

    echo "${num}" > "/tmp/CDS_PV_REG_NO_${USER_NAME}_${uniqueid}"

    run_cmd "vse_sub \
        -v ${VSE_VERSION} \
        -env ${ICM_ENV} \
        -replay ../replay_${num}.il \
        -log ../../../CDS_log/CDS_${uniqueid}_${num}.log"
)

log "[TEST ${num}] DONE"
