#!/bin/bash
#######################################
# Background teardown worker.
#
# Usage: teardown_worker.sh <queue_file> <done_flag> <teardown_script>
#
# - The queue is append-only: producers append one uniquetestid per line
#   (echo "<id>" >> queue). The worker never rewrites it; it keeps a read
#   offset, so an append can never be lost.
# - A failed teardown is logged, recorded in <queue_file>.failed and the
#   worker moves on to the next item.
# - Exits once <done_flag> exists and every queued line has been processed.
#   Exit status: 0 = all teardowns succeeded, 1 = at least one failed.
#######################################

set -uo pipefail

[[ -n "${script_dir:-}" ]] || { echo "ERROR: script_dir is not set. Run via main.sh or perf_main.sh." >&2; exit 1; }
source "${script_dir}/code/env.sh"
source "${script_dir}/code/common.sh"
# common.sh turns on errexit; the worker must survive a failing step
# and keep draining the queue, so switch it back off.
set +e

#######################################
# Args
#######################################
[[ $# -eq 3 ]] || error_exit "[WORKER] Usage: $(basename "$0") <queue_file> <done_flag> <teardown_script>"
queue_file="$1"
done_flag="$2"
teardown_script="$3"
[[ -f "${teardown_script}" ]] || error_exit "[WORKER] teardown script not found: ${teardown_script}"

log "[WORKER] started (queue=${queue_file} teardown=${teardown_script})"

#######################################
# Process queue until main is done
# and every queued line is processed
#######################################
processed=0
failed=0
main_pid=${PPID}   # the entry script starts the worker with "&"

queued_lines() {
    # wc -l counts only newline-terminated lines, so a line that is
    # still being written is never consumed.
    if [[ -f "${queue_file}" ]]; then
        wc -l < "${queue_file}"
    else
        echo 0
    fi
}

while true; do
    queued=$(queued_lines)
    if (( queued > processed )); then
        processed=$(( processed + 1 ))
        uniquetestid=$(sed -n "${processed}p" "${queue_file}")
        [[ -n "${uniquetestid}" ]] || continue

        export uniquetestid
        log "[WORKER] tearing down uniquetestid=${uniquetestid}"
        if bash "${teardown_script}" -d "${DRY_RUN:-0}"; then
            :
        else
            rc=$?
            failed=$(( failed + 1 ))
            warn "[WORKER] teardown failed (rc=${rc}) uniquetestid=${uniquetestid}; continuing"
            echo "${uniquetestid}" >> "${queue_file}.failed"
        fi

    elif [[ -f "${done_flag}" ]] || ! kill -0 "${main_pid}" 2>/dev/null; then
        # Producers finish before done_flag is created; re-check once so
        # nothing appended just before the flag is missed.
        (( $(queued_lines) > processed )) && continue
        if [[ -f "${done_flag}" ]]; then
            log "[WORKER] queue empty and main done. Exiting."
        else
            # main died without its EXIT trap (e.g. kill -9): no flag will come
            warn "[WORKER] main process ${main_pid} is gone; queue drained. Exiting."
        fi
        break

    else
        sleep 2
    fi
done

if (( failed > 0 )); then
    warn "[WORKER] ${failed} of ${processed} teardown(s) failed; ids listed in ${queue_file}.failed"
    exit 1
fi
log "[WORKER] all teardowns completed. (processed=${processed})"
exit 0
