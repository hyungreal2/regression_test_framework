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
source "${script_dir}/code/perf_icm.sh"

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
#            force-sync only files sync refuses to clobber (legacy main.template),
#            then roll the depot back to the init changelist (ICM rollback):
#            undo every change submitted after the last clean point and
#            submit the result as a new change, so head equals the init state
#            and the next run checks in on top of it without out-of-date
#            conflicts (e.g. copyHier* adding the same cells again).
#            Limitation: files a run created but never submitted stay on
#            disk, because p4 revert keeps files opened for add and sync
#            ignores untracked files. A depot-wide `xlp4 clean` would fix that
#            but would also delete the untracked workspace files the run needs
#            (replay .au, cds.lib, .cdsenv/cdsLibMgr.il links), so it is not
#            used until it has been scoped and checked on a real ICM workspace.
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
    rollback_managed_ws
}

# managed_init_cl: prints the init changelist recorded by perf_init.sh, or (for a
# workspace initialised before it was recorded) the newest creation
# changelist of the GDP libraries perf_init.sh created, saved for next time
managed_init_cl() {
    local init_file="${managed_ws}/${PERF_INIT_CL}" cl libs
    if [[ -s "${init_file}" ]]; then
        cl=$(< "${init_file}")
    else
        warn "[RESET] ${init_file} missing; deriving the init changelist from the library creation changes"
        mapfile -t libs < <(run_cmd "gdp list \"${PERF_GDP_BASE}/${ws_name}/rev01/oa/:library\"" | awk -F/ 'NF { print $NF }')
        (( ${#libs[@]} > 0 )) || error_exit "[RESET] No GDP libraries found for ${ws_name}; cannot determine the init changelist (re-init the workspace)"
        cl=$(perf_derive_init_cl "${ws_name}" "${libs[@]}") \
            || error_exit "[RESET] Cannot determine the init changelist of ${ws_name} (re-init the workspace)"
        echo "${cl}" > "${init_file}"
        log "[RESET] Init changelist ${cl} (libraries: ${libs[*]}) saved to ${init_file}" >&2
    fi
    [[ "${cl}" =~ ^[0-9]+$ ]] || error_exit "[RESET] Invalid init changelist in ${init_file}: ${cl}"
    echo "${cl}"
}

# rollback_managed_ws: ICM rollback of the workspace's depot files to the init
# state. The workspace is synced to head (above). Only changes submitted after
# the last clean point (PERF_CLEAN_CL, where the depot last equalled the init
# state) are undone, so each rollback covers one run's check-ins. Files whose
# content is already the init revision are reverted before submit (the client
# has submitunchanged). Any failure reverts what was opened and stops the
# combo, as for a failed sync.
rollback_managed_ws() {
    local init_cl clean_cl clean_file="${managed_ws}/${PERF_CLEAN_CL}" later opened head_cl
    if [[ "${DRY_RUN:-0}" -ge 1 ]]; then
        log "[DRY-RUN:${DRY_RUN}] Would roll back the depot of ${ws_name} to its init changelist (${PERF_INIT_CL})"
        return 0
    fi
    init_cl=$(managed_init_cl)
    clean_cl="${init_cl}"
    if [[ -s "${clean_file}" ]]; then
        clean_cl=$(< "${clean_file}")
        [[ "${clean_cl}" =~ ^[0-9]+$ ]] && (( clean_cl >= init_cl )) || clean_cl="${init_cl}"
    fi

    later=$(run_cmd "xlp4 -c \"${ws_name}\" changes -m1 \"//${ws_name}/...@>${clean_cl}\"") \
        || error_exit "[RESET] xlp4 changes failed (${ws_name}); not measuring on unreset data"
    if [[ -z "${later}" ]]; then
        log "[RESET] Depot unchanged since @${clean_cl} (init @${init_cl}); no rollback needed"
        return 0
    fi

    # -q on undo / submit: they print a line per file (like revert), which
    # floods the log on a large library; errors still reach stderr
    log "[RESET] Rolling back ${ws_name} to @${init_cl}: undo changes after @${clean_cl}"
    if ! run_cmd "xlp4 -c \"${ws_name}\" -q undo \"//${ws_name}/...@>${clean_cl}\""; then
        run_cmd "xlp4 -c \"${ws_name}\" -q revert \"//${ws_name}/...\"" || true
        error_exit "[RESET] xlp4 undo failed (${ws_name}); not measuring on unreset data"
    fi
    run_cmd "xlp4 -c \"${ws_name}\" -q revert -a \"//${ws_name}/...\"" || true
    opened=$(run_cmd "xlp4 -c \"${ws_name}\" opened \"//${ws_name}/...\"") \
        || error_exit "[RESET] xlp4 opened failed (${ws_name}); not measuring on unreset data"
    if [[ -n "${opened}" ]]; then
        log "[RESET] Submitting rollback of $(wc -l <<< "${opened}") file(s)"
        if ! run_cmd "xlp4 -c \"${ws_name}\" -q submit -d \"CAT perf: roll back ${ws_name} to @${init_cl}\""; then
            run_cmd "xlp4 -c \"${ws_name}\" -q revert \"//${ws_name}/...\"" || true
            error_exit "[RESET] Rollback submit failed (${ws_name}); not measuring on unreset data"
        fi
    else
        log "[RESET] Depot content already equals @${init_cl}; nothing to submit"
    fi

    # The depot now equals the init state at its newest change
    head_cl=$(run_cmd "xlp4 -c \"${ws_name}\" changes -m1 \"//${ws_name}/...\"" | awk '{print $2}')
    if [[ "${head_cl}" =~ ^[0-9]+$ ]]; then
        echo "${head_cl}" > "${clean_file}"
        log "[RESET] Rolled back ${ws_name}; depot head @${head_cl} = init @${init_cl}"
    else
        warn "[RESET] Could not read the head changelist of ${ws_name}; next rollback starts from @${clean_cl}"
    fi
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
