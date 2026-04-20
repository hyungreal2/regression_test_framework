#!/bin/bash

set -euo pipefail

#######################################
# Parse -d before sourcing env.sh
# (env.sh sets DRY_RUN=${DRY_RUN:-1},
#  so we must export it first)
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
# Validate uniquetestid
#######################################
[[ -n "${uniquetestid:-}" ]] || error_exit "uniquetestid is not set (must be exported from caller)"

project_name="${PROJ_PREFIX}_${uniquetestid}"
workspace_name="${WS_PREFIX}_${uniquetestid}"

project_gdp_path="${CICO_GDP_BASE}/${project_name}"
project_depot_path="//depot${project_gdp_path}/..."

#######################################
# Find workspace
#######################################
log "Finding workspace: ${workspace_name}"
ws_gdp_path=$(run_cmd "gdp find --type=workspace \":=${workspace_name}\"" || true)

if [[ -n "${ws_gdp_path}" ]]; then
    log "Getting workspace local path: ${ws_gdp_path}"
    ws_local_path=$(run_cmd "gdp list \"${ws_gdp_path}\" --columns=rootDir")

    log "Workspace path: ${ws_local_path}"

    (
        cd "${ws_local_path}" || exit 1

        log "Reverting opened files: ${project_depot_path}"
        run_cmd "xlp4 -c \"${workspace_name}\" revert \"${project_depot_path}\" > /dev/null 2>&1 || true"

        #######################################
        # Delete pending changelists
        #######################################
        log "Checking pending changelists for: ${workspace_name}"
        raw_cls=$(run_cmd "xlp4 changes -c \"${workspace_name}\" -s pending" || true)
        pending_cls=$(awk '{print $2}' <<< "${raw_cls}")

        for cl in ${pending_cls}; do
            log "Deleting pending CL: ${cl}"

            #log "  Deleting shelved files in CL: ${cl}"
            #run_cmd "xlp4 shelve -c ${cl} -d 2>/dev/null || true"

            #log "  Reverting opened files in CL: ${cl}"
            #run_cmd "xlp4 revert -c ${cl} //..."

            log "  Deleting CL: ${cl}"
            run_cmd "xlp4 change -d ${cl}"
        done
    )

    log "Deleting workspace: ${workspace_name}"
    run_cmd "gdp delete workspace --leave-files --force --name \"${workspace_name}\""

    log "Unlocking .gdpxl permissions: ${ws_local_path}/.gdpxl"
    run_cmd "chmod -R u+w \"${ws_local_path}/.gdpxl\" || true"

    log "Removing local workspace: ${ws_local_path}"
    safe_rm_rf "${ws_local_path}"
fi

#######################################
# Delete client
#######################################
log "Deleting p4 client: ${workspace_name}"
#run_cmd "xlp4 --user gdpxl_manager client -d -f \"${workspace_name}\" || true"
run_cmd "xlp4 client -d -f \"${workspace_name}\" || true"

#######################################
# Delete project
#######################################
log "Deleting project: ${project_gdp_path}"
run_cmd "gdp delete \"${project_gdp_path}\" --recursive --force --proceed"

#######################################
# Obliterate
#######################################
log "Obliterating depot: ${project_depot_path}"
#run_cmd "xlp4 --user gdpxl_manager obliterate -y \"${project_depot_path}\""
run_cmd "xlp4 obliterate -y \"${project_depot_path}\""

log "Teardown completed"
