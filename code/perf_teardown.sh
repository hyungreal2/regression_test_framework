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

[[ -n "${script_dir:-}" ]] || { echo "ERROR: script_dir is not set. Run via main.sh or perf_main.sh." >&2; exit 1; }
source "${script_dir}/code/env.sh"
source "${script_dir}/code/common.sh"

#######################################
# Args
#######################################
[[ $# -ge 1 ]] || error_exit "Usage: $0 <ws_name> [-d <level>]"
ws_name="$1"

proj_path="${PERF_GDP_BASE}/${ws_name}"
proj_depot_path="//depot${proj_path}/..."
unmanaged_ws="${script_dir}/WORKSPACES_UNMANAGED/${ws_name}"

log "[TEARDOWN] ws=${ws_name}"

#######################################
# Find MANAGED workspace via gdp find
#######################################
log "[TEARDOWN] Finding workspace: ${ws_name}"
ws_gdp_path=$(run_cmd "gdp find --type=workspace \":=${ws_name}\"" || true)

if [[ -n "${ws_gdp_path}" ]]; then
    managed_ws=$(run_cmd "gdp list \"${ws_gdp_path}\" --columns=rootDir")
    log "[TEARDOWN] Workspace local path: ${managed_ws}"

    (
        cd "${managed_ws}" || exit 1

        #######################################
        # Revert opened files
        #######################################
        log "[TEARDOWN] Reverting opened files"
        run_cmd "xlp4 -c \"${ws_name}\" revert \"${proj_depot_path}\" > /dev/null 2>&1 || true"

        #######################################
        # Delete pending changelists
        #######################################
        log "[TEARDOWN] Checking pending changelists"
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

    if [[ "${DRY_RUN:-0}" -ge 2 ]]; then
        log "[DRY-RUN] Would move ${managed_ws} to trash"
    elif [[ -d "${managed_ws}/.gdpxl" ]]; then
        warn "[TEARDOWN] Teardown may have failed: .gdpxl still present in ${managed_ws}"
    else
        log "[TEARDOWN] Workspace teardown verified; moving to trash: ${managed_ws}"
        safe_mv_to_trash "${managed_ws}"
    fi
else
    log "[TEARDOWN] Workspace not found via gdp find: ${ws_name} (may already be deleted)"
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
run_cmd "xlp4 obliterate -y \"${proj_depot_path}\" > /dev/null"

log "[TEARDOWN] Done: ${ws_name}"
