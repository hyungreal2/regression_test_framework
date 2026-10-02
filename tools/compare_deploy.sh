#!/bin/bash
#######################################
# Compare a deployed suite against a prod snapshot.
#
# Runtime outputs and generated files are ignored on both sides:
# log/, CDS_log/, WORKSPACES_*, result/, regression dirs, *.au,
# GenerateReplayScript/lcv.txt, editor swap files.
#
# Exit status: 0 = identical, 1 = differences found.
#######################################

set -euo pipefail

[[ $# -eq 2 ]] || { echo "Usage: $(basename "$0") <deployed_dir> <prod_snapshot_dir>" >&2; exit 2; }

diff -r \
    -x log -x CDS_log -x result -x 'WORKSPACES_*' -x 'regression_test_*' -x 'regression_num*.txt' \
    -x '*.au' -x lcv.txt -x '*.swp' -x __pycache__ -x .trash \
    "$1" "$2"
