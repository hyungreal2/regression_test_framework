#!/bin/bash

set -euo pipefail

#######################################
# Parse -d before sourcing env.sh
#######################################
_i=1
while [[ $_i -le $# ]]; do
    _arg="${!_i}"
    if [[ "${_arg}" == "-d" || "${_arg}" == "--dry-run" ]]; then
        _j=$(( _i + 1 ))
        _next="${!_j:-}"
        if [[ "${_next}" =~ ^[012]$ ]]; then
            export DRY_RUN="${_next}"
        else
            export DRY_RUN=2
        fi
        break
    fi
    _i=$(( _i + 1 ))
done

[[ -n "${script_dir:-}" ]] || { echo "ERROR: script_dir is not set. Run via main.sh or perf_main.sh." >&2; exit 1; }
source "${script_dir}/code/env.sh"
source "${script_dir}/code/common.sh"

_td_fail=0

#######################################
# Args
#######################################
[[ $# -ge 1 ]] || error_exit "Usage: $0 <ws_name> [-d <level>]"
ws_name="$1"

proj_path="${PERF_GDP_BASE}/${ws_name}"
proj_depot_path="//depot${proj_path}/..."
unmanaged_ws="${script_dir}/WORKSPACES_UNMANAGED/${ws_name}"

log "[TEARDOWN] ws=${ws_name}"

#######################################
# Find MANAGED workspace via gdp find
#######################################
log "[TEARDOWN] Finding workspace: ${ws_name}"
ws_gdp_path=$(run_cmd "gdp find --type=workspace \":=${ws_name}\"" || true)

if [[ -n "${ws_gdp_path}" ]]; then
    managed_ws=$(run_cmd "gdp list \"${ws_gdp_path}\" --columns=rootDir" || true)
    log "[TEARDOWN] Workspace local path: ${managed_ws}"

    (
        if [[ -d "${managed_ws}" ]]; then
            cd "${managed_ws}"
        elif [[ "${DRY_RUN:-0}" -lt 2 ]]; then
            # Orphan (e.g. found by perf_teardown_all.sh): the local directory is
            # gone; the xlp4 calls below name the client with -c, so continue
            warn "[TEARDOWN] Workspace directory not found: ${managed_ws}; cleaning up client state from $(pwd)"
        fi

        #######################################
        # Revert opened files
        #######################################
        log "[TEARDOWN] Reverting opened files"
        run_cmd "xlp4 -c \"${ws_name}\" revert \"${proj_depot_path}\" > /dev/null 2>&1 || true"

        #######################################
        # Delete pending changelists
        #######################################
        log "[TEARDOWN] Checking pending changelists"
        raw_cls=$(run_cmd "xlp4 changes -c \"${ws_name}\" -s pending" || true)
        pending_cls=$(awk '{print $2}' <<< "${raw_cls}")
        _sub_rc=0
        for cl in ${pending_cls}; do
            log "[TEARDOWN] Deleting pending CL: ${cl}"
            run_cmd "xlp4 -c \"${ws_name}\" change -d ${cl}" || { warn "[TEARDOWN] failed to delete CL ${cl} (continuing)"; _sub_rc=1; }
        done
        exit "${_sub_rc}"
    ) || { _td_fail=1; warn "[TEARDOWN] revert/pending-CL cleanup failed for ${ws_name} (continuing)"; }

    #######################################
    # Delete xlp4 client (before the GDP workspace, as legacy cico/func did)
    #######################################
    log "[TEARDOWN] Deleting xlp4 client: ${ws_name}"
    run_cmd "xlp4 client -d -f \"${ws_name}\" || true"

    #######################################
    # Delete GDP workspace
    #######################################
    log "[TEARDOWN] Deleting GDP workspace: ${ws_name}"
    # Not fatal: with the client already gone some gdp versions may fail
    # here; the "still registered" check below decides whether to trash
    run_cmd "gdp delete workspace --leave-files --force --name \"${ws_name}\"" \
        || { _td_fail=1; warn "[TEARDOWN] gdp delete workspace failed: ${ws_name}"; }

    log "[TEARDOWN] Unlocking .gdpxl: ${managed_ws}/.gdpxl"
    run_cmd "chmod -R u+w \"${managed_ws}/.gdpxl\" || true"

    if [[ "${DRY_RUN:-0}" -ge 2 ]]; then
        log "[DRY-RUN] Would move ${managed_ws} to trash"
    else
        # The local dir is trashed only once GDP confirms the record is gone
        case "$(gdp_ws_state "${ws_name}" "${proj_path}")" in
            gone)
                if [[ -z "${managed_ws}" ]]; then
                    log "[TEARDOWN] No rootDir recorded for ${ws_name}; no local directory to move"
                else
                    log "[TEARDOWN] Workspace teardown verified (GDP record removed); moving to trash: ${managed_ws}"
                    safe_mv_to_trash "${managed_ws}"
                fi ;;
            registered)
                _td_fail=1
                warn "[TEARDOWN] Teardown may have failed: workspace still registered in GDP: ${ws_name}" ;;
            *)
                _td_fail=1
                warn "[TEARDOWN] gdp did not answer; cannot verify that ${ws_name} is gone, keeping ${managed_ws}" ;;
        esac
    fi
else
    log "[TEARDOWN] Workspace not found via gdp find: ${ws_name} (may already be deleted)"
    # The client can outlive its GDP workspace record; delete it anyway
    log "[TEARDOWN] Deleting xlp4 client: ${ws_name}"
    run_cmd "xlp4 client -d -f \"${ws_name}\" || true"
fi

#######################################
# Remove UNMANAGED workspace
#######################################
if [[ -d "${unmanaged_ws}" ]]; then
    log "[TEARDOWN] Removing UNMANAGED workspace: ${unmanaged_ws}"
    safe_rm_rf "${unmanaged_ws}"
fi

#######################################
# Delete GDP project
#######################################
# Idempotent: a project that is already gone is not a failure
project_exists=1
if [[ "${DRY_RUN:-0}" -eq 0 ]]; then
    case "$(gdp_path_state "${proj_path}")" in
        gone)    project_exists=0
                 log "[TEARDOWN] GDP project already gone: ${proj_path} (skipping delete)" ;;
        unknown) warn "[TEARDOWN] gdp did not answer for ${proj_path} or its folder; trying the delete anyway" ;;
    esac
fi
if (( project_exists )); then
    log "[TEARDOWN] Deleting GDP project: ${proj_path}"
    run_cmd "gdp delete \"${proj_path}\" --recursive --force --proceed"
fi

#######################################
# Obliterate depot (best effort when the
# project was already gone)
#######################################
log "[TEARDOWN] Obliterating depot: ${proj_depot_path}"
if (( project_exists )); then
    run_cmd "xlp4 obliterate -y \"${proj_depot_path}\" > /dev/null"
else
    run_cmd "xlp4 obliterate -y \"${proj_depot_path}\" > /dev/null" \
        || warn "[TEARDOWN] obliterate failed (best effort; project was already gone)"
fi

#######################################
# Left-over local MANAGED dir: after a failed "gdp delete workspace" the
# project delete (--recursive) removes the record, and a retry takes the
# "not found" branch above. perf_init.sh skips a combo whose dir exists,
# so trash it once GDP no longer lists the workspace.
#######################################
local_managed="${script_dir}/WORKSPACES_MANAGED/${ws_name}"
if [[ "${DRY_RUN:-0}" -eq 0 && -d "${local_managed}" ]]; then
    # Trash only when GDP confirms the record is gone (not when gdp is silent)
    case "$(gdp_ws_state "${ws_name}" "${proj_path}")" in
        gone)
            log "[TEARDOWN] No GDP record left; moving local workspace to trash: ${local_managed}"
            chmod -R u+w "${local_managed}/.gdpxl" 2>/dev/null || true
            safe_mv_to_trash "${local_managed}" || { _td_fail=1; warn "[TEARDOWN] failed to trash ${local_managed}"; } ;;
        registered)
            _td_fail=1
            warn "[TEARDOWN] workspace still known to GDP; keeping ${local_managed}" ;;
        *)
            _td_fail=1
            warn "[TEARDOWN] gdp did not answer; cannot verify that ${ws_name} is gone, keeping ${local_managed}" ;;
    esac
fi

#######################################
# DRY_RUN=1: remove the mock workspaces (gdp and rm are skipped at this
# level, so neither branch above removed them). A mock has no .gdpxl;
# a real workspace is never touched here.
#######################################
if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    for _mock in "${local_managed}" "${unmanaged_ws}"; do
        [[ -d "${_mock}" ]] || continue
        if [[ -e "${_mock}/.gdpxl" ]]; then
            warn "[TEARDOWN] DRY_RUN=1: ${_mock} holds a real GDP workspace; left alone"
        else
            log "[TEARDOWN] DRY_RUN=1: removing mock workspace: ${_mock}"
            safe_mv_to_trash "${_mock}"
        fi
    done
fi

if (( _td_fail )); then
    warn "[TEARDOWN] Done with errors: ${ws_name}"
    exit 1
fi
log "[TEARDOWN] Done: ${ws_name}"
