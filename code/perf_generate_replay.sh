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
[[ $# -ge 5 ]] || error_exit "Usage: $0 <testtype> <lib> <cell> <mode> <uniqueid> [-d <level>]"
testtype="$1"
lib="$2"
cell="$3"
mode="$4"       # managed | unmanaged
uniqueid="$5"

[[ "${mode}" == "managed" || "${mode}" == "unmanaged" ]] || \
    error_exit "mode must be 'managed' or 'unmanaged', got: ${mode}"

replay_dir="${script_dir}/GenerateReplayScript"

log "[REPLAY] Generating ${testtype}_${lib}_${mode}.au (cell=${cell}, result=${uniqueid})"

(
    cd "${replay_dir}"

    run_cmd "perl createReplay.pl -lib \"${lib}\" -cell \"${cell}\" -template ${testtype} -managed \"${mode}\" -result \"${uniqueid}\""

    # createReplay.pl outputs replay.<testtype>1.au → rename to <testtype>_<lib>_<mode>.au
    local_out="replay.${testtype}1.au"
    if [[ "${DRY_RUN}" -lt 2 ]]; then
        [[ -f "${local_out}" ]] || error_exit "Expected output not found: ${local_out}"
        mv "${local_out}" "${testtype}_${lib}_${mode}.au"
        log "[REPLAY] Created: GenerateReplayScript/${testtype}_${lib}_${mode}.au"
    else
        log "[DRY-RUN:2] Would create: GenerateReplayScript/${testtype}_${lib}_${mode}.au"
    fi
)
