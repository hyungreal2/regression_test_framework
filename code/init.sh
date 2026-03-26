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
CONFIG="${GDP_BASE}/${proj_name}/rev01/dev"

#######################################
# GDP operations
#######################################
log "Creating project: $proj_name"

run_cmd "gdp create project --user=gdpxl_manager ${GDP_BASE}/${proj_name}"
run_cmd "gdp assign role --user=gdpxl_manager ${GDP_BASE}/${proj_name} ${USER} projman"

run_cmd "gdp create variant ${GDP_BASE}/${proj_name}/rev01"
run_cmd "gdp create libtype ${GDP_BASE}/${proj_name}/rev01/oa --libspec oa"
run_cmd "gdp create config ${CONFIG}"

#######################################
# Libraries
#######################################
for lib in "$@"; do
    OA_LIB="${GDP_BASE}/${proj_name}/rev01/oa/${lib}"

    log "Building library: $lib"

    run_cmd "gdp create library \"$OA_LIB\" --from \"$FROM_LIB/$lib\" --columns id,name,type,path,description"
    run_cmd "gdp update \"$CONFIG\" --add \"$OA_LIB\""
done

#######################################
# Workspace
#######################################
WS_NAME="${WS_PREFIX}_${uniqueid}"

log "Building workspace: $WS_NAME"

run_cmd "gdp build workspace --content \"$CONFIG\" --gdp-name \"$WS_NAME\""

log "Init completed (uniqueid=$uniqueid)"
