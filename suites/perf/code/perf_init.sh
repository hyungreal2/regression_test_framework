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
[[ $# -ge 4 ]] || error_exit "Usage: $0 <testtype> <lib> <cell> <uniqueid> [-d <level>]"
testtype="$1"
lib="$2"
cell="$3"
uniqueid="$4"

ws_name="${PERF_PREFIX}_${testtype}_${lib}_${uniqueid}"
proj_path="${PERF_GDP_BASE}/${ws_name}"
proj_depot_path="//depot${proj_path}/..."
config="${proj_path}/rev01/dev"

#######################################
# Libraries for this testtype (+ -common, PERF_BASE_LIBS)
#######################################
IFS=' ' read -ra libs <<< "$(perf_ws_libs "${testtype}" "${lib}")"

# Export for gdp workspace mock (DRY_RUN=1)
export MOCK_GDP_LIBS="${libs[*]}"
export MOCK_GDP_CELL="${cell}"

log "[INIT] ${testtype}/${lib}/${cell} → ws=${ws_name}"

#######################################
# GDP: create project / variant / libtype / config
#######################################
log "[INIT] Creating GDP project: ${proj_path}"
create_gdp_project "${proj_path}"
run_cmd "gdp create variant ${proj_path}/rev01"
run_cmd "gdp create libtype ${proj_path}/rev01/oa --libspec oa"
run_cmd "gdp create config ${config}"

#######################################
# GDP: create libraries
#######################################
for l in "${libs[@]}"; do
    log "[INIT] Creating library: ${l}"
    run_cmd "gdp create library \"${proj_path}/rev01/oa/${l}\" --from \"${FROM_LIB}/${l}\" --location=oa/{{library}} --columns id,name,type,path,description"
    run_cmd "gdp update \"${config}\" --add \"${proj_path}/rev01/oa/${l}\""
done

#######################################
# Build MANAGED workspace
# (no lock: builds run in parallel up to perf_main.sh -j)
#######################################
log "[INIT] Creating MANAGED workspace: ${ws_name}"
if [[ "${DRY_RUN}" -lt 2 ]]; then
    run_cmd "gdp build workspace --content \"${config}\" --gdp-name \"${ws_name}\" --location \"${script_dir}/WORKSPACES_MANAGED\""

    #######################################
    # Symlinks in MANAGED workspace
    #######################################
    managed_ws_build="${script_dir}/WORKSPACES_MANAGED/${ws_name}"
    log "[INIT] Creating symlinks in MANAGED workspace"
    run_cmd "ln -sf \"${CDS_LIB_MGR}\" \"${managed_ws_build}/\""
    run_cmd "ln -sf \"${script_dir}/code/.cdsenv\" \"${managed_ws_build}/.cdsenv\""
else
    log "[DRY-RUN:2] Would: gdp build workspace --gdp-name ${ws_name}"
fi

#######################################
# Setup UNMANAGED workspace
# - cds.lib from MANAGED's cds.libicm
# - oa/<lib> copied from the shared pristine (perf_pristine.sh) in the
#   background; MANAGED keeps the oa gdp built
#######################################
log "[INIT] Setting up UNMANAGED workspace: ${ws_name}"
managed_ws="${script_dir}/WORKSPACES_MANAGED/${ws_name}"
unmanaged_ws="${script_dir}/WORKSPACES_UNMANAGED/${ws_name}"

if [[ "${DRY_RUN}" -lt 2 ]]; then
    run_cmd "mkdir -p \"${unmanaged_ws}\""

    # UNMANAGED: cds.lib = MANAGED's cds.libicm (no cds.libicm in UNMANAGED)
    if [[ -e "${managed_ws}/cds.libicm" ]]; then
        run_cmd "cp \"${managed_ws}/cds.libicm\" \"${unmanaged_ws}/cds.lib\""

        # Patch paths: WORKSPACES_MANAGED → WORKSPACES_UNMANAGED
        log "[INIT] Patching cds.lib: WORKSPACES_MANAGED → WORKSPACES_UNMANAGED"
        sed -i "s|WORKSPACES_MANAGED|WORKSPACES_UNMANAGED|g" "${unmanaged_ws}/cds.lib"
    fi

    if [[ -d "${managed_ws}/oa" ]]; then
        # Copy oa/<lib> from the pristine in the background, one job per
        # library, at most PERF_COPY_JOBS across all inits (slot locks).
        # perf_run_single.sh restores the same way before every run; it waits
        # on <lib>.lock for a copy still in progress, so a workspace can be
        # run as soon as its own libraries are done. Not waited for here.
        mkdir -p "${unmanaged_ws}/${PERF_OA_READY}"
        printf "%s\n" "${libs[@]}" > "${unmanaged_ws}/${PERF_OA_READY}/.libs"
        log "[INIT] Copying oa from the pristine in the background: ${libs[*]} (log: ${unmanaged_ws}/${PERF_OA_READY}/copy.log)"
        for l in "${libs[@]}"; do
            (
                for (( _s = 0; ; _s = (_s + 1) % PERF_COPY_JOBS )); do
                    exec 7>"${script_dir}/WORKSPACES_UNMANAGED/.copy_slot.${_s}"
                    flock -n 7 && break
                    (( _s + 1 < PERF_COPY_JOBS )) || sleep 5
                done
                perf_copy_lib "${unmanaged_ws}" "${l}" missing
            ) >> "${unmanaged_ws}/${PERF_OA_READY}/copy.log" 2>&1 < /dev/null &
        done

        # Record the changelist the workspace holds now, before any test ran:
        # perf_run_single.sh rolls the depot back to it before every MANAGED
        # run. Taken from #have here because no test has checked in yet; the
        # library-creation derivation is what perf_run_single.sh falls back
        # to when the file is missing, so check that both agree.
        if [[ "${DRY_RUN}" -eq 0 ]]; then
            init_cl=$(run_cmd "xlp4 -c \"${ws_name}\" changes -m1 \"//${ws_name}/...#have\"" | awk '{print $2}')
            [[ "${init_cl}" =~ ^[0-9]+$ ]] || error_exit "Cannot read the init changelist of ${ws_name} (xlp4 changes -m1 #have)"
            derived_cl=$(perf_derive_init_cl "${ws_name}" "${libs[@]}") || derived_cl=""
            if [[ "${derived_cl}" != "${init_cl}" ]]; then
                warn "[INIT] Newest library creation CL (${derived_cl:-none}) != init CL ${init_cl}: init made extra check-ins, so the fallback used when ${PERF_INIT_CL} is missing would be wrong for this workspace"
            fi
            echo "${init_cl}" > "${managed_ws}/${PERF_INIT_CL}"
            echo "${init_cl}" > "${managed_ws}/${PERF_CLEAN_CL}"
            log "[INIT] Init changelist: ${init_cl} (${managed_ws}/${PERF_INIT_CL})"
        else
            log "[DRY-RUN:${DRY_RUN}] Would record the init changelist in ${managed_ws}/${PERF_INIT_CL}"
        fi
    else
        if [[ "${DRY_RUN}" -eq 0 ]]; then
            error_exit "No oa dir in MANAGED workspace after gdp build: ${managed_ws}/oa (libraries must be created with --location=oa/{{library}})"
        fi
        log "[INIT] No oa dir in managed_ws (skipped at dry-run level)"
    fi
else
    log "[DRY-RUN:2] Would setup UNMANAGED workspace and copy its oa from the pristine"
fi

#######################################
# Copy mode-specific replay files to each workspace
#######################################
replay_managed="${script_dir}/GenerateReplayScript/${testtype}_${lib}_managed.au"
replay_unmanaged="${script_dir}/GenerateReplayScript/${testtype}_${lib}_unmanaged.au"
log "[INIT] Copying replay files to workspaces"
if [[ "${DRY_RUN}" -lt 2 ]]; then
    run_cmd "cp \"${replay_managed}\"   \"${managed_ws}/${testtype}_${lib}.au\""
    run_cmd "cp \"${replay_unmanaged}\" \"${unmanaged_ws}/${testtype}_${lib}.au\""
else
    log "[DRY-RUN:2] Would copy ${testtype}_${lib}_managed.au   → MANAGED workspace"
    log "[DRY-RUN:2] Would copy ${testtype}_${lib}_unmanaged.au → UNMANAGED workspace"
fi

log "[INIT] Done: ${testtype}/${lib}"
