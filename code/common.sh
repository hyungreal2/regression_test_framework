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
# Level 1: skip gdp / xlp4 / rm / vse_sub / vse_run
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
                gdp|xlp4|rm|vse_sub|vse_run)
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
# VSE_MODE=sub  → vse_sub + poll bjobs (async submit, env 2)
#######################################
run_vse() {
    local replay="$1" logfile="$2"
    if [[ "${VSE_MODE:-run}" == "sub" ]]; then
        local vse_out job_id stat
        vse_out=$(run_cmd "vse_sub -v ${VSE_VERSION} -env ${ICM_ENV} -replay ${replay} -log ${logfile}")
        job_id=$(awk -F'[<>]' '{print $2}' <<< "${vse_out}")
        log "Submitted job: ${job_id}. Polling every 10s..."
        # bwait -w "ended(${job_id})"  # disabled: pending verification
        while true; do
            stat=$(bjobs -noheader -o stat "${job_id}" 2>/dev/null | awk '{print $1}')
            log "  job ${job_id} stat=${stat:-unknown}"
            case "${stat}" in
                DONE) log "Job ${job_id} finished: DONE"; break ;;
                EXIT) log "Job ${job_id} finished: EXIT"; break ;;
            esac
            sleep 10
        done
    else
        run_cmd "vse_run -v ${VSE_VERSION} -replay ${replay} -log ${logfile}"
    fi
}

#######################################
# GDP workspace build with retry
# Usage: build_gdp_workspace <ws_name> <config> [location]
# - Runs gdp build workspace; after each attempt sleeps 10s and
#   verifies the workspace exists via gdp find.
# - Retries up to GDP_WS_MAX_ATTEMPTS times (default 5).
# - At DRY_RUN>=1 delegates to run_cmd without retry.
#######################################
build_gdp_workspace() {
    local ws_name="$1" config="$2" location="${3:-}"
    local cmd="gdp build workspace --content \"${config}\" --gdp-name \"${ws_name}\""
    [[ -n "${location}" ]] && cmd="${cmd} --location \"${location}\""

    if [[ "${DRY_RUN:-0}" -ge 1 ]]; then
        run_cmd "${cmd}"
        return
    fi

    local max_attempts="${GDP_WS_MAX_ATTEMPTS:-5}"
    local attempt=0
    while [[ ${attempt} -lt ${max_attempts} ]]; do
        attempt=$(( attempt + 1 ))
        log "[WS] gdp build workspace attempt ${attempt}/${max_attempts}: ${ws_name}"
        eval "${cmd}" || true
        sleep 10
        if [[ -n "$(gdp find --type=workspace ":=${ws_name}" 2>/dev/null)" ]]; then
            log "[WS] Workspace confirmed: ${ws_name}"
            return 0
        fi
        log "[WS] Workspace not found after attempt ${attempt}, retrying..."
    done
    error_exit "gdp build workspace failed after ${max_attempts} attempts: ${ws_name}"
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
