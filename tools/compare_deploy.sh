#!/bin/bash
#######################################
# Compare a deployed suite against a prod snapshot.
#
# Runtime outputs and generated files are ignored on both sides
# (kept in sync with .gitignore):
#   log/, CDS_log/, result/, WORKSPACES_*, regression_test_*, regression_num*.txt,
#   code/replay_files*, code/func_template_*.il, code/date_virtuosoVer.txt,
#   GenerateReplayScript/*.au and lcv.txt, cico_ws_* / func_ws_* (dry-run
#   workspaces), perf_metrics/, .gdp_ws_lock, .trash, __pycache__, editor swap files,
#   .deploy_info (written by deploy.sh).
#
# Besides content, the owner exec bit of every script (*.sh, *.pl, *.py)
# present on both sides is compared (diff -r ignores modes).
#
# Exit status: 0 = identical, 1 = differences found, 2 = usage / error.
#######################################

set -euo pipefail

[[ $# -eq 2 ]] || { echo "Usage: $(basename "$0") <deployed_dir> <prod_snapshot_dir>" >&2; exit 2; }
[[ -d "$1" && -d "$2" ]] || { echo "ERROR: both arguments must be directories" >&2; exit 2; }

EXCLUDES=(
    log CDS_log result 'WORKSPACES_*' 'regression_test_*' 'regression_num*.txt'
    'replay_files*' 'func_template_*.il' date_virtuosoVer.txt
    '*.au' lcv.txt
    'cico_ws_*' 'func_ws_*' perf_metrics .gdp_ws_lock .trash .deploy_info
    '*.swp' '*.swo' __pycache__ '*.pyc'
)

diff_args=()
for x in "${EXCLUDES[@]}"; do diff_args+=(-x "${x}"); done

rc=0
diff -r "${diff_args[@]}" "$1" "$2" || rc=$?
(( rc <= 1 )) || exit 2

# Exec-bit comparison on scripts present on both sides
find_args=()
for x in "${EXCLUDES[@]}"; do find_args+=(-name "${x}" -prune -o); done
while IFS= read -r rel; do
    [[ -f "$2/${rel}" ]] || continue
    a=0; b=0
    [[ -x "$1/${rel}" ]] && a=1
    [[ -x "$2/${rel}" ]] && b=1
    if (( a != b )); then
        echo "Exec bit differs: ${rel} ($1: $( ((a)) && echo x || echo -), $2: $( ((b)) && echo x || echo -))"
        rc=1
    fi
done < <(cd "$1" && find . -mindepth 1 "${find_args[@]}" -type f \( -name '*.sh' -o -name '*.pl' -o -name '*.py' \) -print | sed 's|^\./||' | sort)

exit "${rc}"
