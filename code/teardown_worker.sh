#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/env.sh"
source "$(dirname "$0")/common.sh"

#######################################
# Args
#######################################
queue_file="$1"
done_flag="$2"

log "[WORKER] started (queue=${queue_file})"

#######################################
# Process queue until main is done
# and queue is empty
#######################################
while true; do
    if [[ -s "${queue_file}" ]]; then
        # Dequeue first entry
        uniquetestid=$(head -1 "${queue_file}")
        tail -n +2 "${queue_file}" > "${queue_file}.tmp"
        mv "${queue_file}.tmp" "${queue_file}"

        export uniquetestid
        log "[WORKER] tearing down uniquetestid=${uniquetestid}"
        bash "$(dirname "$0")/teardown.sh" -d "${DRY_RUN:-1}"

    elif [[ -f "${done_flag}" ]]; then
        log "[WORKER] queue empty and main done. Exiting."
        break

    else
        sleep 2
    fi
done

log "[WORKER] all teardowns completed."
