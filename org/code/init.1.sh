#!/bin/bash

set -euo pipefail

#######################################
# Default values
#######################################
uniqueid_path="/tmp/uniqueid_cico"
ws_name="cadence_cico_ws"
proj_prefix="cadence_cico"
from_lib="/MEMORY/TEST/testProj/testVar/oa"

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
    [[ -n "${2:-}" ]] || error_exit "Option $1 requires a value"
}

#######################################
# Argument parsing
#######################################
if [[ $# -eq 0 ]]; then
    error_exit "Usage: $0 [options] <libname>..."
fi

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
        -from_lib)
            require_arg "$1" "${2:-}"
            from_lib="$2"
            shift 2
            ;;
        -*)
            error_exit "Unknown option: $1"
            ;;
        *)
            break
            ;;
    esac
done

#######################################
# Validate libs
#######################################
[[ $# -gt 0 ]] || error_exit "At least one libname required"

libs=("$@")

#######################################
# Generate unique ID (collision-safe)
#######################################
uniqueid="$(date +%Y%m%d_%H%M%S)_$$"
export uniqueid

echo "uniqueid=$uniqueid" > "$uniqueid_path"

proj_name="${proj_prefix}_${uniqueid}"
CONFIG="/MEMORY/TEST/CAT/${proj_name}/rev01/dev"

#######################################
# GDP operations
#######################################
log "Creating project: $proj_name"

gdp create project --user=gdpxl_manager "/MEMORY/TEST/CAT/$proj_name"
gdp assign role --user=gdpxl_manager "/MEMORY/TEST/CAT/$proj_name" "$USER" projman

gdp create variant "/MEMORY/TEST/CAT/$proj_name/rev01"
gdp create libtype "/MEMORY/TEST/CAT/$proj_name/rev01/oa" --libspec oa
gdp create config "$CONFIG"

#######################################
# Libraries
#######################################
for lib in "${libs[@]}"; do
    lib_from="$lib"
    lib_to="$lib"

    OA_LIB="/MEMORY/TEST/CAT/${proj_name}/rev01/oa/${lib_to}"

    log "Building library: $lib"

    gdp create library "$OA_LIB" \
        --from "$from_lib/$lib_from" \
        --columns id,name,type,path,description

    gdp update "$CONFIG" --add "$OA_LIB"
done

#######################################
# Build workspace
#######################################
ws_full="${ws_name}_${uniqueid}"

log "Building workspace: $ws_full"

gdp build workspace \
    --content "$CONFIG" \
    --gdp-name "$ws_full"

log "Init completed successfully"
