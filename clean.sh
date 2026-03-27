#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"

echo "Cleaning outputs in ${script_dir}..."

# Regression test directories
rm -rf "${script_dir}"/regression_test_*/
rm -f  "${script_dir}/regression_num.txt"

# Log directory
rm -rf "${script_dir}/CDS_log"

# Generated replay files
rm -rf "${script_dir}/code/replay_files"

# Temp file
rm -f  "${script_dir}/code/date_virtuosoVer.txt"

# Workspaces created by dry-run level 1
rm -rf "${script_dir}"/cico_ws_*/

# Python cache
rm -rf "${script_dir}"/__pycache__
find   "${script_dir}" -name "*.pyc" -delete

echo "Done."
