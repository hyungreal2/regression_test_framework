#!/bin/bash
set -euo pipefail

source "$(dirname "$0")/env.sh"
source "$(dirname "$0")/common.sh"

managed="$1"
replay="$2"
ws_name="$3"
lib_name="$4"
cell_name="$5"

#######################################
# unique 실행 ID (핵심)
#######################################
run_id="$(date +%Y%m%d_%H%M%S)_$$"

log "[RUN] $replay ($managed) id=$run_id"

#######################################
# isolated tmp
#######################################
tmp_dir="/tmp/perf_${USER}_${run_id}"
mkdir -p "$tmp_dir"

echo "$lib_name"  > "$tmp_dir/lib"
echo "$cell_name" > "$tmp_dir/cell"
echo "$managed"   > "$tmp_dir/managed"

#######################################
# testdir
#######################################
testdir="$(pwd)/$managed/$ws_name"

(
    cd "$testdir" || exit 1

    log "Running in $testdir"

    #######################################
    # 실행
    #######################################
    vse_run \
        -v IC251_ISR5-010 \
        -replay ../../code/replay/$replay \
        -log ../../CDS_log/${replay}_${managed}_${run_id}.log
)

log "[DONE] $replay ($managed)"
