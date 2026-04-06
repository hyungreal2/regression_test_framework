#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/env.sh"
source "$(dirname "$0")/common.sh"

script_dir="$(cd "$(dirname "$0")" && pwd)"
jobs=4

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
        -j|--jobs)
            jobs="$2"
            shift 2
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
# Collect uniqueids
#######################################
log "Starting teardown for all tests in ${regression_dir} (jobs=${jobs})"

uid_list=()
for testdir in "${regression_dir}"/test_*/; do
    if [[ ! -f "${testdir}/uniqueid.txt" ]]; then
        warn "No uniqueid.txt in ${testdir}, skipping"
        continue
    fi
    uid_list+=("$(<"${testdir}/uniqueid.txt")")
done

[[ ${#uid_list[@]} -gt 0 ]] || { log "No tests to tear down."; exit 0; }

#######################################
# Run teardowns in parallel
#######################################
export script_dir
printf "%s\n" "${uid_list[@]}" | \
    xargs -n1 -P"${jobs}" bash -c '
        export uniqueid="$1"
        bash "${script_dir}/teardown.sh"
    ' _

log "All teardowns completed."

log "Removing regression directory: ${regression_dir}"
safe_rm_rf "${regression_dir}"
