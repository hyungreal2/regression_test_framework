#!/bin/bash

set -euo pipefail

#######################################
# Defaults
#######################################
user_name="${USER}"

uniqueid_path="/tmp/uniqueid_cico_${user_name}"
ws_name="cadence_cico_ws_${user_name}"
proj_prefix="cadence_cico_${user_name}"

#######################################
# Utils
#######################################
error_exit() {
    echo "[ERROR] $1" >&2
    exit 1
}

log() {
    echo "[INFO] $1"
}

require_arg() {
    [[ -n "${2:-}" ]] || error_exit "$1 requires value"
}

safe_rm_rf() {
    local target="$1"

    [[ -n "$target" ]] || error_exit "rm target empty"
    [[ "$target" != "/" ]] || error_exit "refuse to delete /"
    [[ "$target" != "/home" ]] || error_exit "refuse to delete /home"

    rm -rf "$target"
}

#######################################
# Argument parsing
#######################################
while [[ $# -gt 0 ]]; do
    case "$1" in
        -ws|--ws_name)
            require_arg "$1" "${2:-}"
            ws_name="$2"
            shift 2
            ;;
        -proj|--proj_prefix)
            require_arg "$1" "${2:-}"
            proj_prefix="$2"
            shift 2
            ;;
        -id|--uniqueid)
            require_arg "$1" "${2:-}"
            uniqueid_path="$2"
            shift 2
            ;;
        *)
            error_exit "Unknown option: $1"
            ;;
    esac
done

#######################################
# Load uniqueid safely
#######################################
[[ -f "$uniqueid_path" ]] || error_exit "uniqueid file not found"

uniqueid=$(grep '^uniqueid=' "$uniqueid_path" | cut -d= -f2)

[[ -n "$uniqueid" ]] || error_exit "uniqueid empty"

#######################################
# Derived names (MATCH init.sh)
#######################################
project_name="${proj_prefix}_${uniqueid}"
ws_full="${ws_name}_${uniqueid}"

project_path="/MEMORY/TEST/CAT/${project_name}"
project_depot_path="//depot${project_path}/..."

#######################################
# Find workspace paths
#######################################
ws_gdp_path=$(gdp find --type=workspace ":=${ws_full}" || true)

if [[ -z "$ws_gdp_path" ]]; then
    log "Workspace not found in GDP (already deleted?)"
else
    ws_local_path=$(gdp list "$ws_gdp_path" --columns=rootDir)
    log "Workspace local path: $ws_local_path"
fi

#######################################
# Revert files (if exists)
#######################################
if [[ -n "${ws_local_path:-}" && -d "$ws_local_path" ]]; then
    log "Reverting files"
    (
        cd "$ws_local_path"
        xlp4 -c "$ws_full" revert "$project_depot_path" || true
    )
fi

#######################################
# Delete client
#######################################
log "Deleting p4 client"
xlp4 -u gdpxl_manager client -d -f "$ws_full" || true

#######################################
# Delete workspace (GDP)
#######################################
if [[ -n "$ws_gdp_path" ]]; then
    log "Deleting workspace (GDP): $ws_full"
    gdp delete workspace \
        --leave-files \
        --force \
        --name "$ws_full" || true
fi

#######################################
# Delete local workspace
#######################################
if [[ -n "${ws_local_path:-}" && -d "$ws_local_path" ]]; then
    log "Removing local workspace: $ws_local_path"
    chmod -R 777 "$ws_local_path/.gdpxl" 2>/dev/null || true
    safe_rm_rf "$ws_local_path"
fi

#######################################
# Delete project
#######################################
log "Deleting project: $project_path"
gdp delete "$project_path" \
    --recursive \
    --force \
    --proceed || true

#######################################
# Obliterate depot
#######################################
log "Obliterating depot: $project_depot_path"
xlp4 -u gdpxl_manager obliterate -y "$project_depot_path" || true

log "Teardown completed"
