#!/bin/bash

# No "set -e": a failed step must not stop the later ones (p4 client,
# GDP project, depot obliterate). Failures are counted in _rc and the
# script exits 1 at the end if any step failed.
set -uo pipefail

#######################################
# Parse -d before sourcing env.sh
# (env.sh sets DRY_RUN=${DRY_RUN:-0}, which keeps an already-exported
#  value, so we must export it first)
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
set +e   # common.sh turns on set -e; teardown continues past failures

_rc=0
# Run a step through run_cmd; on failure warn, count it, and continue.
_try() {
    if ! run_cmd "$1"; then
        _rc=$(( _rc + 1 ))
        warn "[TEARDOWN] step failed (continuing): $1"
    fi
}

delete_client() {
    log "Deleting p4 client: ${workspace_name}"
    #run_cmd "xlp4 --user gdpxl_manager client -d -f \"${workspace_name}\" || true"
    run_cmd "xlp4 client -d -f \"${workspace_name}\" || true"
}

#######################################
# Validate uniquetestid
#######################################
[[ -n "${uniquetestid:-}" ]] || error_exit "uniquetestid is not set (must be exported from caller)"

project_name="${PROJ_PREFIX}_${uniquetestid}"
workspace_name="${WS_PREFIX}_${uniquetestid}"

project_gdp_path="${CICO_GDP_BASE}/${project_name}"
project_depot_path="//depot${project_gdp_path}/..."

#######################################
# Find workspace
#######################################
log "Finding workspace: ${workspace_name}"
ws_gdp_path=$(run_cmd "gdp find --type=workspace \":=${workspace_name}\"" || true)

if [[ -n "${ws_gdp_path}" ]]; then
    log "Getting workspace local path: ${ws_gdp_path}"
    ws_local_path=$(run_cmd "gdp list \"${ws_gdp_path}\" --columns=rootDir" || true)

    log "Workspace path: ${ws_local_path}"

    if [[ -n "${ws_local_path}" && -d "${ws_local_path}" ]]; then
        (
            cd "${ws_local_path}" || exit 1
            _sub_rc=0

            log "Reverting opened files: ${project_depot_path}"
            run_cmd "xlp4 -c \"${workspace_name}\" revert \"${project_depot_path}\" > /dev/null 2>&1 || true"

            #######################################
            # Delete pending changelists
            #######################################
            log "Checking pending changelists for: ${workspace_name}"
            raw_cls=$(run_cmd "xlp4 changes -c \"${workspace_name}\" -s pending" || true)
            pending_cls=$(awk '{print $2}' <<< "${raw_cls}")

            for cl in ${pending_cls}; do
                log "Deleting pending CL: ${cl}"

                #log "  Deleting shelved files in CL: ${cl}"
                #run_cmd "xlp4 shelve -c ${cl} -d 2>/dev/null || true"

                #log "  Reverting opened files in CL: ${cl}"
                #run_cmd "xlp4 revert -c ${cl} //..."

                log "  Deleting CL: ${cl}"
                run_cmd "xlp4 change -d ${cl}" || { warn "[TEARDOWN] failed to delete CL ${cl} (continuing)"; _sub_rc=1; }
            done
            exit "${_sub_rc}"
        ) || { _rc=$(( _rc + 1 )); warn "[TEARDOWN] revert/pending-CL cleanup failed in ${ws_local_path} (continuing)"; }
    else
        # Not a failure: a retry after a partial teardown may find the dir gone
        warn "[TEARDOWN] workspace rootDir missing or stale: '${ws_local_path}' (skipping revert/CL cleanup)"
    fi

    # Legacy order: p4 client first, then the GDP workspace
    delete_client

    log "Deleting workspace: ${workspace_name}"
    _try "gdp delete workspace --leave-files --force --name \"${workspace_name}\""

    if [[ -n "${ws_local_path}" && -d "${ws_local_path}" ]]; then
        log "Unlocking .gdpxl permissions: ${ws_local_path}/.gdpxl"
        run_cmd "chmod -R u+w \"${ws_local_path}/.gdpxl\" || true"

        if [[ "${DRY_RUN:-0}" -ge 2 ]]; then
            log "[DRY-RUN] Would move ${ws_local_path} to trash"
        else
            # The local dir is trashed only once GDP confirms the record is gone
            case "$(gdp_ws_state "${workspace_name}" "${project_gdp_path}")" in
                gone)
                    log "Workspace teardown verified (GDP record removed); moving to trash: ${ws_local_path}"
                    safe_mv_to_trash "${ws_local_path}" || { _rc=$(( _rc + 1 )); warn "[TEARDOWN] failed to trash ${ws_local_path}"; } ;;
                registered)
                    _rc=$(( _rc + 1 ))
                    warn "Teardown may have failed: workspace still registered in GDP: ${workspace_name}" ;;
                *)
                    _rc=$(( _rc + 1 ))
                    warn "[TEARDOWN] gdp did not answer; cannot verify that ${workspace_name} is gone, keeping ${ws_local_path}" ;;
            esac
        fi
    fi
else
    log "Workspace not found in GDP: ${workspace_name}"
    # Still remove an orphaned p4 client (legacy deleted it unconditionally)
    delete_client
fi

#######################################
# DRY_RUN=1: clean up mock workspace
# (gdp find was skipped, so ws_gdp_path
#  is empty; remove the local directory
#  that _mock_gdp_workspace() created)
#######################################
if [[ "${DRY_RUN:-0}" -eq 1 && -n "${regression_dir:-}" ]]; then
    _num=$(cut -d'_' -f1 <<< "${uniquetestid}")
    _mock_ws="${regression_dir}/test_${_num}/${workspace_name}"
    if [[ -d "${_mock_ws}" ]]; then
        log "DRY_RUN=1: removing mock workspace: ${_mock_ws}"
        safe_mv_to_trash "${_mock_ws}"
    fi
fi

#######################################
# Delete project (idempotent: a project that
# is already gone is not a failure, so a retry
# of a partly torn-down test can succeed)
#######################################
project_exists=1
if [[ "${DRY_RUN:-0}" -eq 0 ]]; then
    case "$(gdp_path_state "${project_gdp_path}")" in
        gone)    project_exists=0
                 log "Project already gone: ${project_gdp_path} (skipping delete)" ;;
        unknown) warn "[TEARDOWN] gdp did not answer for ${project_gdp_path} or its folder; trying the delete anyway" ;;
    esac
fi

if (( project_exists )); then
    log "Deleting project: ${project_gdp_path}"
    _try "gdp delete \"${project_gdp_path}\" --recursive --force --proceed"
fi

#######################################
# Obliterate (best effort when the project
# was already gone: depot files may remain
# from an earlier partial teardown)
#######################################
log "Obliterating depot: ${project_depot_path}"
#run_cmd "xlp4 --user gdpxl_manager obliterate -y \"${project_depot_path}\""
if (( project_exists )); then
    _try "xlp4 obliterate -y \"${project_depot_path}\" > /dev/null"
else
    run_cmd "xlp4 obliterate -y \"${project_depot_path}\" > /dev/null" \
        || warn "[TEARDOWN] obliterate of ${project_depot_path} failed (best effort; project was already gone)"
fi

if [[ ${_rc} -eq 0 ]]; then
    log "Teardown completed"
    exit 0
fi
warn "[TEARDOWN] ${_rc} step(s) failed: uniquetestid=${uniquetestid}"
exit 1
