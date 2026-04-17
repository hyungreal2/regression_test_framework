#!/bin/bash

set -euo pipefail

#######################################
# Parse -d before sourcing env.sh
#######################################
_i=1
while [[ $_i -le $# ]]; do
    _arg="${!_i}"
    if [[ "${_arg}" == "-d" || "${_arg}" == "--dry-run" ]]; then
        _j=$(( _i + 1 ))
        _next="${!_j:-}"
        if [[ "${_next}" =~ ^[012]$ ]]; then
            export DRY_RUN="${_next}"
        else
            export DRY_RUN=2
        fi
        break
    fi
    _i=$(( _i + 1 ))
done

source "$(dirname "$0")/env.sh"
source "$(dirname "$0")/common.sh"

#######################################
# Args
#######################################
[[ $# -ge 3 ]] || error_exit "Usage: $0 <testtype> <lib> <uniqueid> [-d <level>]"
testtype="$1"
lib="$2"
uniqueid="$3"

script_dir="$(cd "$(dirname "$0")" && pwd)"
project_root="$(cd "${script_dir}/.." && pwd)"

ws_name="${PERF_PREFIX}_${testtype}_${lib}_${uniqueid}"
proj_path="${PERF_GDP_BASE}/${ws_name}"
proj_depot_path="//depot${proj_path}/..."
managed_ws="${project_root}/WORKSPACES_MANAGED/${ws_name}"
unmanaged_ws="${project_root}/WORKSPACES_UNMANAGED/${ws_name}"

log "[TEARDOWN] ${testtype}/${lib} ws=${ws_name}"

#######################################
# Revert opened files in MANAGED ws
#######################################
if [[ -d "${managed_ws}" ]]; then
    log "[TEARDOWN] Reverting opened files"
    (
        cd "${managed_ws}" || exit 1
        run_cmd "xlp4 -c \"${ws_name}\" revert \"${proj_depot_path}\" > /dev/null 2>&1 || true"
    )

    #######################################
    # Delete pending changelists
    #######################################
    log "[TEARDOWN] Checking pending changelists"
    (
        cd "${managed_ws}" || exit 1
        raw_cls=$(run_cmd "xlp4 changes -c \"${ws_name}\" -s pending" || true)
        pending_cls=$(awk '{print $2}' <<< "${raw_cls}")
        for cl in ${pending_cls}; do
            log "[TEARDOWN] Deleting pending CL: ${cl}"
            run_cmd "xlp4 change -d ${cl}"
        done
    )

    #######################################
    # Delete GDP workspace
    #######################################
    log "[TEARDOWN] Deleting GDP workspace: ${ws_name}"
    run_cmd "gdp delete workspace --leave-files --force --name \"${ws_name}\""

    log "[TEARDOWN] Unlocking .gdpxl: ${managed_ws}/.gdpxl"
    run_cmd "chmod -R u+w \"${managed_ws}/.gdpxl\" || true"

    log "[TEARDOWN] Removing MANAGED workspace: ${managed_ws}"
    safe_rm_rf "${managed_ws}"
fi

#######################################
# Remove UNMANAGED workspace
#######################################
if [[ -d "${unmanaged_ws}" ]]; then
    log "[TEARDOWN] Removing UNMANAGED workspace: ${unmanaged_ws}"
    safe_rm_rf "${unmanaged_ws}"
fi

#######################################
# Delete xlp4 client
#######################################
log "[TEARDOWN] Deleting xlp4 client: ${ws_name}"
run_cmd "xlp4 client -d -f \"${ws_name}\" || true"

#######################################
# Delete GDP project
#######################################
log "[TEARDOWN] Deleting GDP project: ${proj_path}"
run_cmd "gdp delete \"${proj_path}\" --recursive --force --proceed"

#######################################
# Obliterate depot
#######################################
log "[TEARDOWN] Obliterating depot: ${proj_depot_path}"
run_cmd "xlp4 obliterate -y \"${proj_depot_path}\""

log "[TEARDOWN] Done: ${testtype}/${lib}"
