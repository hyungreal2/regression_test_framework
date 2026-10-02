#!/bin/bash
#######################################
# Assemble one suite in its prod deployment layout.
#
#   suites/<suite>/   (shared/ symlinks dereferenced)
# + site/<site>.env   (KEY= lines replace the same keys in code/env.sh)
# → <dest>/           e.g. build/prod/2_perf_mp
#
# Only git-tracked files are copied, so runtime outputs (log/, CDS_log/,
# WORKSPACES_*, generated replays, ...) never end up in a deployment.
#######################################

set -euo pipefail

repo_dir="$(cd "$(dirname "$0")" && pwd)"

declare -A DEPLOY_NAME=( [cico]=1_cico_mp [perf]=2_perf_mp [func]=3_func_mp )

usage() {
    cat <<EOF
Usage: $(basename "$0") <suite> <site> [dest]

  suite   cico | perf | func
  site    name of a file in site/ without .env  ($(cd "${repo_dir}/site" && ls *.env | sed 's/\.env$//' | xargs))
  dest    target directory (default: build/<site>/<deployment name>)
          must not exist or must be empty

Examples:
  $(basename "$0") perf prod                     # → build/prod/2_perf_mp
  $(basename "$0") func dev /tmp/3_func_mp
EOF
}

die() { echo "ERROR: $*" >&2; exit 1; }

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { usage; exit 0; }
[[ $# -ge 2 && $# -le 3 ]] || { usage >&2; exit 1; }

suite="$1"
site="$2"
[[ -n "${DEPLOY_NAME[${suite}]:-}" ]] || die "Unknown suite: ${suite} (valid: ${!DEPLOY_NAME[*]})"
site_file="${repo_dir}/site/${site}.env"
[[ -f "${site_file}" ]] || die "Site file not found: site/${site}.env"
dest="${3:-${repo_dir}/build/${site}/${DEPLOY_NAME[${suite}]}}"

if [[ -e "${dest}" ]]; then
    [[ -d "${dest}" ]] || die "Destination exists and is not a directory: ${dest}"
    [[ -z "$(ls -A "${dest}")" ]] || die "Destination is not empty: ${dest} (remove it first)"
fi

#######################################
# Copy tracked suite files, dereferencing shared/ symlinks
#######################################
src="suites/${suite}"
mapfile -t files < <(git -C "${repo_dir}" ls-files -- "${src}")
[[ ${#files[@]} -gt 0 ]] || die "No tracked files under ${src}"

mkdir -p "${dest}"
for f in "${files[@]}"; do
    rel="${f#${src}/}"
    [[ -e "${repo_dir}/${f}" ]] || die "Missing or broken link: ${f}"
    mkdir -p "${dest}/$(dirname "${rel}")"
    cp -pL "${repo_dir}/${f}" "${dest}/${rel}"
done

#######################################
# Render code/env.sh with the site values
#######################################
env_out="${dest}/code/env.sh"
[[ -f "${env_out}" ]] || die "Suite has no code/env.sh: ${suite}"

awk -v SITE="${site_file}" '
    BEGIN {
        while ((getline line < SITE) > 0) {
            if (line ~ /^[A-Z_][A-Z0-9_]*=/) { key = line; sub(/=.*/, "", key); val[key] = line }
        }
    }
    {
        key = $0
        if (key ~ /^[A-Z_][A-Z0-9_]*=/) {
            sub(/=.*/, "", key)
            if (key in val) { print val[key]; used[key] = 1; next }
        }
        print
    }
    END {
        for (key in val) if (!(key in used)) { print "ERROR: " key " from site file not found in env.sh" > "/dev/stderr"; bad = 1 }
        exit bad
    }
' "${repo_dir}/shared/code/env.sh" > "${env_out}.tmp"
mv "${env_out}.tmp" "${env_out}"

echo "Deployed ${suite} (site=${site}) → ${dest}  (${#files[@]} files)"
