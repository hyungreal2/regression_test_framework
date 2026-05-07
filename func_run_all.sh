#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
export script_dir

source "${script_dir}/code/env.sh"
source "${script_dir}/code/common.sh"

readonly FUNC_VALID_MODES=(
    checkHier renameRefLib changeRefLib
    replace deleteAllMarkers
    copyHierToEmpty copyHierToNonEmpty
)

#######################################
# Log file
#######################################
mkdir -p "${script_dir}/log"
logfile="${script_dir}/log/func_run_all.log.$(date +%Y%m%d_%H%M%S).txt"
exec > >(tee "${logfile}") 2>&1
log "Logging to ${logfile}"

#######################################
# Defaults
#######################################
libname=""
cellname=""
fromLib="All"
toLib=""
fromCell=""
prefix=""
min=""
min_set=false
max=""
max_set=false
cases=""
cases_set=false
jobs=4
do_teardown=false
modes_filter=()

#######################################
# Help
#######################################
print_help() {
    cat <<EOF
Usage: $(basename "$0") [options]

Runs func_main.sh for each mode sequentially.
Modes whose required args are missing are skipped automatically.

Options:
  -h | --help              Print this help message
  -modes <m1,m2,...>       Comma-sep modes to run (default: all valid modes)
  -lib   | --library <n>   Library name
  -cell  | --cell <n>      Cell name
  -fromLib <n>             Source library name (default: All)
  -toLib <n>               Destination library name
  -fromCell <n>            Source cell name
  -prefix <p>              Variant prefix
  -m  | --min <n>          Minimum test number
  -M  | --max <n>          Maximum test number
  -c  | --cases <list>     Specific cases (e.g. 1,3,5-9)
  -j  | --jobs <n>         Parallel jobs per mode (default: ${jobs})
  -d  | --dry-run [n]      Dry-run level 0/1/2 (default: ${DRY_RUN})
  -t  | --teardown         Run teardown after each mode

Valid modes:
  ${FUNC_VALID_MODES[*]}

Examples:
  $(basename "$0") -lib ESD01 -cell FULLCHIP -toLib DstLib -fromCell myCell -fromLib SrcLib
  $(basename "$0") -modes checkHier,replace -lib ESD01 -cell FULLCHIP -d 2
EOF
}

#######################################
# Parse args
#######################################
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)        print_help; exit 0 ;;
        -lib|--library)   libname="$2";  shift 2 ;;
        -cell|--cell)     cellname="$2"; shift 2 ;;
        -fromLib)         fromLib="$2";  shift 2 ;;
        -toLib)           toLib="$2";    shift 2 ;;
        -fromCell)        fromCell="$2"; shift 2 ;;
        -prefix|--prefix) prefix="$2";  shift 2 ;;
        -m|--min)         min="$2"; min_set=true; shift 2 ;;
        -M|--max)         max="$2"; max_set=true; shift 2 ;;
        -c|--cases)       cases="$2"; cases_set=true; shift 2 ;;
        -j|--jobs)
            [[ "${2:-}" =~ ^[0-9]+$ ]] || error_exit "-j requires a positive integer"
            jobs="$2"; shift 2 ;;
        -d|--dry-run)
            if [[ "${2:-}" =~ ^[012]$ ]]; then DRY_RUN="$2"; shift 2
            else DRY_RUN=2; shift; fi ;;
        -t|--teardown)    do_teardown=true; shift ;;
        -modes|--modes)
            IFS=',' read -ra modes_filter <<< "$2"; shift 2 ;;
        *)  error_exit "Unknown option: $1" ;;
    esac
done

export DRY_RUN

#######################################
# Determine modes to run
#######################################
if [[ ${#modes_filter[@]} -gt 0 ]]; then
    run_modes=("${modes_filter[@]}")
else
    run_modes=("${FUNC_VALID_MODES[@]}")
fi

#######################################
# Run each mode
#######################################
skipped=()
ran=()
failed=()

log "Modes to attempt (${#run_modes[@]}): ${run_modes[*]}"
log "Common args — lib=${libname} cell=${cellname} fromLib=${fromLib} toLib=${toLib} fromCell=${fromCell}"

for mode in "${run_modes[@]}"; do
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "MODE: ${mode}"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    #######################################
    # Build mode-specific required args;
    # skip if any required arg is missing
    #######################################
    mode_args=()
    skip=false

    case "${mode}" in
        checkHier|replace|deleteAllMarkers)
            if [[ -z "${libname}" || -z "${cellname}" ]]; then
                warn "Skipping ${mode}: -lib and -cell are required"
                skip=true
            else
                mode_args+=(-lib "${libname}" -cell "${cellname}")
            fi
            ;;
        renameRefLib)
            if [[ -z "${libname}" || -z "${cellname}" || -z "${toLib}" ]]; then
                warn "Skipping ${mode}: -lib, -cell, and -toLib are required"
                skip=true
            else
                mode_args+=(-lib "${libname}" -cell "${cellname}" \
                            -fromLib "${fromLib}" -toLib "${toLib}")
            fi
            ;;
        changeRefLib)
            if [[ -z "${libname}" || -z "${toLib}" ]]; then
                warn "Skipping ${mode}: -lib and -toLib are required"
                skip=true
            else
                mode_args+=(-lib "${libname}" -toLib "${toLib}")
            fi
            ;;
        copyHierToEmpty|copyHierToNonEmpty)
            if [[ -z "${fromCell}" || -z "${toLib}" ]]; then
                warn "Skipping ${mode}: -fromLib, -fromCell, and -toLib are required"
                skip=true
            else
                mode_args+=(-fromLib "${fromLib}" -fromCell "${fromCell}" -toLib "${toLib}")
            fi
            ;;
        *)
            warn "Unknown mode: ${mode}"
            skip=true
            ;;
    esac

    if [[ "${skip}" == true ]]; then
        skipped+=("${mode}")
        continue
    fi

    #######################################
    # Append common optional args
    #######################################
    [[ -n "${prefix}"         ]] && mode_args+=(-prefix "${prefix}")
    [[ "${min_set}"  == true  ]] && mode_args+=(-m "${min}")
    [[ "${max_set}"  == true  ]] && mode_args+=(-M "${max}")
    [[ "${cases_set}" == true ]] && mode_args+=(-c "${cases}")
    mode_args+=(-j "${jobs}" -d "${DRY_RUN}")
    [[ "${do_teardown}" == true ]] && mode_args+=(-t)

    #######################################
    # Run func_main.sh for this mode
    #######################################
    log "Calling: func_main.sh -mode ${mode} ${mode_args[*]}"
    if bash "${script_dir}/func_main.sh" -mode "${mode}" "${mode_args[@]}"; then
        ran+=("${mode}")
        log "MODE ${mode}: DONE"
    else
        failed+=("${mode}")
        log "MODE ${mode}: FAILED (exit $?)"
    fi
done

#######################################
# Final summary
#######################################
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "func_run_all.sh SUMMARY"
log "  Ran     (${#ran[@]}): ${ran[*]:-none}"
log "  Skipped (${#skipped[@]}): ${skipped[*]:-none}"
log "  Failed  (${#failed[@]}): ${failed[*]:-none}"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

[[ ${#failed[@]} -eq 0 ]]
