#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/env.sh"
source "$(dirname "$0")/common.sh"

#######################################
# Validate uniqueid
#######################################
[[ -n "${uniqueid:-}" ]] || error_exit "uniqueid is not set (must be exported from caller)"

project_name="${PROJ_PREFIX}_${uniqueid}"
workspace_name="${WS_PREFIX}_${uniqueid}"

project_path="${GDP_BASE}/${project_name}"
project_depot_path="//depot${project_path}/..."

#######################################
# Find workspace
#######################################
if [[ "${DRY_RUN:-0}" -ge 1 ]]; then
    log "[SKIP:${DRY_RUN}] gdp find --type=workspace :=${workspace_name}"
    ws_gdp_path=""
else
    ws_gdp_path=$(gdp find --type=workspace ":=${workspace_name}" || true)
fi

if [[ -n "${ws_gdp_path}" ]]; then
    ws_local_path=$(gdp list "${ws_gdp_path}" --columns=rootDir)

    log "Workspace path: ${ws_local_path}"

    log "Reverting opened files: ${project_depot_path}"
    run_cmd "xlp4 -c \"${workspace_name}\" revert \"${project_depot_path}\" || true"

    log "Deleting workspace: ${workspace_name}"
    run_cmd "gdp delete workspace --leave-files --force --name \"${workspace_name}\""

    chmod -R u+w "${ws_local_path}/.gdpxl"
    safe_rm_rf "${ws_local_path}"
fi

#######################################
# Delete client
#######################################
log "Deleting p4 client: ${workspace_name}"
run_cmd "xlp4 -u gdpxl_manager client -d -f \"${workspace_name}\" || true"

#######################################
# Delete project
#######################################
log "Deleting project: ${project_path}"
run_cmd "gdp delete \"${project_path}\" --recursive --force --proceed"

#######################################
# Obliterate
#######################################
log "Obliterating depot: ${project_depot_path}"
run_cmd "xlp4 -u gdpxl_manager obliterate -y \"${project_depot_path}\""

log "Teardown completed"
