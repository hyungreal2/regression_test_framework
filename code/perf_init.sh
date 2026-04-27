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

if [[ -n "${PERF_COMMON_LIBS:-}" ]]; then
    for _cl in ${PERF_COMMON_LIBS}; do
        libs+=("${_cl}")
    done
fi

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
    run_cmd "gdp create library \"${proj_path}/rev01/oa/${l}\" --from \"${FROM_LIB}/${l}\" --columns id,name,type,path,description"
    run_cmd "gdp update \"${config}\" --add \"${proj_path}/rev01/oa/${l}\""
done

#######################################
# Build MANAGED workspace
# flock: serialise p4 protect table updates
# across parallel perf_init.sh processes
#######################################
log "[INIT] Creating MANAGED workspace: ${ws_name}"
if [[ "${DRY_RUN}" -lt 2 ]]; then
    run_cmd "gdp create workspace --content \"${config}\" --gdp-name \"${ws_name}\" --location \"${script_dir}/WORKSPACES_MANAGED\""

    #######################################
    # Symlinks in MANAGED workspace
    #######################################
    managed_ws_build="${script_dir}/WORKSPACES_MANAGED/${ws_name}"
    log "[INIT] Creating symlinks in MANAGED workspace"
    run_cmd "ln -sf \"${CDS_LIB_MGR}\" \"${managed_ws_build}/\""
    run_cmd "ln -sf \"${script_dir}/code/.cdsenv\" \"${managed_ws_build}/.cdsenv\""
else
    log "[DRY-RUN:2] Would: gdp create workspace --gdp-name ${ws_name}"
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

        # Patch paths: WORKSPACES_MANAGED → WORKSPACES_UNMANAGED
        log "[INIT] Patching cds.lib: WORKSPACES_MANAGED → WORKSPACES_UNMANAGED"
        sed -i "s|WORKSPACES_MANAGED|WORKSPACES_UNMANAGED|g" "${unmanaged_ws}/cds.lib"
    fi

    # mv oa MANAGED → UNMANAGED
    if [[ -d "${managed_ws}/oa" ]]; then
        log "[INIT] Moving oa: MANAGED → UNMANAGED"
        run_cmd "mv \"${managed_ws}/oa\" \"${unmanaged_ws}/oa\""

        # Grant write permission to user and group (synced files are r--r--r--)
        log "[INIT] Granting ug+w on UNMANAGED oa"
        run_cmd "chmod -R ug+w \"${unmanaged_ws}/oa\""

        # UNMANAGED: patch cdsinfo.tag — DMTYPE p4 → DMTYPE none
        log "[INIT] Patching cdsinfo.tag: DMTYPE p4 → DMTYPE none (UNMANAGED)"
        while IFS= read -r -d '' tag; do
            log "[INIT]   ${tag}"
            sed -i 's/DMTYPE p4/DMTYPE none/g' "${tag}"
        done < <(find "${unmanaged_ws}/oa" -name "cdsinfo.tag" -print0)

        # Restore MANAGED oa via force-sync
        log "[INIT] Restoring MANAGED oa: xlp4 sync -f"
        run_cmd "xlp4 -c \"${ws_name}\" -q sync -f"
    else
        log "[INIT] No oa dir in managed_ws (skipped at dry-run level)"
    fi
else
    log "[DRY-RUN:2] Would setup UNMANAGED workspace and rebuild MANAGED"
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
