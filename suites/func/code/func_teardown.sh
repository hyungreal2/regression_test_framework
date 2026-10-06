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

[[ -n "${script_dir:-}" ]] || { echo "ERROR: script_dir is not set. Run via func_main.sh." >&2; exit 1; }
source "${script_dir}/code/env.sh"
source "${script_dir}/code/common.sh"

_td_fail=0

[[ -n "${uniquetestid:-}" ]] || error_exit "uniquetestid is not set (must be exported from caller)"

project_name="${FUNC_PROJ_PREFIX}_${uniquetestid}"
workspace_name="${FUNC_WS_PREFIX}_${uniquetestid}"
project_gdp_path="${FUNC_GDP_BASE}/${project_name}"
project_depot_path="//depot${project_gdp_path}/..."

#######################################
# Find workspace
#######################################
log "[TEARDOWN] Finding workspace: ${workspace_name}"
ws_gdp_path=$(run_cmd "gdp find --type=workspace \":=${workspace_name}\"" || true)

if [[ -n "${ws_gdp_path}" ]]; then
    ws_local_path=$(run_cmd "gdp list \"${ws_gdp_path}\" --columns=rootDir" || true)
    log "[TEARDOWN] Workspace local path: ${ws_local_path}"

    # Not fatal (as in cico teardown.sh): a stale rootDir or a failed CL
    # delete must not stop the client/workspace/project/depot cleanup
    if [[ -n "${ws_local_path}" && -d "${ws_local_path}" ]]; then
        (
            cd "${ws_local_path}" || exit 1
            _sub_rc=0

            log "[TEARDOWN] Reverting opened files"
            run_cmd "xlp4 -c \"${workspace_name}\" revert \"${project_depot_path}\" > /dev/null 2>&1 || true"

            log "[TEARDOWN] Checking pending changelists"
            raw_cls=$(run_cmd "xlp4 changes -c \"${workspace_name}\" -s pending" || true)
            pending_cls=$(awk '{print $2}' <<< "${raw_cls}")
            for cl in ${pending_cls}; do
                log "[TEARDOWN] Deleting pending CL: ${cl}"
                run_cmd "xlp4 change -d ${cl}" || { warn "[TEARDOWN] failed to delete CL ${cl} (continuing)"; _sub_rc=1; }
            done
            exit "${_sub_rc}"
        ) || { _td_fail=1; warn "[TEARDOWN] revert/pending-CL cleanup failed in ${ws_local_path} (continuing)"; }
    else
        warn "[TEARDOWN] workspace rootDir missing or stale: '${ws_local_path}' (skipping revert/CL cleanup)"
    fi

    # Legacy order: p4 client first, then the GDP workspace
    log "[TEARDOWN] Deleting xlp4 client: ${workspace_name}"
    run_cmd "xlp4 client -d -f \"${workspace_name}\" || true"

    log "[TEARDOWN] Deleting GDP workspace: ${workspace_name}"
    # Not fatal: with the client already gone some gdp versions may fail
    # here; the "still registered" check below decides whether to trash
    run_cmd "gdp delete workspace --leave-files --force --name \"${workspace_name}\"" \
        || { _td_fail=1; warn "[TEARDOWN] gdp delete workspace failed: ${workspace_name}"; }

    log "[TEARDOWN] Unlocking .gdpxl: ${ws_local_path}/.gdpxl"
    run_cmd "chmod -R u+w \"${ws_local_path}/.gdpxl\" || true"

    if [[ "${DRY_RUN:-0}" -ge 2 ]]; then
        log "[DRY-RUN] Would move ${ws_local_path} to trash"
    else
        # The local dir is trashed only once GDP confirms the record is gone
        case "$(gdp_ws_state "${workspace_name}" "${project_gdp_path}")" in
            gone)
                if [[ -z "${ws_local_path}" ]]; then
                    log "[TEARDOWN] No rootDir recorded for ${workspace_name}; no local directory to move"
                else
                    log "[TEARDOWN] Workspace teardown verified (GDP record removed); moving to trash: ${ws_local_path}"
                    safe_mv_to_trash "${ws_local_path}"
                fi ;;
            registered)
                _td_fail=1
                warn "[TEARDOWN] Teardown may have failed: workspace still registered in GDP: ${workspace_name}" ;;
            *)
                _td_fail=1
                warn "[TEARDOWN] gdp did not answer; cannot verify that ${workspace_name} is gone, keeping ${ws_local_path}" ;;
        esac
    fi
else
    log "[TEARDOWN] Workspace not found via gdp find: ${workspace_name} (may already be deleted)"
    # still remove an orphaned client (legacy deleted it unconditionally)
    log "[TEARDOWN] Deleting xlp4 client: ${workspace_name}"
    run_cmd "xlp4 client -d -f \"${workspace_name}\" || true"
fi

#######################################
# DRY_RUN=1: clean up mock workspace
# (gdp find was skipped, so ws_gdp_path
#  is empty; remove the local directory
#  that _mock_gdp_workspace() created)
#######################################
if [[ "${DRY_RUN:-0}" -eq 1 && -n "${regression_dir:-}" ]]; then
    # func uniquetestid = <mode>_<date>_<time>_<user>[_<prefix>]_<num>_<pid>:
    # num is always the second-to-last field (prefix may contain '_')
    _num="${uniquetestid%_*}"; _num="${_num##*_}"
    _mock_ws="${regression_dir}/test_${_num}/${workspace_name}"
    if [[ -d "${_mock_ws}" ]]; then
        log "[TEARDOWN] DRY_RUN=1: removing mock workspace: ${_mock_ws}"
        safe_mv_to_trash "${_mock_ws}"
    fi
fi

#######################################
# Delete GDP project
#######################################
# Idempotent: a project that is already gone (retry after a partial
# teardown, or init failed before creating it) is not a failure
project_exists=1
if [[ "${DRY_RUN:-0}" -eq 0 ]]; then
    case "$(gdp_path_state "${project_gdp_path}")" in
        gone)    project_exists=0
                 log "[TEARDOWN] GDP project already gone: ${project_gdp_path} (skipping delete)" ;;
        unknown) warn "[TEARDOWN] gdp did not answer for ${project_gdp_path} or its folder; trying the delete anyway" ;;
    esac
fi
if (( project_exists )); then
    log "[TEARDOWN] Deleting GDP project: ${project_gdp_path}"
    run_cmd "gdp delete \"${project_gdp_path}\" --recursive --force --proceed"
fi

#######################################
# Obliterate depot (best effort when the
# project was already gone)
#######################################
log "[TEARDOWN] Obliterating depot: ${project_depot_path}"
if (( project_exists )); then
    run_cmd "xlp4 obliterate -y \"${project_depot_path}\" > /dev/null"
else
    run_cmd "xlp4 obliterate -y \"${project_depot_path}\" > /dev/null" \
        || warn "[TEARDOWN] obliterate failed (best effort; project was already gone)"
fi

if (( _td_fail )); then
    warn "[TEARDOWN] Done with errors: ${uniquetestid}"
    exit 1
fi
log "[TEARDOWN] Done: ${uniquetestid}"
