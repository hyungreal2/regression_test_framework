#!/bin/bash
#######################################
# Perf workspace helpers: libraries, the shared pristine copy and the
# ICM (xlp4) init changelist of a MANAGED workspace
# Sourced by perf_main.sh, perf_pristine.sh, perf_init.sh and
# perf_run_single.sh after env.sh and common.sh
#######################################

# perf_ws_libs <testtype> <lib>: the libraries of one perf workspace
# (testtype libraries, then -common, then PERF_BASE_LIBS; no duplicates)
perf_ws_libs() {
    local tt="$1" l="$2" libs=() x
    case "${tt}" in
        checkHier|replace|deleteAllMarker)
            libs=("${l}") ;;
        renameRefLib)
            libs=("${l}" "${l}_ORIGIN" "${l}_TARGET") ;;
        changeLibRef)
            libs=("${l}" "${l}_ORIGIN" "${l}_TARGET" "${l}_MIX") ;;
        copyHierToEmpty)
            libs=("${l}" "${l}_CHIP" "${l}_COPY") ;;
        copyHierToNonEmpty)
            libs=("${l}" "${l}_CHIP") ;;
        *)
            error_exit "Unknown testtype: ${tt}" ;;
    esac
    # Libraries every perf workspace needs (e.g. DRAMLIB, which the HierCopy
    # templates skip); added once even if also given with -common
    for x in ${PERF_COMMON_LIBS:-} "${PERF_BASE_LIBS[@]}"; do
        [[ " ${libs[*]} " == *" ${x} "* ]] || libs+=("${x}")
    done
    echo "${libs[*]}"
}

# perf_pristine_ws: root of the shared pristine workspace made by
# perf_pristine.sh; returns 1 when there is none
perf_pristine_ws() {
    local base="${script_dir}/${PERF_PRISTINE_DIR}"
    [[ -s "${base}/.name" ]] || return 1
    echo "${base}/$(head -1 "${base}/.name")"
}

# perf_copy_lib <unmanaged_ws> <lib> [missing]: rsync UNMANAGED oa/<lib>
# from the pristine copy. <lib>.lock is held while copying, so a run's
# reset waits for the background copy perf_init.sh started and then only
# transfers the difference. With "missing" (that background copy) a library
# that is already copied (<lib> flag) is skipped. rsync writes physical copies (no
# copy-on-write clone sharing blocks with the pristine).
perf_copy_lib() {
    local ws="$1" lib="$2" only_missing="${3:-}" src ready
    src="$(perf_pristine_ws)/oa/${lib}" || error_exit "No pristine workspace; run perf_main.sh -no-run first"
    ready="${ws}/${PERF_OA_READY}/${lib}"
    [[ -d "${src}" ]] || error_exit "No pristine copy of ${lib}: ${src} (run perf_main.sh -no-run for it first)"
    mkdir -p "${ws}/oa/${lib}" "${ws}/${PERF_OA_READY}"
    (
        flock 8
        [[ -n "${only_missing}" && -e "${ready}" ]] && exit 0
        run_cmd "rsync -a --delete \"${src}/\" \"${ws}/oa/${lib}/\"" && touch "${ready}"
    ) 8>"${ready}.lock"
}

# perf_lib_creation_cl <ws_name> <lib>: the changelist that created <lib>.
# changes lists newest first, so the last line is the creation; check-ins
# made by tests only add lines above it. The whole history is searched
# (no #have) so a library whose files a test deleted still has its creation.
perf_lib_creation_cl() {
    local ws="$1" lib="$2"
    run_cmd "xlp4 -c \"${ws}\" changes \"//${ws}/oa/${lib}/...\"" | tail -1 | awk '{print $2}'
}

# perf_derive_init_cl <ws_name> <lib>...: the newest library creation
# changelist, i.e. the depot state right after init (every library exists
# before the first test runs). Prints nothing and returns 1 when a library
# has no history.
perf_derive_init_cl() {
    local ws="$1" lib cl max=0
    shift
    for lib in "$@"; do
        cl=$(perf_lib_creation_cl "${ws}" "${lib}") || return 1
        [[ "${cl}" =~ ^[0-9]+$ ]] || return 1
        if (( cl > max )); then
            max=${cl}
        fi
    done
    (( max > 0 )) || return 1
    echo "${max}"
}
