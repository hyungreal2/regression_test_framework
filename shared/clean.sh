#!/bin/bash
#######################################
# Remove local outputs of the suite this script sits in
# (suites/<suite>/clean.sh links here; a deployment has its own copy).
#
# Removed (every suite): CDS_log/, log/, .trash/ (workspaces already torn
#   down), code/replay_files*, code/date_virtuosoVer.txt, Python cache
# cico / func: regression_test_*/ and regression_num*.txt,
#   code/func_template_*.il (func)
# perf: GenerateReplayScript/*.au and GenerateReplayScript/lcv.txt
#
# Kept on purpose:
#   result/                  summary output
#   perf_metrics/            perf trend data (history.jsonl is append-only)
#   GDP-backed workspaces    never rm -rf'ed here, because that would orphan
#                            their GDP project / p4 client. This covers
#                            WORKSPACES_MANAGED/ and WORKSPACES_UNMANAGED/
#                            (perf), top-level cico_ws_* / func_ws_*, and any
#                            regression_test_*/ that still holds a workspace
#                            with a .gdpxl directory. The command to tear them
#                            down is printed instead.
#
# Usage: clean.sh [-n]    -n: only print what would be removed
#######################################

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"

dry=0
case "${1:-}" in
    -n|--dry-run) dry=1 ;;
    -h|--help)    sed -n '3,23p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    "")           ;;
    *)            echo "Unknown option: $1 (use -n or -h)" >&2; exit 1 ;;
esac

if   [[ -f "${script_dir}/perf_main.sh" ]]; then suite=perf
elif [[ -f "${script_dir}/func_main.sh" ]]; then suite=func
elif [[ -f "${script_dir}/main.sh" ]];      then suite=cico
else
    echo "ERROR: ${script_dir} is not a suite directory (no main.sh / perf_main.sh / func_main.sh)" >&2
    exit 1
fi

echo "Cleaning ${suite} outputs in ${script_dir}..."

kept=()

remove() {
    local p shown
    for p in "$@"; do
        [[ -e "${p}" || -L "${p}" ]] || continue
        shown="${p#${script_dir}/}"
        echo "  remove ${shown%/}"
        (( dry )) || rm -rf -- "${p}"
    done
}

# has_gdp_workspace <dir>: true if <dir> holds a workspace with a .gdpxl dir
has_gdp_workspace() {
    [[ -n "$(find "$1" -maxdepth 4 -name .gdpxl -print -quit 2>/dev/null)" ]]
}

# pending_teardown <regression_dir>: true if the run still owes a teardown
# (a -k run, or teardowns the worker reported as failed). Its queue holds
# the ids teardown_all.sh / func_teardown_all.sh need, even for tests whose
# init failed before a workspace (.gdpxl) existed.
pending_teardown() {
    [[ -f "$1/teardown_skipped" || -s "$1/teardown_queue.txt.failed" ]]
}

shopt -s nullglob

#######################################
# Common
#######################################
remove "${script_dir}/CDS_log" "${script_dir}/log" "${script_dir}/.trash"
remove "${script_dir}/code/replay_files" "${script_dir}"/code/replay_files_*/
remove "${script_dir}/code/date_virtuosoVer.txt"
remove "${script_dir}/__pycache__" "${script_dir}/code/__pycache__"
(( dry )) || find "${script_dir}" -name '*.pyc' -not -path '*/WORKSPACES_*' -delete 2>/dev/null || true

#######################################
# cico / func
#######################################
if [[ "${suite}" == cico || "${suite}" == func ]]; then
    for d in "${script_dir}"/regression_test_*/; do
        d="${d%/}"
        if has_gdp_workspace "${d}"; then
            kept+=("${d#${script_dir}/}/ (holds a GDP workspace)")
        elif pending_teardown "${d}"; then
            kept+=("${d#${script_dir}/}/ (teardown pending: -k run or failed teardowns)")
        else
            remove "${d}"
        fi
    done
    remove "${script_dir}/regression_num.txt" "${script_dir}"/regression_num_*.txt
    if [[ "${suite}" == func ]]; then
        remove "${script_dir}"/code/func_template_*.il
    fi
    for d in "${script_dir}"/cico_ws_*/ "${script_dir}"/func_ws_*/; do
        d="${d%/}"
        if has_gdp_workspace "${d}"; then
            kept+=("$(basename "${d}")/ (GDP workspace)")
        else
            remove "${d}"   # mock workspace of an old dry-run level 1 run
        fi
    done
fi

#######################################
# perf
#######################################
if [[ "${suite}" == perf ]]; then
    remove "${script_dir}"/GenerateReplayScript/*.au "${script_dir}/GenerateReplayScript/lcv.txt"
    # Mock workspaces of dry-run level 1 have no .gdpxl: remove them (and the
    # UNMANAGED copy of the same name). Real MANAGED workspaces always have
    # .gdpxl and are kept, together with their UNMANAGED copy.
    for d in "${script_dir}"/WORKSPACES_MANAGED/*/; do
        d="${d%/}"
        has_gdp_workspace "${d}" && continue
        remove "${d}" "${script_dir}/WORKSPACES_UNMANAGED/$(basename "${d}")"
    done
    # An UNMANAGED copy whose MANAGED workspace is gone (e.g. perf_teardown.sh
    # trashed MANAGED but failed to remove UNMANAGED) has no GDP backing
    # (DMTYPE none) and nothing would ever find it again: remove it.
    for d in "${script_dir}"/WORKSPACES_UNMANAGED/*/; do
        d="${d%/}"
        [[ -e "${script_dir}/WORKSPACES_MANAGED/$(basename "${d}")" ]] || remove "${d}"
    done
    for d in WORKSPACES_MANAGED WORKSPACES_UNMANAGED; do
        [[ -d "${script_dir}/${d}" ]] || continue
        if [[ -n "$(ls -A "${script_dir}/${d}")" ]]; then
            kept+=("${d}/ (persistent perf workspaces)")
        else
            remove "${script_dir}/${d}"
        fi
    done
fi

#######################################
# Report what was kept
#######################################
if (( ${#kept[@]} > 0 )); then
    echo
    echo "Kept (GDP-backed, not deleted by clean.sh):"
    printf '  %s\n' "${kept[@]}"
    case "${suite}" in
        cico) echo "Tear down with:  ./code/teardown_all.sh <regression_test_NNN>   (then run ./clean.sh again)" ;;
        func) echo "Tear down with:  ./code/func_teardown_all.sh <regression_test_<mode>_NNN>   (then run ./clean.sh again)" ;;
        perf) echo "Tear down with:  ./perf_main.sh -no-run -t   (then run ./clean.sh again)" ;;
    esac
fi
[[ -d "${script_dir}/result" ]]       && echo "Kept result/ (summary output)."
[[ -d "${script_dir}/perf_metrics" ]] && echo "Kept perf_metrics/ (trend data)."

echo "Done."
