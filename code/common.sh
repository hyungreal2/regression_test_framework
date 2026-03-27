#!/bin/bash

set -euo pipefail

#######################################
# Logging
#######################################
log() {
    echo "[INFO] $*"
}

warn() {
    echo "[WARN] $*" >&2
}

error_exit() {
    echo "[ERROR] $*" >&2
    exit 1
}

#######################################
# Dry-run wrapper
# Level 0: run all
# Level 1: skip gdp / xlp4 / rm
# Level 2: skip all
#######################################
run_cmd() {
    local cmd="$1"
    local first_word
    first_word=$(awk '{print $1}' <<< "${cmd}")

    case "${DRY_RUN:-0}" in
        2)
            echo "[DRY-RUN:2] ${cmd}"
            ;;
        1)
            case "${first_word}" in
                gdp|xlp4|rm|vse_sub)
                    if [[ "${cmd}" == *"gdp build workspace"* ]]; then
                        local gdp_name
                        gdp_name=$(grep -oP '(?<=--gdp-name\s)\S+' <<< "${cmd}" | tr -d "\"'" || true)
                        if [[ -n "${gdp_name}" ]]; then
                            echo "[MOCK:1] mkdir -p ${gdp_name}"
                            mkdir -p "${gdp_name}"
                        else
                            echo "[SKIP:1] ${cmd}"
                        fi
                    else
                        echo "[SKIP:1] ${cmd}"
                    fi
                    ;;
                *)
                    eval "${cmd}"
                    ;;
            esac
            ;;
        *)
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
