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
[[ $# -ge 3 ]] || error_exit "Usage: $0 <testtype> <lib> <cell> [-d <level>]"
testtype="$1"
lib="$2"
cell="$3"

replay_dir="${script_dir}/GenerateReplayScript"

log "[REPLAY] Generating ${testtype}_${lib}.au (cell=${cell})"

(
    cd "${replay_dir}"

    run_cmd "perl createReplay.pl -lib \"${lib}\" -cell \"${cell}\" -template ${testtype}"

    # createReplay.pl outputs replay.<testtype>1.au → rename to <testtype>_<lib>.au
    local_out="replay.${testtype}1.au"
    if [[ "${DRY_RUN}" -lt 2 ]]; then
        [[ -f "${local_out}" ]] || error_exit "Expected output not found: ${local_out}"
        mv "${local_out}" "${testtype}_${lib}.au"
        log "[REPLAY] Created: GenerateReplayScript/${testtype}_${lib}.au"
    else
        log "[DRY-RUN:2] Would create: GenerateReplayScript/${testtype}_${lib}.au"
    fi
)
