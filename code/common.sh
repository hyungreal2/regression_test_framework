#!/bin/bash

set -euo pipefail

#######################################
# Logging
#######################################
_log_prefix() {
    local level="$1"
    local ts caller
    ts=$(date +%H:%M:%S)
    caller=$(basename "${BASH_SOURCE[2]:-unknown}")
    echo "[${level}][${ts}][${caller}]"
}

log() {
    echo "$(_log_prefix INFO) $*"
}

warn() {
    echo "$(_log_prefix WARN) $*" >&2
}

error_exit() {
    echo "$(_log_prefix ERROR) $*" >&2
    exit 1
}

#######################################
# Dry-run wrapper
# Level 0: run all (echo command before exec)
# Level 1: skip gdp / xlp4 / rm / vse_sub / vse_run / bwait
# Level 2: skip all
#######################################
run_cmd() {
    local cmd="$1"
    local first_word ts caller
    first_word=$(awk '{print $1}' <<< "${cmd}")
    ts=$(date +%H:%M:%S)
    caller=$(basename "${BASH_SOURCE[1]:-unknown}")

    case "${DRY_RUN:-0}" in
        2)
            echo "[DRY-RUN:2][${ts}][${caller}] ${cmd}" >&2
            ;;
        1)
            case "${first_word}" in
                gdp|xlp4|rm|vse_sub|vse_run|bwait)
                    if [[ "${cmd}" == *"gdp build workspace"* ]]; then
                        local gdp_name
                        gdp_name=$(grep -oP '(?<=--gdp-name\s)\S+' <<< "${cmd}" | tr -d "\"'" || true)
                        if [[ -n "${gdp_name}" ]]; then
                            echo "[MOCK:1][${ts}][${caller}] mkdir -p ${gdp_name}" >&2
                            mkdir -p "${gdp_name}"
                        else
                            echo "[SKIP:1][${ts}][${caller}] ${cmd}" >&2
                        fi
                    else
                        echo "[SKIP:1][${ts}][${caller}] ${cmd}" >&2
                    fi
                    ;;
                *)
                    echo "[RUN][${ts}][${caller}] ${cmd}" >&2
                    eval "${cmd}"
                    ;;
            esac
            ;;
        *)
            echo "[RUN][${ts}][${caller}] ${cmd}" >&2
            eval "${cmd}"
            ;;
    esac
}

#######################################
# Safe rm
#######################################
safe_rm_rf() {
    local target="$1"

    [[ -n "${target}" ]] || error_exit "Empty path"
    [[ "${target}" != "/" ]] || error_exit "Refuse to delete /"
    [[ "${target}" != "/home" ]] || error_exit "Refuse to delete /home"

    run_cmd "rm -rf \"${target}\""
}

#######################################
# Utility
#######################################
format_num() {
    printf "%03d" "$1"
}
