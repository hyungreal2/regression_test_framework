#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/env.sh"
source "$(dirname "$0")/common.sh"

#######################################
# Args
#######################################
[[ $# -ge 3 ]] || error_exit "Usage: $0 <testtype> <lib> <cell>"
testtype="$1"
lib="$2"
cell="$3"

script_dir="$(cd "$(dirname "$0")" && pwd)"
replay_dir="${script_dir}/../GenerateReplayScript"

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
