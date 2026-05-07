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

[[ -n "${script_dir:-}" ]] || { echo "ERROR: script_dir is not set. Run via func_main.sh." >&2; exit 1; }
source "${script_dir}/code/env.sh"
source "${script_dir}/code/common.sh"

[[ -n "${uniquetestid:-}" ]] || error_exit "uniquetestid is not set (must be exported from caller)"

project_name="${FUNC_PROJ_PREFIX}_${uniquetestid}"
workspace_name="${FUNC_WS_PREFIX}_${uniquetestid}"
project_gdp_path="${FUNC_GDP_BASE}/${project_name}"
project_depot_path="//depot${project_gdp_path}/..."

#######################################
# Find workspace
#######################################
log "[TEARDOWN] Finding workspace: ${workspace_name}"
ws_gdp_path=$(run_cmd "gdp find --type=workspace \":=${workspace_name}\"" || true)

if [[ -n "${ws_gdp_path}" ]]; then
    ws_local_path=$(run_cmd "gdp list \"${ws_gdp_path}\" --columns=rootDir")
    log "[TEARDOWN] Workspace local path: ${ws_local_path}"

    (
        cd "${ws_local_path}" || exit 1

        log "[TEARDOWN] Reverting opened files"
        run_cmd "xlp4 -c \"${workspace_name}\" revert \"${project_depot_path}\" > /dev/null 2>&1 || true"

        log "[TEARDOWN] Checking pending changelists"
        raw_cls=$(run_cmd "xlp4 changes -c \"${workspace_name}\" -s pending" || true)
        pending_cls=$(awk '{print $2}' <<< "${raw_cls}")
        for cl in ${pending_cls}; do
            log "[TEARDOWN] Deleting pending CL: ${cl}"
            run_cmd "xlp4 change -d ${cl}"
        done
    )

    log "[TEARDOWN] Deleting GDP workspace: ${workspace_name}"
    run_cmd "gdp delete workspace --leave-files --force --name \"${workspace_name}\""

    log "[TEARDOWN] Unlocking .gdpxl: ${ws_local_path}/.gdpxl"
    run_cmd "chmod -R u+w \"${ws_local_path}/.gdpxl\" || true"

    log "[TEARDOWN] Removing local workspace: ${ws_local_path}"
    safe_rm_rf "${ws_local_path}"
else
    log "[TEARDOWN] Workspace not found via gdp find: ${workspace_name} (may already be deleted)"
fi

#######################################
# Delete xlp4 client
#######################################
log "[TEARDOWN] Deleting xlp4 client: ${workspace_name}"
run_cmd "xlp4 client -d -f \"${workspace_name}\" || true"

#######################################
# Delete GDP project
#######################################
log "[TEARDOWN] Deleting GDP project: ${project_gdp_path}"
run_cmd "gdp delete \"${project_gdp_path}\" --recursive --force --proceed"

#######################################
# Obliterate depot
#######################################
log "[TEARDOWN] Obliterating depot: ${project_depot_path}"
run_cmd "xlp4 obliterate -y \"${project_depot_path}\" > /dev/null"

log "[TEARDOWN] Done: ${uniquetestid}"
