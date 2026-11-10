#!/bin/bash

set -euo pipefail

#######################################
# Shared pristine copy of the FROM_LIB libraries
#
# One GDP project (PERF_PREFIX_pristine_<uniqueid>) whose config holds every
# library a perf workspace was initialised with, built once into
# PERF_PRISTINE_DIR/<name>. UNMANAGED workspaces copy oa/<lib> from it
# (perf_copy_lib), so cdsinfo.tag (DMTYPE p4 → none) and ug+w are fixed
# here once instead of in every workspace. Nothing is ever opened or
# submitted in it: the depot copy of FROM_LIB stays as imported.
#
# Incremental: a library already in the config is not created again; a new
# one is added and fetched with gdp rebuild workspace. A library whose
# FROM_LIB change number (newest change synced there) moved since it was
# imported stops the init (the MANAGED workspaces would import the new
# data, the pristine has the old). Unreadable numbers are not checked.
#
# State in PERF_PRISTINE_DIR:
#   .name        project / workspace name
#   .libs/<lib>  library added to the config; holds its FROM_LIB change number
#   .ready/<lib> library fetched, patched and writable
#   .lock        held while this script runs (concurrent perf_main.sh)
#######################################

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

[[ -n "${script_dir:-}" ]] || { echo "ERROR: script_dir is not set. Run via perf_main.sh." >&2; exit 1; }
source "${script_dir}/code/env.sh"
source "${script_dir}/code/common.sh"
source "${script_dir}/code/perf_icm.sh"

[[ $# -ge 2 ]] || error_exit "Usage: $0 <uniqueid> <lib>... [-d <level>]"
uniqueid="$1"
shift
libs=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--dry-run) shift; [[ "${1:-}" =~ ^[012]$ ]] && shift ;;
        *)            libs+=("$1"); shift ;;
    esac
done

base="${script_dir}/${PERF_PRISTINE_DIR}"

if [[ "${DRY_RUN}" -ge 2 ]]; then
    log "[PRISTINE][DRY-RUN:2] Would create/extend ${base}/${PERF_PREFIX}_pristine_* with: ${libs[*]}"
    exit 0
fi

mkdir -p "${base}/.libs" "${base}/.ready"
exec 9>"${base}/.lock"
flock 9

# source_cl <lib>: newest change synced in FROM_LIB/<lib> (its #have);
# empty when it cannot be read (dry run, or not an xlp4 workspace)
source_cl() {
    local cl
    cl=$(cd "${FROM_LIB}/$1" && run_cmd "xlp4 changes -m1 \"./...#have\"" 2>/dev/null | awk '{print $2}') || true
    [[ "${cl}" =~ ^[0-9]+$ ]] && echo "${cl}"
    return 0
}

#######################################
# Project (first time only)
#######################################
if [[ -s "${base}/.name" ]]; then
    name=$(head -1 "${base}/.name")
else
    name="${PERF_PREFIX}_pristine_${uniqueid}"
    log "[PRISTINE] Creating GDP project: ${PERF_GDP_BASE}/${name}"
    create_gdp_project "${PERF_GDP_BASE}/${name}"
    run_cmd "gdp create variant ${PERF_GDP_BASE}/${name}/rev01"
    run_cmd "gdp create libtype ${PERF_GDP_BASE}/${name}/rev01/oa --libspec oa"
    run_cmd "gdp create config ${PERF_GDP_BASE}/${name}/rev01/dev"
    echo "${name}" > "${base}/.name"
fi
proj_path="${PERF_GDP_BASE}/${name}"
config="${proj_path}/rev01/dev"
ws="${base}/${name}"

#######################################
# Libraries: add new ones, check imported ones
#######################################
added=()
for l in "${libs[@]}"; do
    [[ -d "${FROM_LIB}/${l}" || "${DRY_RUN}" -ge 1 ]] || error_exit "No source library: ${FROM_LIB}/${l}"
    cl=$(source_cl "${l}")
    [[ -n "${cl}" || "${DRY_RUN}" -ge 1 ]] || warn "[PRISTINE] Cannot read the change number of ${FROM_LIB}/${l}; not checking it for changes"
    if [[ -e "${base}/.libs/${l}" ]]; then
        old_cl=$(cat "${base}/.libs/${l}")
        [[ -z "${cl}" || -z "${old_cl}" || "${cl}" == "${old_cl}" ]] || error_exit \
            "[PRISTINE] ${FROM_LIB}/${l} moved from change ${old_cl} to ${cl} since it was imported into ${name}; remove the pristine (perf_main.sh -no-run -t -pristine) and init again"
        continue
    fi
    log "[PRISTINE] Adding library: ${l}"
    run_cmd "gdp create library \"${proj_path}/rev01/oa/${l}\" --from \"${FROM_LIB}/${l}\" --location=oa/{{library}} --columns id,name,type,path,description"
    run_cmd "gdp update \"${config}\" --add \"${proj_path}/rev01/oa/${l}\""
    echo "${cl}" > "${base}/.libs/${l}"
    added+=("${l}")
done

#######################################
# Workspace: build once, then rebuild to fetch added libraries
#######################################
export MOCK_GDP_LIBS="${libs[*]}" MOCK_GDP_CELL="cell"   # DRY_RUN=1 mock
if [[ ! -d "${ws}" ]]; then
    log "[PRISTINE] Building workspace: ${ws}"
    run_cmd "gdp build workspace --content \"${config}\" --gdp-name \"${name}\" --location \"${base}\""
elif [[ ${#added[@]} -gt 0 ]]; then
    log "[PRISTINE] Rebuilding workspace for: ${added[*]}"
    (cd "${ws}" && run_cmd "gdp rebuild workspace .")
fi

#######################################
# Make each library usable as an UNMANAGED source (once)
#######################################
for l in "${libs[@]}"; do
    [[ -e "${base}/.ready/${l}" ]] && continue
    [[ -d "${ws}/oa/${l}" ]] || error_exit "[PRISTINE] ${l} missing in ${ws}/oa after gdp build/rebuild"
    log "[PRISTINE] Preparing ${l}: ug+w, cdsinfo.tag DMTYPE p4 → none"
    # Synced files are r--r--r--; UNMANAGED copies keep these modes
    run_cmd "chmod -R ug+w \"${ws}/oa/${l}\""
    while IFS= read -r -d '' tag; do
        sed -i 's/DMTYPE p4/DMTYPE none/g' "${tag}"
    done < <(find "${ws}/oa/${l}" -name "cdsinfo.tag" -print0)
    touch "${base}/.ready/${l}"
done

log "[PRISTINE] Ready: ${ws} (${#libs[@]} libraries, ${#added[@]} new)"
