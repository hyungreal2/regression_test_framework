#!/bin/bash
#######################################
# ICM (xlp4) helpers for the MANAGED init changelist
# Sourced by perf_init.sh and perf_run_single.sh after env.sh and common.sh
#######################################

# perf_lib_creation_cl <ws_name> <lib>: the changelist that created <lib>.
# changes lists newest first, so the last line is the creation; check-ins
# made by tests only add lines above it. The whole history is searched
# (no #have) so a library whose files a test deleted still has its creation.
perf_lib_creation_cl() {
    local ws="$1" lib="$2"
    run_cmd "xlp4 -c \"${ws}\" changes \"//${ws}/oa/${lib}/...\"" | tail -1 | awk '{print $2}'
}

# perf_derive_init_cl <ws_name> <lib>...: the newest library creation
# changelist, i.e. the depot state right after init (every library exists
# before the first test runs). Prints nothing and returns 1 when a library
# has no history.
perf_derive_init_cl() {
    local ws="$1" lib cl max=0
    shift
    for lib in "$@"; do
        cl=$(perf_lib_creation_cl "${ws}" "${lib}") || return 1
        [[ "${cl}" =~ ^[0-9]+$ ]] || return 1
        if (( cl > max )); then
            max=${cl}
        fi
    done
    (( max > 0 )) || return 1
    echo "${max}"
}
