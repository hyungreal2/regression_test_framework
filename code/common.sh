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
# GDP workspace mock (DRY_RUN=1)
# Creates minimal workspace structure:
#   cds.lib, cds.libicm, oa/<lib>/<cell>/, oa/<lib>/cdsinfo.tag
# Reads MOCK_GDP_LIBS (space-separated) and MOCK_GDP_CELL from env.
#######################################
_mock_gdp_workspace() {
    local ws_dir="$1"
    local ts="$2"
    local caller="$3"

    echo "[MOCK:1][${ts}][${caller}] gdp workspace: ${ws_dir}" >&2
    mkdir -p "${ws_dir}"
    touch "${ws_dir}/cds.lib"
    touch "${ws_dir}/cds.libicm"

    if [[ -n "${MOCK_GDP_LIBS:-}" && -n "${MOCK_GDP_CELL:-}" ]]; then
        local lib
        for lib in ${MOCK_GDP_LIBS}; do
            mkdir -p "${ws_dir}/oa/${lib}/${MOCK_GDP_CELL}"
            printf "DMTYPE p4\n" > "${ws_dir}/oa/${lib}/cdsinfo.tag"
        done
    fi
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
                            _mock_gdp_workspace "${gdp_name}" "${ts}" "${caller}"
                        else
                            echo "[SKIP:1][${ts}][${caller}] ${cmd}" >&2
                        fi
                    elif [[ "${cmd}" == *"gdp rebuild workspace"* ]]; then
                        _mock_gdp_workspace "." "${ts}" "${caller}"
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
# VSE execution wrapper
# VSE_MODE=run  → vse_run  (synchronous, env 1)
# VSE_MODE=sub  → vse_sub + bwait (async submit, env 2)
#######################################
run_vse() {
    local replay="$1" logfile="$2"
    if [[ "${VSE_MODE:-run}" == "sub" ]]; then
        local vse_out job_id
        vse_out=$(run_cmd "vse_sub -v ${VSE_VERSION} -env ${ICM_ENV} -replay ${replay} -log ${logfile}")
        job_id=$(awk -F'[<>]' '{print $2}' <<< "${vse_out}")
        log "Waiting for job: ${job_id}"
        run_cmd "bwait -w \"ended(${job_id})\""
    else
        run_cmd "vse_run -v ${VSE_VERSION} -replay ${replay} -log ${logfile}"
    fi
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
