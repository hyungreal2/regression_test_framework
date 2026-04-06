#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/env.sh"
source "$(dirname "$0")/common.sh"

#######################################
# Validate input
#######################################
[[ $# -gt 0 ]] || error_exit "Usage: $0 <libname> [<libname>...]"

#######################################
# Validate uniqueid
#######################################
[[ -n "${uniqueid:-}" ]] || error_exit "uniqueid is not set (must be exported from caller)"

proj_name="${PROJ_PREFIX}_${uniqueid}"
config="${GDP_BASE}/${proj_name}/rev01/dev"

#######################################
# GDP operations
#######################################
log "Creating project: ${proj_name}"
#run_cmd "gdp create project --user=gdpxl_manager ${GDP_BASE}/${proj_name}"
run_cmd "gdp create project ${GDP_BASE}/${proj_name}"

#log "Assigning role projman: ${proj_name}"
#run_cmd "gdp assign role --user=gdpxl_manager ${GDP_BASE}/${proj_name} ${USER} projman"

log "Creating variant: ${proj_name}/rev01"
run_cmd "gdp create variant ${GDP_BASE}/${proj_name}/rev01"

log "Creating libtype: ${proj_name}/rev01/oa"
run_cmd "gdp create libtype ${GDP_BASE}/${proj_name}/rev01/oa --libspec oa"

log "Creating config: ${config}"
run_cmd "gdp create config ${config}"

#######################################
# Libraries
#######################################
for lib in "$@"; do
    oa_lib="${GDP_BASE}/${proj_name}/rev01/oa/${lib}"

    log "Building library: ${lib}"

    run_cmd "gdp create library \"${oa_lib}\" --from \"${FROM_LIB}/${lib}\" --columns id,name,type,path,description"

    log "Adding ${lib} to config"
    run_cmd "gdp update \"${config}\" --add \"${oa_lib}\""
done

#######################################
# Workspace
#######################################
workspace_name="${WS_PREFIX}_${uniqueid}"

log "Building workspace: ${workspace_name}"

run_cmd "gdp build workspace --content \"${config}\" --gdp-name \"${workspace_name}\""

log "Init completed (uniqueid=${uniqueid})"
