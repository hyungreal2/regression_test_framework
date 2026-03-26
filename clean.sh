#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Cleaning outputs in ${SCRIPT_DIR}..."

# Regression test directories
rm -rf "${SCRIPT_DIR}"/regression_test_*/
rm -f  "${SCRIPT_DIR}/regression_num.txt"

# Log directory
rm -rf "${SCRIPT_DIR}/CDS_log"

# Generated replay files
rm -rf "${SCRIPT_DIR}/code/replay_files"

# Temp file
rm -f  "${SCRIPT_DIR}/code/date_virtuosoVer.txt"

# Workspaces created by dry-run level 1
rm -rf "${SCRIPT_DIR}"/cico_ws_*/

# Python cache
rm -rf "${SCRIPT_DIR}"/__pycache__
find   "${SCRIPT_DIR}" -name "*.pyc" -delete

echo "Done."
