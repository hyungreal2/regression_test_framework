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

#######################################
# Args
#######################################
[[ $# -ge 5 ]] || error_exit "Usage: $0 <testtype> <lib> <mode> <ws_name> <uniqueid> [-d <level>]"
testtype="$1"
lib="$2"
mode="$3"     # managed | unmanaged
ws_name="$4"
uniqueid="$5"

[[ "${mode}" == "managed" || "${mode}" == "unmanaged" ]] || \
    error_exit "mode must be 'managed' or 'unmanaged', got: ${mode}"

log "[RUN] ${testtype}/${lib}/${mode} ws=${ws_name}"

#######################################
# Locate workspace directory
# MANAGED  : gdp find (authoritative, location-independent)
# UNMANAGED: derived from MANAGED path (local dir, not GDP-registered)
#######################################
ws_gdp_path=$(run_cmd "gdp find --type=workspace \":=${ws_name}\"" || true)
if [[ -n "${ws_gdp_path}" ]]; then
    managed_ws=$(run_cmd "gdp list \"${ws_gdp_path}\" --columns=rootDir")
elif [[ "${DRY_RUN}" -ge 1 ]]; then
    # gdp is skipped (1) or only printed (2): assume the perf_init.sh location
    managed_ws="${script_dir}/WORKSPACES_MANAGED/${ws_name}"
    log "[DRY-RUN:${DRY_RUN}] gdp find skipped; assuming MANAGED workspace path ${managed_ws}"
else
    error_exit "Workspace not found via gdp find: ${ws_name}"
fi
if [[ "${DRY_RUN}" -lt 2 ]]; then
    [[ -d "${managed_ws}" ]] || error_exit "MANAGED workspace directory not found: ${managed_ws}"
fi

managed_parent="$(dirname "${managed_ws}")"
unmanaged_ws="${managed_parent/%WORKSPACES_MANAGED/WORKSPACES_UNMANAGED}/${ws_name}"

if [[ "${mode}" == "managed" ]]; then
    ws_dir="${managed_ws}"
else
    if [[ "${DRY_RUN}" -lt 2 ]]; then
        [[ -d "${unmanaged_ws}" ]] || error_exit "UNMANAGED workspace directory not found: ${unmanaged_ws}"
    fi
    ws_dir="${unmanaged_ws}"
fi

#######################################
# Reset workspace data before the run (not timed)
# MANAGED  : revert files left opened by earlier runs, sync to head and
#            force-sync only files sync refuses to clobber (legacy main.template)
#            Limitation (same as legacy): files a run created that are not in
#            the depot (e.g. cells added by copyHier*) stay on disk, because
#            p4 revert keeps files opened for add and sync ignores untracked
#            files. A depot-wide `xlp4 clean` would fix that but would also
#            delete the untracked workspace files the run needs (replay .au,
#            cds.lib, .cdsenv/cdsLibMgr.il links), so it is not used until it
#            has been scoped and checked on a real ICM workspace.
# UNMANAGED: restore oa from the pristine copy saved by perf_init.sh
#######################################
_clobber_file=""
_cleanup_clobber() {
    if [[ -n "${_clobber_file}" ]]; then
        rm -f "${_clobber_file}"
    fi
}
trap '_cleanup_clobber' EXIT

reset_managed_ws() {
    local sync_out
    log "[RESET] MANAGED: revert opened files and sync (${ws_name})"
    # revert may also exit non-zero when nothing is opened: warn only
    run_cmd "xlp4 -c \"${ws_name}\" -q revert \"//${ws_name}/...\"" \
        || warn "[RESET] xlp4 revert returned non-zero (${ws_name}); continuing with sync"
    # sync exits non-zero also when it only refused to clobber writable files
    # (handled below with sync -f); any other failure means the workspace
    # was not reset, so the combo is not measured
    local sync_rc=0
    sync_out=$(run_cmd "xlp4 -c \"${ws_name}\" -q sync \"//${ws_name}/...\" 2>&1") || sync_rc=$?
    _clobber_file=$(mktemp)   # removed by the EXIT trap even if sync -f fails
    grep "Can't clobber writable file" <<< "${sync_out}" \
        | sed "s/^.*Can't clobber writable file //" > "${_clobber_file}" || true
    if (( sync_rc != 0 )) && [[ ! -s "${_clobber_file}" ]]; then
        printf '%s\n' "${sync_out}" | tail -5 >&2
        error_exit "[RESET] MANAGED reset failed: xlp4 sync rc=${sync_rc} (${ws_name}); not measuring on unreset data"
    fi
    if [[ -s "${_clobber_file}" ]]; then
        log "[RESET] Force-syncing $(wc -l < "${_clobber_file}") writable file(s)"
        run_cmd "xlp4 -c \"${ws_name}\" -x \"${_clobber_file}\" sync -f"
    fi
    _cleanup_clobber
    _clobber_file=""
}

reset_unmanaged_ws() {
    local pristine="${unmanaged_ws}/${PERF_PRISTINE_OA}"
    if [[ "${DRY_RUN:-0}" -ge 2 ]]; then
        log "[DRY-RUN:2] Would restore ${unmanaged_ws}/oa from ${PERF_PRISTINE_OA}"
        return 0
    fi
    if [[ ! -d "${pristine}" ]]; then
        warn "[RESET] No pristine copy (${pristine}); workspace predates it, running without reset"
        return 0
    fi
    command -v rsync >/dev/null || error_exit "rsync is required to restore ${unmanaged_ws}/oa"
    log "[RESET] UNMANAGED: restore oa from ${PERF_PRISTINE_OA}"
    run_cmd "rsync -a --delete \"${pristine}/\" \"${unmanaged_ws}/oa/\""
}

if [[ "${mode}" == "managed" ]]; then
    reset_managed_ws
else
    reset_unmanaged_ws
fi

#######################################
# Run VSE inside workspace
#######################################
log "[RUN] Running VSE (mode=${VSE_MODE:-run}) in ${ws_dir}"

t_start=$(date +%s)

(
    if [[ "${DRY_RUN}" -lt 2 ]]; then
        cd "${ws_dir}" || exit 1
    fi

    run_cmd "mkdir -p \"${script_dir}/CDS_log/${uniqueid}\""
    run_vse "./${testtype}_${lib}.au" "${script_dir}/CDS_log/${uniqueid}/${testtype}_${lib}_${mode}.log"
)

t_end=$(date +%s)
elapsed=$(( t_end - t_start ))
log "[RUN] Elapsed: ${elapsed}s (${testtype}/${lib}/${mode})"

# Append to shared timing file (atomic single-line append)
if [[ "${DRY_RUN}" -lt 2 ]]; then
    printf "%s\t%s\t%s\t%d\n" "${testtype}" "${lib}" "${mode}" "${elapsed}" \
        >> "${script_dir}/CDS_log/${uniqueid}/timing.tsv"
else
    log "[DRY-RUN:2] Would append timing to CDS_log/${uniqueid}/timing.tsv"
fi

log "[RUN] Done: ${testtype}/${lib}/${mode}"
