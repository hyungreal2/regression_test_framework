#!/bin/bash

set -euo pipefail

#######################################
# Sweep orphaned perf GDP projects
#
# perf_main.sh -t only tears down workspaces that still have a local
# WORKSPACES_MANAGED/<ws_name> directory. This script asks GDP instead
# (like legacy ICM_deleteProj.sh -prefix): it lists the projects under
# PERF_GDP_BASE named PERF_PREFIX_*, looks each one's workspace up with
# gdp find, and runs code/perf_teardown.sh for every orphan:
#   - no workspace registered in GDP, or
#   - workspace registered but its rootDir no longer exists.
# Kept (not orphans):
#   - workspace directory exists on disk (use perf_main.sh -no-run -t)
#   - WORKSPACES_MANAGED/<name> exists in this deployment
#   - project younger than -min-age minutes (perf_init.sh may still be
#     between "gdp create project" and "gdp build workspace")
#######################################

script_dir="${script_dir:-$(cd "$(dirname "$0")/.." && pwd)}"
export script_dir

source "${script_dir}/code/env.sh"
source "${script_dir}/code/common.sh"

jobs=4
assume_yes=false
min_age_min=120

print_help() {
    cat <<EOF
Usage: $(basename "$0") [options]

  Find perf GDP projects (${PERF_GDP_BASE}/${PERF_PREFIX}_*) whose workspace
  is gone and tear them down with code/perf_teardown.sh (xlp4 client,
  GDP project, depot files, local UNMANAGED copy).

OPTIONS
  -h | --help              Print this help message
  -d | --dry-run [0|1|2]   Dry-run level (default: ${DRY_RUN})
                             0 = list, confirm, tear down
                             1 = list (read-only gdp queries), teardown skips gdp/xlp4/rm
                             2 = print the queries only
  -j | --jobs <n>          Parallel teardowns (default: ${jobs}, max ${MAX_JOBS})
  -y | --yes               Do not ask for confirmation
  -min-age <minutes>       Keep projects without a workspace that are younger
                           than this (default: ${min_age_min}); 0 = no age guard

Run it on a host that sees the WORKSPACES_MANAGED directories: a workspace
whose rootDir is not visible from here is treated as orphaned.
EOF
}

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
            [[ "${2:-}" =~ ^[1-9][0-9]*$ ]] || error_exit "-j requires a positive integer"
            jobs="$2"
            shift 2
            if (( jobs > MAX_JOBS )); then
                warn "-j ${jobs} exceeds MAX_JOBS (${MAX_JOBS}); clamping to ${MAX_JOBS}"
                jobs=${MAX_JOBS}
            fi
            ;;
        -y|--yes)
            assume_yes=true
            shift
            ;;
        -min-age|--min-age)
            [[ "${2:-}" =~ ^[0-9]+$ ]] || error_exit "-min-age requires a number of minutes"
            min_age_min="$2"
            shift 2
            ;;
        *)
            error_exit "Unknown option: $1"
            ;;
    esac
done

export DRY_RUN

trap 'flush_trash || true' EXIT INT TERM

log "START perf_teardown_all (dry-run=${DRY_RUN}, prefix=${PERF_GDP_BASE}/${PERF_PREFIX}_)"

if [[ "${DRY_RUN}" -ge 2 ]]; then
    run_cmd "gdp list \"${PERF_GDP_BASE}/:project\""
    run_cmd "gdp find --type=workspace \":=<project name>\""
    log "[DRY-RUN:2] Would keep ${PERF_GDP_BASE}/${PERF_PREFIX}_* projects without a live workspace"
    log "[DRY-RUN:2] and run code/perf_teardown.sh <project name> for each, after confirmation"
    exit 0
fi

if ! command -v gdp >/dev/null 2>&1; then
    [[ "${DRY_RUN}" -ge 1 ]] || error_exit "gdp not found on PATH"
    log "[DRY-RUN:${DRY_RUN}] gdp not found on PATH; nothing to list"
    exit 0
fi

#######################################
# Project creation time from the name
# perf_<testtype>_<lib>_<YYYYmmdd>_<HHMMSS>_<user>
# Prints epoch seconds, or nothing if absent.
#######################################
project_epoch() {
    local name="$1"
    if [[ "${name}" =~ _([0-9]{8})_([0-9]{2})([0-9]{2})([0-9]{2})_ ]]; then
        date -d "${BASH_REMATCH[1]} ${BASH_REMATCH[2]}:${BASH_REMATCH[3]}:${BASH_REMATCH[4]}" +%s 2>/dev/null || true
    fi
}

#######################################
# Classify projects (read-only gdp queries)
#######################################
log "Listing GDP projects: ${PERF_GDP_BASE}/:project"
# Fail closed: a failed listing must not look like "nothing to sweep"
project_list=$(gdp list "${PERF_GDP_BASE}/:project") \
    || error_exit "gdp list ${PERF_GDP_BASE}/:project failed; nothing was deleted"
mapfile -t projects < <(
    awk '{print $1}' <<< "${project_list}" | grep "^${PERF_GDP_BASE}/${PERF_PREFIX}_" || true
)
log "Found ${#projects[@]} ${PERF_PREFIX}_* project(s)"

now=$(date +%s)

# uniqueid of a project: perf_<testtype>_<lib>_<YYYYmmdd>_<HHMMSS>_<user>
project_uid() {
    [[ "$1" =~ _([0-9]{8}_[0-9]{6}_.+)$ ]] && echo "${BASH_REMATCH[1]}"
}
# Runs that may still be initialising in this deployment: every uniqueid
# that already has a local workspace, plus the uniqueid of the latest init
# (perf_main.sh writes it to code/date_virtuosoVer.txt). perf_init.sh runs
# through xargs, so a project of such a run can exist for a long time
# before its workspace is built.
declare -A active_uid=()
for _d in "${script_dir}"/WORKSPACES_MANAGED/"${PERF_PREFIX}"_*/; do
    [[ -d "${_d}" ]] || continue
    _u=$(project_uid "$(basename "${_d}")") && active_uid[${_u}]=1
done
if [[ -f "${script_dir}/code/date_virtuosoVer.txt" ]]; then
    _u=$(head -1 "${script_dir}/code/date_virtuosoVer.txt")
    [[ -n "${_u}" ]] && active_uid[${_u}]=1
fi

orphans=()
query_failed=0
for proj in "${projects[@]}"; do
    [[ -n "${proj}" ]] || continue
    name="$(basename "${proj}")"

    if [[ -e "${script_dir}/WORKSPACES_MANAGED/${name}" ]]; then
        log "[KEEP]   ${name}: local workspace exists (use perf_main.sh -no-run -t)"
        continue
    fi

    _u=$(project_uid "${name}" || true)
    if [[ -n "${_u}" && -n "${active_uid[${_u}]:-}" ]]; then
        log "[KEEP]   ${name}: belongs to run ${_u}, which has workspaces here or is the latest init"
        continue
    fi

    # Fail closed: a failed query is not "no workspace"
    if ! ws_gdp_path=$(gdp find --type=workspace ":=${name}"); then
        warn "[SKIP]   ${name}: gdp find failed, cannot tell whether a workspace exists"
        query_failed=1
        continue
    fi
    if [[ -n "${ws_gdp_path}" ]]; then
        if ! root_dir=$(gdp list "${ws_gdp_path}" --columns=rootDir); then
            warn "[SKIP]   ${name}: gdp list rootDir failed"
            query_failed=1
            continue
        fi
        if [[ -n "${root_dir}" && -d "${root_dir}" ]]; then
            log "[KEEP]   ${name}: workspace directory exists: ${root_dir}"
            continue
        fi
        reason="workspace registered, directory missing (${root_dir:-no rootDir})"
    else
        created=$(project_epoch "${name}")
        if [[ -n "${created}" && ${min_age_min} -gt 0 ]] && (( now - created < min_age_min * 60 )); then
            log "[KEEP]   ${name}: no workspace yet, created $(( (now - created) / 60 )) min ago (< -min-age ${min_age_min})"
            continue
        fi
        reason="no workspace registered"
    fi

    log "[ORPHAN] ${name}: ${reason}"
    orphans+=("${name}")
done

if [[ ${#orphans[@]} -eq 0 ]]; then
    log "No orphaned perf projects found."
    (( query_failed == 0 )) || warn "Some projects were skipped because a gdp query failed (see [SKIP] above)"
    log "perf_teardown_all.sh DONE"
    exit "${query_failed}"
fi

#######################################
# Confirm (real teardown only)
#######################################
if [[ "${DRY_RUN}" -eq 0 && "${assume_yes}" != true ]]; then
    echo ""
    echo "About to delete ${#orphans[@]} GDP project(s), their xlp4 clients and depot files:"
    printf "  %s\n" "${orphans[@]}"
    echo -n "Proceed? [y/N] "
    answer=""
    read -r answer || answer=""   # no terminal input (EOF) counts as "no"
    [[ "${answer}" =~ ^[Yy]$ ]] || error_exit "Aborted; nothing deleted (use -y to skip the prompt)"
fi

#######################################
# Teardown (parallel)
#######################################
log "--- Teardown of ${#orphans[@]} orphan(s), jobs=${jobs} ---"
rc=0
printf "%s\n" "${orphans[@]}" | \
    xargs -n1 -P"${jobs}" bash -c "
        bash \"${script_dir}/code/perf_teardown.sh\" \"\$1\" -d \"${DRY_RUN}\"
    " _ || rc=$?

if [[ ${rc} -ne 0 || ${query_failed} -ne 0 ]]; then
    [[ ${rc} -eq 0 ]] || warn "Some teardowns failed (xargs rc=${rc})"
    [[ ${query_failed} -eq 0 ]] || warn "Some projects were skipped because a gdp query failed (see [SKIP] above)"
    log "perf_teardown_all.sh DONE (with failures)"
    exit 1
fi

log "perf_teardown_all.sh DONE"
