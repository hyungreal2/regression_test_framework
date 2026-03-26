#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/env.sh"
source "$(dirname "$0")/common.sh"

#######################################
# Parse args
#######################################
while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--dry-run)
            if [[ "${2:-}" =~ ^[012]$ ]]; then
                DRY_RUN="$2"
                shift 2
            else
                DRY_RUN=2
                shift
            fi
            ;;
        -*)
            error_exit "Unknown option: $1"
            ;;
        *)
            break
            ;;
    esac
done

export DRY_RUN

#######################################
# Args: regression_dir (arg or env)
#######################################
regression_dir="${1:-${regression_dir:-}}"
[[ -n "${regression_dir}" ]] || error_exit "regression_dir not set. Pass as argument or export."

[[ -d "${regression_dir}" ]] || error_exit "Directory not found: ${regression_dir}"

#######################################
# Iterate and teardown each test
#######################################
log "Starting teardown for all tests in ${regression_dir}"

for testdir in "${regression_dir}"/test_*/; do
    [[ -f "${testdir}/uniqueid.txt" ]] || { warn "No uniqueid.txt in ${testdir}, skipping"; continue; }

    export uniqueid=$(<"${testdir}/uniqueid.txt")
    log "Tearing down ${testdir} (uniqueid=${uniqueid})"

    bash "$(dirname "$0")/teardown.sh"
done

log "All teardowns completed."
