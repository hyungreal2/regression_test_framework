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
# Libraries for this testtype
#######################################
perf_libs() {
    local tt="$1" l="$2"
    case "${tt}" in
        checkHier|replace|deleteAllMarker)
            echo "${l}" ;;
        renameRefLib)
            echo "${l} ${l}_ORIGIN ${l}_TARGET" ;;
        copyHierToEmpty)
            echo "${l} ${l}_CHIP ${l}_COPY" ;;
        copyHierToNonEmpty)
            echo "${l} ${l}_CHIP" ;;
        *)
            error_exit "Unknown testtype: ${tt}" ;;
    esac
}

IFS=' ' read -ra libs <<< "$(perf_libs "${testtype}" "${lib}")"

# Export for gdp workspace mock (DRY_RUN=1)
export MOCK_GDP_LIBS="${libs[*]}"
export MOCK_GDP_CELL="${cell}"

log "[INIT] ${testtype}/${lib}/${cell} → ws=${ws_name}"

#######################################
# GDP: create project / variant / libtype / config
#######################################
log "[INIT] Creating GDP project: ${proj_path}"
run_cmd "gdp create project ${proj_path}"
run_cmd "gdp create variant ${proj_path}/rev01"
run_cmd "gdp create libtype ${proj_path}/rev01/oa --libspec oa"
run_cmd "gdp create config ${config}"

#######################################
# GDP: create libraries
#######################################
for l in "${libs[@]}"; do
    log "[INIT] Creating library: ${l}"
    run_cmd "gdp create library \"${proj_path}/rev01/oa/${l}\" --from \"${FROM_LIB}/${l}\" --columns id,name,type,path,description"
    run_cmd "gdp update \"${config}\" --add \"${proj_path}/rev01/oa/${l}\""
done

#######################################
# Build MANAGED workspace
# flock: serialise p4 protect table updates
# across parallel perf_init.sh processes
#######################################
log "[INIT] Building MANAGED workspace: ${ws_name}"
if [[ "${DRY_RUN}" -lt 2 ]]; then
    (
        flock 9
        log "[INIT] Lock acquired for gdp build workspace: ${ws_name}"
        cd "${script_dir}/WORKSPACES_MANAGED" || exit 1
        run_cmd "gdp build workspace --content \"${config}\" --gdp-name \"${ws_name}\" --location \"$(pwd)\""
    ) 9>"${script_dir}/.gdp_ws_lock"

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
# - copy non-oa files from MANAGED
# - mv oa from MANAGED to UNMANAGED
# - gdp rebuild MANAGED to restore oa
#######################################
log "[INIT] Setting up UNMANAGED workspace: ${ws_name}"
managed_ws="${script_dir}/WORKSPACES_MANAGED/${ws_name}"
unmanaged_ws="${script_dir}/WORKSPACES_UNMANAGED/${ws_name}"

if [[ "${DRY_RUN}" -lt 2 ]]; then
    run_cmd "mkdir -p \"${unmanaged_ws}\""

    # UNMANAGED: cds.lib = MANAGED's cds.libicm (no cds.libicm in UNMANAGED)
    if [[ -e "${managed_ws}/cds.libicm" ]]; then
        run_cmd "cp \"${managed_ws}/cds.libicm\" \"${unmanaged_ws}/cds.lib\""
    fi

    # mv oa MANAGED → UNMANAGED
    if [[ -d "${managed_ws}/oa" ]]; then
        log "[INIT] Moving oa: MANAGED → UNMANAGED"
        run_cmd "mv \"${managed_ws}/oa\" \"${unmanaged_ws}/oa\""

        # UNMANAGED: patch cdsinfo.tag — DMTYPE p4 → DMTYPE none
        log "[INIT] Patching cdsinfo.tag: DMTYPE p4 → DMTYPE none (UNMANAGED)"
        while IFS= read -r -d '' tag; do
            log "[INIT]   ${tag}"
            sed -i 's/DMTYPE p4/DMTYPE none/g' "${tag}"
        done < <(find "${unmanaged_ws}/oa" -name "cdsinfo.tag" -print0)

        # rebuild MANAGED to restore oa
        log "[INIT] Rebuilding MANAGED workspace to restore oa"
        (
            cd "${managed_ws}" || exit 1
            run_cmd "gdp rebuild workspace ."
        )
    else
        log "[INIT] No oa dir in managed_ws (skipped at dry-run level)"
    fi
else
    log "[DRY-RUN:2] Would setup UNMANAGED workspace and rebuild MANAGED"
fi

#######################################
# Copy replay file to both workspaces
#######################################
replay_src="${script_dir}/GenerateReplayScript/${testtype}_${lib}.au"
log "[INIT] Copying replay to workspaces"
if [[ "${DRY_RUN}" -lt 2 ]]; then
    run_cmd "cp \"${replay_src}\" \"${managed_ws}/${testtype}_${lib}.au\""
    run_cmd "cp \"${replay_src}\" \"${unmanaged_ws}/${testtype}_${lib}.au\""
else
    log "[DRY-RUN:2] Would copy ${testtype}_${lib}.au to both workspaces"
fi

log "[INIT] Done: ${testtype}/${lib}"
