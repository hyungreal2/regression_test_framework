#!/bin/bash

set -euo pipefail

[[ -n "${script_dir:-}" ]] || { echo "ERROR: script_dir is not set. Run via main.sh or perf_main.sh." >&2; exit 1; }
source "${script_dir}/code/env.sh"
source "${script_dir}/code/common.sh"

#######################################
# Validate input
#######################################
[[ $# -gt 0 ]] || error_exit "Usage: $0 <libname> [<libname>...]"

#######################################
# Validate uniquetestid
#######################################
[[ -n "${uniquetestid:-}" ]] || error_exit "uniquetestid is not set (must be exported from caller)"

proj_name="${PROJ_PREFIX}_${uniquetestid}"
config="${CICO_GDP_BASE}/${proj_name}/rev01/dev"

#######################################
# GDP operations
#######################################
log "Creating project: ${proj_name}"
#run_cmd "gdp create project --user=gdpxl_manager ${CICO_GDP_BASE}/${proj_name}"
run_cmd "gdp create project ${CICO_GDP_BASE}/${proj_name}"

#log "Assigning role projman: ${proj_name}"
#run_cmd "gdp assign role --user=gdpxl_manager ${CICO_GDP_BASE}/${proj_name} ${USER} projman"

log "Creating variant: ${proj_name}/rev01"
run_cmd "gdp create variant ${CICO_GDP_BASE}/${proj_name}/rev01"

log "Creating libtype: ${proj_name}/rev01/oa"
run_cmd "gdp create libtype ${CICO_GDP_BASE}/${proj_name}/rev01/oa --libspec oa"

log "Creating config: ${config}"
run_cmd "gdp create config ${config}"

#######################################
# Libraries
#######################################
for lib in "$@"; do
    oa_lib="${CICO_GDP_BASE}/${proj_name}/rev01/oa/${lib}"

    log "Building library: ${lib}"

    run_cmd "gdp create library \"${oa_lib}\" --from \"${FROM_LIB}/${lib}\" --columns id,name,type,path,description"

    log "Adding ${lib} to config"
    run_cmd "gdp update \"${config}\" --add \"${oa_lib}\""
done

#######################################
# Workspace
#######################################
workspace_name="${WS_PREFIX}_${uniquetestid}"

log "Creating workspace: ${workspace_name}"

(
    flock 9
    log "Lock acquired for gdp create workspace: ${workspace_name}"
    create_gdp_workspace "${workspace_name}" "${config}" "$(pwd)"
) 9>"${script_dir}/.gdp_ws_lock"

log "Init completed (uniquetestid=${uniquetestid})"
