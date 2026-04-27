#!/bin/bash

set -euo pipefail

[[ -n "${script_dir:-}" ]] || { echo "ERROR: script_dir is not set. Run via func_main.sh." >&2; exit 1; }
source "${script_dir}/code/env.sh"
source "${script_dir}/code/common.sh"

[[ $# -ge 1 ]] || error_exit "Usage: $0 <libname> [<libname>...]"
[[ -n "${uniquetestid:-}" ]] || error_exit "uniquetestid is not exported from caller"

proj_name="${FUNC_PROJ_PREFIX}_${uniquetestid}"
config="${FUNC_GDP_BASE}/${proj_name}/rev01/dev"

log "Creating project: ${proj_name}"
create_gdp_project "${FUNC_GDP_BASE}/${proj_name}"

log "Creating variant: ${proj_name}/rev01"
run_cmd "gdp create variant ${FUNC_GDP_BASE}/${proj_name}/rev01"

log "Creating libtype: ${proj_name}/rev01/oa"
run_cmd "gdp create libtype ${FUNC_GDP_BASE}/${proj_name}/rev01/oa --libspec oa"

log "Creating config: ${config}"
run_cmd "gdp create config ${config}"

for lib in "$@"; do
    oa_lib="${FUNC_GDP_BASE}/${proj_name}/rev01/oa/${lib}"
    log "Building library: ${lib}"
    run_cmd "gdp create library \"${oa_lib}\" --from \"${FROM_LIB}/${lib}\" --columns id,name,type,path,description"
    log "Adding ${lib} to config"
    run_cmd "gdp update \"${config}\" --add \"${oa_lib}\""
done

workspace_name="${FUNC_WS_PREFIX}_${uniquetestid}"

log "Creating workspace: ${workspace_name}"
run_cmd "gdp create workspace --content \"${config}\" --gdp-name \"${workspace_name}\" --location \"$(pwd)\""

log "func_init completed (uniquetestid=${uniquetestid})"
