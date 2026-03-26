#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/env.sh"
source "$(dirname "$0")/common.sh"

#######################################
# Validate uniqueid
#######################################
[[ -n "${uniqueid:-}" ]] || error_exit "uniqueid is not set (must be exported from caller)"

project_name="${PROJ_PREFIX}_${uniqueid}"
ws_full="${WS_NAME}_${uniqueid}"

project_path="${GDP_BASE}/${project_name}"
project_depot_path="//depot${project_path}/..."

#######################################
# Find workspace
#######################################
ws_gdp_path=$(gdp find --type=workspace ":=${ws_full}" || true)

if [[ -n "$ws_gdp_path" ]]; then
    ws_local_path=$(gdp list "$ws_gdp_path" --columns=rootDir)

    log "Workspace path: $ws_local_path"

    run_cmd "xlp4 -c \"$ws_full\" revert \"$project_depot_path\" || true"

    run_cmd "gdp delete workspace --leave-files --force --name \"$ws_full\""

    safe_rm_rf "$ws_local_path"
fi

#######################################
# Delete client
#######################################
log "Deleting p4 client: $ws_full"
run_cmd "xlp4 -u gdpxl_manager client -d -f \"$ws_full\" || true"

#######################################
# Delete project
#######################################
run_cmd "gdp delete \"$project_path\" --recursive --force --proceed"

#######################################
# Obliterate
#######################################
run_cmd "xlp4 -u gdpxl_manager obliterate -y \"$project_depot_path\""

log "Teardown completed"
