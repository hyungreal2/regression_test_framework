#!/bin/bash

set -euo pipefail

script_dir="${script_dir:-$(cd "$(dirname "$0")/.." && pwd)}"
export script_dir
source "${script_dir}/code/env.sh"
source "${script_dir}/code/common.sh"
jobs=4
prefix=""

#######################################
# Help
#######################################
print_help() {
    cat <<EOF
Usage: $(basename "$0") [options] [<regression_dir>]

Tears down every test of a run (p4 client, GDP workspace/project, depot)
and then removes the regression directory. With -p it also sweeps
leftover GDP projects by name (legacy ICM_deleteProj.sh -prefix), e.g.
after ./clean.sh, an interrupted run, or a run with -k.

Options:
  -h    | --help              Print this help message
  -d    | --dry-run [n]       Dry-run level 0/1/2  (default: ${DRY_RUN})
  -j    | --jobs <n>          Parallel teardown job count  (default: ${jobs})
  -p    | --prefix <p>        Also sweep GDP projects ${CICO_GDP_BASE}/<p>*
                              that have no registered workspace (e.g. -p ${PROJ_PREFIX}_).
                              Without -y the candidates are only listed.
                              Make sure no other cico run with this prefix is active.
  -y    | --yes                 Delete the swept projects and obliterate their depot files
  -ws   | --ws_name <name>    Workspace prefix used by the run  (default: <regression_dir>/run_prefixes, else ${WS_PREFIX})
  -proj | --proj_prefix <p>   Project prefix used by the run    (default: <regression_dir>/run_prefixes, else ${PROJ_PREFIX})

Arguments:
  regression_dir        Path to regression directory (e.g. regression_test_001)
                        Can also be set via exported env var \$regression_dir.
                        Optional when -p is given.
EOF
}

#######################################
# Parse args
#######################################
positional_args=()
assume_yes=false
ws_given=false
proj_given=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            print_help
            exit 0
            ;;
        -d|--dry-run)
            if [[ "${2:-}" =~ ^[012]$ ]]; then
                DRY_RUN="$2"
                shift 2
            else
                DRY_RUN=2
                shift
            fi
            ;;
        -j|--jobs)
            [[ "${2:-}" =~ ^[1-9][0-9]*$ ]] || error_exit "-j/--jobs requires a positive integer"
            jobs="$2"
            shift 2
            ;;
        -p|-prefix|--prefix)
            [[ -n "${2:-}" ]] || error_exit "$1 requires a project name prefix (e.g. ${PROJ_PREFIX}_)"
            prefix="$2"
            shift 2
            ;;
        -y|--yes)
            assume_yes=true
            shift
            ;;
        -ws|--ws_name)
            [[ -n "${2:-}" ]] || error_exit "$1 requires a value"
            WS_PREFIX="$2"
            ws_given=true
            shift 2
            ;;
        -proj|--proj_prefix)
            [[ -n "${2:-}" ]] || error_exit "$1 requires a value"
            PROJ_PREFIX="$2"
            proj_given=true
            shift 2
            ;;
        -*)
            error_exit "Unknown option: $1"
            ;;
        *)
            positional_args+=("$1")
            shift
            ;;
    esac
done

export DRY_RUN WS_PREFIX PROJ_PREFIX
export CAT_WS_PREFIX="${WS_PREFIX}" CAT_PROJ_PREFIX="${PROJ_PREFIX}"   # teardown.sh re-sources env.sh

#######################################
# Args: regression_dir (arg or env)
#######################################
regression_dir="${positional_args[0]:-${regression_dir:-}}"
if [[ -z "${prefix}" ]]; then
    [[ -n "${regression_dir}" ]] || error_exit "regression_dir not set. Pass as argument or export (or use -p <prefix>)."
fi
if [[ -n "${regression_dir}" ]]; then
    [[ -d "${regression_dir}" ]] || error_exit "Directory not found: ${regression_dir}"
    # Prefixes the run used (main.sh -ws/-proj), unless given here
    _pfx_file="${regression_dir}/run_prefixes"
    if [[ -f "${_pfx_file}" ]]; then
        _ws=$(sed -n 's/^WS_PREFIX=//p' "${_pfx_file}")
        _pj=$(sed -n 's/^PROJ_PREFIX=//p' "${_pfx_file}")
        [[ "${ws_given}" == true || -z "${_ws}" ]] || WS_PREFIX="${_ws}"
        [[ "${proj_given}" == true || -z "${_pj}" ]] || PROJ_PREFIX="${_pj}"
        log "Using prefixes of the run: WS_PREFIX=${WS_PREFIX} PROJ_PREFIX=${PROJ_PREFIX}"
    fi
    export WS_PREFIX PROJ_PREFIX CAT_WS_PREFIX="${WS_PREFIX}" CAT_PROJ_PREFIX="${PROJ_PREFIX}"
    export regression_dir   # teardown.sh uses it for the DRY_RUN=1 mock workspace
fi

overall_rc=0

#######################################
# Per-test teardown of one regression dir
#######################################
if [[ -n "${regression_dir}" ]]; then
    #######################################
    # Collect uniquetestids from workspace dirs
    # (workspace name = ${WS_PREFIX}_${uniquetestid})
    #######################################
    log "Starting teardown for all tests in ${regression_dir} (jobs=${jobs})"

    uid_list=()
    for testdir in "${regression_dir}"/test_*/; do
        [[ -d "${testdir}" ]] || continue
        _found=false
        for ws_dir in "${testdir}"/${WS_PREFIX}_*/; do
            [[ -d "${ws_dir}" ]] || continue
            _ws=$(basename "${ws_dir}")
            uid_list+=("${_ws#${WS_PREFIX}_}")
            _found=true
            break
        done
        [[ "${_found}" == true ]] || warn "No workspace dir (${WS_PREFIX}_*) in ${testdir}, skipping"
    done

    # Every test the run queued (teardown_queue.txt, written even with -k)
    # and every teardown that failed in the run's background worker
    # (teardown_queue.txt.failed). Their workspace dir may already be gone,
    # e.g. when init failed after "gdp create project"; teardown.sh is
    # idempotent, so ids that were already torn down are harmless.
    for _qf in "${regression_dir}/teardown_queue.txt" "${regression_dir}/teardown_queue.txt.failed"; do
        [[ -f "${_qf}" ]] || continue
        while read -r _uid; do
            [[ -n "${_uid}" ]] || continue
            [[ " ${uid_list[*]:-} " == *" ${_uid} "* ]] && continue
            log "Adding teardown from $(basename "${_qf}"): ${_uid}"
            uid_list+=("${_uid}")
        done < "${_qf}"
    done

    #######################################
    # Run teardowns in parallel
    #######################################
    td_rc=0
    if [[ ${#uid_list[@]} -eq 0 ]]; then
        # Normal after a run whose teardown already ran: the regression
        # dir is still removed below.
        log "No per-test teardown needed (no workspace dirs left)."
    else
        printf "%s\n" "${uid_list[@]}" | \
            xargs -n1 -P"${jobs}" bash -c "
                export uniquetestid=\"\$1\"
                bash \"${script_dir}/code/teardown.sh\" -d \"${DRY_RUN}\"
            " _ || td_rc=$?
    fi

    if [[ ${td_rc} -eq 0 ]]; then
        log "All teardowns completed."
        log "Removing regression directory: ${regression_dir}"
        safe_rm_rf "${regression_dir}"
    else
        overall_rc=1
        warn "Some teardowns failed (xargs rc=${td_rc}); keeping ${regression_dir} so this can be re-run."
        warn "GDP projects left without a workspace can be listed with: $(basename "$0") -p ${PROJ_PREFIX}_  (add -y to delete; no other cico run may be active)"
    fi
fi

#######################################
# GDP sweep by project-name prefix
# (legacy ICM_deleteProj.sh -prefix). Projects that still have a
# registered workspace are skipped: a run may still be using them.
#######################################
if [[ -n "${prefix}" ]]; then
    log "Sweeping GDP projects ${CICO_GDP_BASE}/${prefix}*"
    if [[ "${DRY_RUN}" -ge 1 ]]; then
        log "[DRY-RUN:${DRY_RUN}] gdp list is not run, so no projects are found to sweep"
    fi
    _swept=0
    # Fail closed: a failed gdp query must never look like "no workspace"
    if ! _projects=$(run_cmd "gdp list \"${CICO_GDP_BASE}/:project\""); then
        overall_rc=1
        warn "gdp list ${CICO_GDP_BASE}/:project failed; sweep skipped"
        _projects=""
    fi
    # fd 3, so a gdp/xlp4 call that reads stdin cannot eat the project list
    while read -r gdp_path <&3; do
        [[ -n "${gdp_path}" ]] || continue
        [[ "${gdp_path}" == "${CICO_GDP_BASE}/${prefix}"* ]] || continue

        _alive=""
        _query_ok=true
        if _vars=$(run_cmd "gdp list \"${gdp_path}/:variant\""); then
            for _var in ${_vars}; do
                if _cfgs=$(run_cmd "gdp list \"${_var}/:config\""); then
                    for _cfg in ${_cfgs}; do
                        if _w=$(run_cmd "gdp list \"${_cfg}/:workspace\""); then
                            _alive+="${_w}"
                        else
                            _query_ok=false
                        fi
                    done
                else
                    _query_ok=false
                fi
            done
        else
            _query_ok=false
        fi
        if [[ "${_query_ok}" != true ]]; then
            overall_rc=1
            warn "Skip (gdp query failed, cannot tell whether a workspace exists): ${gdp_path}"
            continue
        fi
        if [[ -n "${_alive}" ]]; then
            warn "Skip (workspace still registered): ${gdp_path}"
            continue
        fi
        if [[ "${assume_yes}" != true ]]; then
            log "[CANDIDATE] no workspace registered: ${gdp_path}  (rerun with -y to delete)"
            continue
        fi

        log "Deleting project: ${gdp_path}"
        if ! run_cmd "gdp delete \"${gdp_path}\" --recursive --force --proceed"; then
            overall_rc=1
            warn "Failed to delete project: ${gdp_path}"
            continue
        fi
        log "Obliterating depot: //depot${gdp_path}/..."
        run_cmd "xlp4 obliterate -y \"//depot${gdp_path}/...\" > /dev/null" \
            || { overall_rc=1; warn "Failed to obliterate //depot${gdp_path}/..."; }
        _swept=$(( _swept + 1 ))
    done 3<<< "${_projects}"
    log "Sweep done: ${_swept} project(s) deleted"
fi

# flush_trash returns 1 when there is no .trash (e.g. at dry-run)
flush_trash || true
exit "${overall_rc}"
