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
# File modes follow the exec bit of the working-tree file (755 / 644).
# Uncommitted changes under the suite, shared/ or site/ are deployed too,
# with a warning; .deploy_info records the commit and whether it was dirty.
#
# Site file rules (checked before anything is written):
#   - every line is blank, a # comment, or KEY=value (no CR, no "export")
#   - no key twice
#   - every key exists as a KEY= line in shared/code/env.sh
#   - it defines the same key set as site/dev.env (the reference site),
#     so a site can never silently inherit a dev value
#
# The deployment is assembled in a temp dir next to <dest> and moved into
# place only when complete; on any error nothing is left at <dest>.
#
# -f (update in place): <dest> may already hold a deployment of the same
# suite. Only deployed files are written; runtime outputs (WORKSPACES_*,
# log/, result/, regression_test_*, perf_metrics/, ...) are left alone, so
# live GDP workspaces keep their local directories. A deployed file whose
# content changes is first copied to .deploy_backup/<time>/. Files listed
# in the previous .deploy_files that are no longer deployed are moved there
# too. Files are replaced one by one (not atomically as a whole), so do not
# update while a suite is running from <dest>.
#######################################

set -euo pipefail

repo_dir="$(cd "$(dirname "$0")" && pwd)"

declare -A DEPLOY_NAME=( [cico]=1_cico_mp [perf]=2_perf_mp [func]=3_func_mp )
ref_site_file="${repo_dir}/site/dev.env"
env_src="${repo_dir}/shared/code/env.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") [-f] <suite> <site> [dest]

  suite   cico | perf | func
  site    name of a file in site/ without .env  ($(cd "${repo_dir}/site" && ls *.env | sed 's/\.env$//' | xargs))
  dest    target directory (default: build/<site>/<deployment name>)
          must not exist or must be empty, unless -f is given
  -f      update an existing deployment of the same suite in place:
          overwrite deployed files (changed ones are backed up to
          <dest>/.deploy_backup/<time>/), keep runtime outputs

Examples:
  $(basename "$0") perf prod                     # → build/prod/2_perf_mp
  $(basename "$0") func dev /tmp/3_func_mp
  $(basename "$0") -f perf prod /path/to/2_perf_mp   # redeploy over an existing one
EOF
}

die() { echo "ERROR: $*" >&2; exit 1; }

force=0
args=()
for a in "$@"; do
    case "${a}" in
        -h|--help)   usage; exit 0 ;;
        -f|--force)  force=1 ;;
        -*)          echo "ERROR: Unknown option: ${a}" >&2; usage >&2; exit 1 ;;
        *)           args+=("${a}") ;;
    esac
done
[[ ${#args[@]} -ge 2 && ${#args[@]} -le 3 ]] || { usage >&2; exit 1; }

suite="${args[0]}"
site="${args[1]}"
[[ -n "${DEPLOY_NAME[${suite}]:-}" ]] || die "Unknown suite: ${suite} (valid: ${!DEPLOY_NAME[*]})"
site_file="${repo_dir}/site/${site}.env"
[[ -f "${site_file}" ]] || die "Site file not found: site/${site}.env"
[[ -f "${env_src}" ]]   || die "Missing ${env_src}"
dest="${args[2]:-${repo_dir}/build/${site}/${DEPLOY_NAME[${suite}]}}"

update=0
if [[ -e "${dest}" ]]; then
    [[ -d "${dest}" ]] || die "Destination exists and is not a directory: ${dest}"
    if [[ -n "$(ls -A "${dest}")" ]]; then
        (( force )) || die "Destination is not empty: ${dest} (remove it first, or -f to update it in place)"
        # Guard against overwriting another suite's deployment by mistake
        if [[ -f "${dest}/.deploy_info" ]]; then
            old_suite=$(sed -n 's/^suite=//p' "${dest}/.deploy_info")
            [[ "${old_suite}" == "${suite}" ]] \
                || die "Destination holds a ${old_suite:-unknown} deployment, not ${suite}: ${dest}"
        else
            echo "WARNING: ${dest} has no .deploy_info (not made by deploy.sh); updating it anyway" >&2
        fi
        update=1
    fi
fi

#######################################
# Validate the site file
#######################################
# site_keys <file> <label>: print the keys of a site file, fail on malformed lines
site_keys() {
    awk -v F="$2" '
        /\r/                              { printf "ERROR: %s:%d: CR character (use LF line endings)\n", F, NR > "/dev/stderr"; bad = 1; next }
        /^[[:space:]]*$/ || /^[[:space:]]*#/ { next }
        /^[A-Z_][A-Z0-9_]*=/ {
            key = $0; sub(/=.*/, "", key)
            if (key in seen) { printf "ERROR: %s:%d: duplicate key %s\n", F, NR, key > "/dev/stderr"; bad = 1 }
            seen[key] = 1; print key; next
        }
        { printf "ERROR: %s:%d: malformed line (expected KEY=value, # comment or blank): %s\n", F, NR, $0 > "/dev/stderr"; bad = 1 }
        END { exit bad }
    ' "$1"
}

site_key_list=$(site_keys "${site_file}" "site/${site}.env") || die "Invalid site file: site/${site}.env"
[[ -n "${site_key_list}" ]] || die "Site file defines no keys: site/${site}.env"
ref_key_list=$(site_keys "${ref_site_file}" "site/dev.env") || die "Invalid reference site file: site/dev.env"
env_key_list=$(grep -oE '^[A-Z_][A-Z0-9_]*=' "${env_src}" | tr -d '=' | sort -u)

errors=0
for key in ${site_key_list}; do
    grep -qx "${key}" <<< "${env_key_list}" \
        || { echo "ERROR: ${key} from site/${site}.env has no ${key}= line in shared/code/env.sh" >&2; errors=1; }
done
for key in ${ref_key_list}; do
    grep -qx "${key}" <<< "${site_key_list}" \
        || { echo "ERROR: site/${site}.env does not define ${key} (every site must set the keys of site/dev.env)" >&2; errors=1; }
done
for key in ${site_key_list}; do
    grep -qx "${key}" <<< "${ref_key_list}" \
        || { echo "ERROR: ${key} in site/${site}.env is not in site/dev.env (add it there too)" >&2; errors=1; }
done
(( errors == 0 )) || die "Site file check failed: site/${site}.env"

#######################################
# Assemble in a temp dir next to dest
#######################################
src="suites/${suite}"
mapfile -t files < <(git -C "${repo_dir}" ls-files -- "${src}")
[[ ${#files[@]} -gt 0 ]] || die "No tracked files under ${src}"

# Uncommitted changes are deployed as they are (useful for comparing a
# deployment with a prod snapshot before committing), but never silently.
mapfile -t dirty < <(git -C "${repo_dir}" status --porcelain -- "${src}" shared site)
if (( ${#dirty[@]} > 0 )); then
    echo "WARNING: ${#dirty[@]} uncommitted change(s) under ${src}, shared/ or site/ are included in this deployment:" >&2
    printf '  %s\n' "${dirty[@]}" >&2
fi

dest_parent="$(dirname "${dest}")"
mkdir -p "${dest_parent}"
tmp_dest="$(mktemp -d "${dest_parent}/.$(basename "${dest}").deploy.XXXXXX")"
trap 'rm -rf "${tmp_dest}"' EXIT
chmod "$(printf '%o' $(( 0777 & ~$(umask) )))" "${tmp_dest}"   # mktemp -d makes it 700

for f in "${files[@]}"; do
    rel="${f#${src}/}"
    [[ -e "${repo_dir}/${f}" ]] || die "Missing or broken link: ${f}"
    mkdir -p "${tmp_dest}/$(dirname "${rel}")"
    cp -pL "${repo_dir}/${f}" "${tmp_dest}/${rel}"
    if [[ -x "${repo_dir}/${f}" ]]; then
        chmod 755 "${tmp_dest}/${rel}"
    else
        chmod 644 "${tmp_dest}/${rel}"
    fi
done

#######################################
# Render code/env.sh with the site values
#######################################
env_out="${tmp_dest}/code/env.sh"
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
' "${env_src}" > "${env_out}.tmp" || die "Rendering code/env.sh failed"
chmod --reference="${env_out}" "${env_out}.tmp"
mv "${env_out}.tmp" "${env_out}"
bash -n "${env_out}" || die "Rendered code/env.sh has a syntax error"

#######################################
# Record where the deployment came from
#######################################
{
    echo "commit=$(git -C "${repo_dir}" rev-parse HEAD 2>/dev/null || echo unknown)"
    echo "dirty=$( (( ${#dirty[@]} > 0 )) && echo "yes (${#dirty[@]} files)" || echo no)"
    echo "suite=${suite}"
    echo "site=${site}"
    echo "deployed_at=$(date '+%Y-%m-%d %H:%M:%S')"
    echo "deployed_by=${USER:-$(id -un)}"
} > "${tmp_dest}/.deploy_info"
chmod 644 "${tmp_dest}/.deploy_info"

# The deployed file list: -f uses the previous one to remove files that
# are no longer deployed
rels=()
for f in "${files[@]}"; do rels+=("${f#${src}/}"); done
printf '%s\n' "${rels[@]}" > "${tmp_dest}/.deploy_files"
chmod 644 "${tmp_dest}/.deploy_files"

#######################################
# Move into place
#######################################
if (( ! update )); then
    [[ -d "${dest}" ]] && rmdir "${dest}"
    mv "${tmp_dest}" "${dest}"
    trap - EXIT
    echo "Deployed ${suite} (site=${site}) → ${dest}  (${#files[@]} files)"
    exit 0
fi

# -f: update in place. Check every target first so a conflict stops the
# update before anything is written.
for rel in "${rels[@]}"; do
    t="${dest}/${rel}"
    [[ ! -d "${t}" || -L "${t}" ]] || die "Cannot update: ${t} is a directory in the destination"
done

backup_dir="${dest}/.deploy_backup/$(date '+%Y%m%d_%H%M%S')"
[[ ! -e "${backup_dir}" ]] || backup_dir="${backup_dir}_$$"   # two updates in one second
backup() {   # backup <rel>: copy dest/<rel> into backup_dir, keeping its path
    mkdir -p "${backup_dir}/$(dirname "$1")"
    cp -pP "${dest}/$1" "${backup_dir}/$1"
}

n_new=0 n_changed=0 n_same=0 n_removed=0
for rel in "${rels[@]}"; do
    t="${dest}/${rel}"
    if [[ -e "${t}" || -L "${t}" ]]; then
        if [[ ! -L "${t}" ]] && cmp -s "${tmp_dest}/${rel}" "${t}"; then
            # Same content: only bring the mode in line
            chmod --reference="${tmp_dest}/${rel}" "${t}"
            n_same=$(( n_same + 1 ))
            continue
        fi
        backup "${rel}"
        n_changed=$(( n_changed + 1 ))
    else
        n_new=$(( n_new + 1 ))
    fi
    mkdir -p "$(dirname "${t}")"
    # Copy beside the target and rename over it, so a file is never half-written
    cp -p "${tmp_dest}/${rel}" "${t}.deploy_tmp"
    mv -f "${t}.deploy_tmp" "${t}"
done

# Files the previous deployment shipped that this one no longer does
if [[ -f "${dest}/.deploy_files" ]]; then
    declare -A now=()
    for rel in "${rels[@]}"; do now["${rel}"]=1; done
    while IFS= read -r rel; do
        [[ -n "${rel}" && -z "${now[${rel}]:-}" ]] || continue
        [[ -e "${dest}/${rel}" || -L "${dest}/${rel}" ]] || continue
        backup "${rel}"
        rm -f "${dest}/${rel}"
        n_removed=$(( n_removed + 1 ))
    done < "${dest}/.deploy_files"
else
    echo "WARNING: no previous .deploy_files in ${dest}: files that are no longer deployed (if any) were not removed" >&2
fi

cp -p "${tmp_dest}/.deploy_info" "${tmp_dest}/.deploy_files" "${dest}/"

echo "Updated ${suite} (site=${site}) in ${dest}: ${n_changed} changed, ${n_new} new, ${n_same} unchanged, ${n_removed} removed"
(( n_changed + n_removed == 0 )) || echo "Previous versions of changed/removed files: ${backup_dir}"
exit 0
