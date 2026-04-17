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

[[ -n "${script_dir:-}" ]] || { echo "ERROR: script_dir is not set. Run via main.sh or perf_main.sh." >&2; exit 1; }
source "${script_dir}/code/env.sh"
source "${script_dir}/code/common.sh"

#######################################
# Args
#######################################
[[ $# -ge 4 ]] || error_exit "Usage: $0 <testtype> <lib> <mode> <uniqueid> [-d <level>]"
testtype="$1"
lib="$2"
mode="$3"     # managed | unmanaged
uniqueid="$4"

[[ "${mode}" == "managed" || "${mode}" == "unmanaged" ]] || \
    error_exit "mode must be 'managed' or 'unmanaged', got: ${mode}"

ws_name="${PERF_PREFIX}_${testtype}_${lib}_${uniqueid}"

log "[RUN] ${testtype}/${lib}/${mode} ws=${ws_name}"

#######################################
# Locate workspace directory
# MANAGED  : gdp find (authoritative, location-independent)
# UNMANAGED: derived from MANAGED path (local dir, not GDP-registered)
#######################################
ws_gdp_path=$(run_cmd "gdp find --type=workspace \":=${ws_name}\"" || true)
[[ -n "${ws_gdp_path}" ]] || error_exit "Workspace not found via gdp find: ${ws_name}"

managed_ws=$(run_cmd "gdp list \"${ws_gdp_path}\" --columns=rootDir")
[[ -d "${managed_ws}" ]] || error_exit "MANAGED workspace directory not found: ${managed_ws}"

managed_parent="$(dirname "${managed_ws}")"
unmanaged_ws="${managed_parent/%WORKSPACES_MANAGED/WORKSPACES_UNMANAGED}/${ws_name}"

if [[ "${mode}" == "managed" ]]; then
    ws_dir="${managed_ws}"
else
    [[ -d "${unmanaged_ws}" ]] || error_exit "UNMANAGED workspace directory not found: ${unmanaged_ws}"
    ws_dir="${unmanaged_ws}"
fi

#######################################
# Run VSE inside workspace
#######################################
log "[RUN] Running VSE (mode=${VSE_MODE:-run}) in ${ws_dir}"
(
    cd "${ws_dir}" || exit 1

    run_cmd "mkdir -p \"${script_dir}/CDS_log/${uniqueid}\""
    run_vse "./${testtype}_${lib}.au" "${script_dir}/CDS_log/${uniqueid}/${testtype}_${lib}_${mode}.log"
)

log "[RUN] Done: ${testtype}/${lib}/${mode}"
