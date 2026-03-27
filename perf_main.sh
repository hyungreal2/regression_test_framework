#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/code/env.sh"
source "$(dirname "$0")/code/common.sh"

#######################################
# Defaults
#######################################
ws_name="cadence_perf_ws_${USER_NAME}"
proj_prefix="cadence_perf_${USER_NAME}"
uniqueid_file="/tmp/uniqueid_perf_${USER_NAME}"
lib_name="BM01"
cell_name="VP_FULLCHIP"

man_folders=(unmanaged managed)

replay_files=(
    Test1_BM01_Check_Hierarchy.au
    Test1_BM02_Check_Hierarchy.au
    Test1_BM03_Check_Hierarchy.au
    Test2_BM01_RenameRefLibrary.au
    Test2_BM02_RenameRefLibrary.au
    Test2_BM03_RenameRefLibrary.au
    Test4_BM01_Replace.au
    Test4_BM02_Replace.au
    Test4_BM03_Replace.au
    Test5_BM01_Delete_All_Marker.au
    Test5_BM02_Delete_All_Marker.au
    Test5_BM03_Delete_All_Marker.au
    # Test6_BM01_Hier_Copy_EmptyLib.au
    # Test6_BM02_Hier_Copy_EmptyLib.au
    Test6_BM03_Hier_Copy_EmptyLib.au
    # Test7_BM01_Hier_Copy_NonEmptyLib.au
    # Test7_BM02_Hier_Copy_NonEmptyLib.au
    Test7_BM03_Hier_Copy_NonEmptyLib.au
)

#######################################
# Help
#######################################
print_help() {
    cat <<EOF
Usage: $(basename "$0") [options]

Options:
  -h     | --help               Print this help message
  -ws    | --ws_name <name>     Workspace name         (default: ${ws_name})
  -proj  | --proj_prefix <p>    Project prefix         (default: ${proj_prefix})
  -id    | --uniqueid <file>    Unique ID file         (default: ${uniqueid_file})
  -lib   | --libname <name>     Library name           (default: ${lib_name})
  -cell  | --cellname <name>    Cell name              (default: ${cell_name})
  -d     | --dry-run [n]        Dry-run level 0/1/2    (default: 2)
EOF
}

#######################################
# Parse args
#######################################
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            print_help
            exit 0
            ;;
        -ws|--ws_name)
            ws_name="$2"
            shift 2
            ;;
        -proj|--proj_prefix)
            proj_prefix="$2"
            shift 2
            ;;
        -id|--uniqueid)
            uniqueid_file="$2"
            shift 2
            ;;
        -lib|--libname)
            lib_name="$2"
            shift 2
            ;;
        -cell|--cellname)
            cell_name="$2"
            shift 2
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
        *)
            error_exit "Unknown option: $1"
            ;;
    esac
done

export DRY_RUN

#######################################
# Main
#######################################
log "START (dry-run=${DRY_RUN})"

log "Removing date_virtuosoVer.txt"
run_cmd "rm -f code/date_virtuosoVer.txt"

log "Creating output directories"
mkdir -p result
mkdir -p CDS_log

log "Writing lib/cell info to /tmp"
run_cmd "echo ${lib_name} > /tmp/perf_lib"
run_cmd "echo ${cell_name} > /tmp/perf_cell"

#######################################
# Run tests
#######################################
for managed in "${man_folders[@]}"; do
    for replay in "${replay_files[@]}"; do
        testdir="$(pwd)/${managed}/${ws_name}"

        log "Writing managed flag: ${managed}"
        run_cmd "rm -f code/managed.txt"
        run_cmd "echo ${managed} > code/managed.txt"

        log "Running perf test: ${replay} [${managed}] in ${testdir}"
        (
            cd "${testdir}" || exit 1
            run_cmd "vse_run \
                -v IC251_ISR5-010 \
                -replay ../../code/replay/${replay} \
                -log ../../CDS_log/${replay}_${managed}.log"
        )
    done
done

log "All selected tests finished."

#######################################
# Summary
#######################################
if [[ -f code/date_virtuosoVer.txt ]]; then
    date_virtuoso_ver=$(cat code/date_virtuosoVer.txt)
    log "Generating summary for version: ${date_virtuoso_ver}"
    run_cmd "code/summary.sh ${date_virtuoso_ver}"
else
    warn "date_virtuosoVer.txt not found, skipping summary"
fi
