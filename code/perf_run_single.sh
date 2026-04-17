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

script_dir="${script_dir:-$(cd "$(dirname "$0")/.." && pwd)}"
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
mode_upper="${mode^^}"
ws_dir="${script_dir}/WORKSPACES_${mode_upper}/${ws_name}"

log "[RUN] ${testtype}/${lib}/${mode} ws=${ws_name}"

[[ -d "${ws_dir}" ]] || error_exit "Workspace directory not found: ${ws_dir}"

#######################################
# Run vse_run inside workspace
#######################################
log "[RUN] Running vse_run in ${ws_dir}"
(
    cd "${ws_dir}" || exit 1

    run_cmd "mkdir -p \"../../CDS_log/${uniqueid}\""
    run_cmd "vse_run \
        -v ${VSE_VERSION} \
        -replay ./${testtype}_${lib}.au \
        -log ../../CDS_log/${uniqueid}/${testtype}_${lib}_${mode}.log"
)

log "[RUN] Done: ${testtype}/${lib}/${mode}"
