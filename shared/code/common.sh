#!/bin/bash

set -euo pipefail

#######################################
# Logging
#######################################
_log_prefix() {
    local level="$1"
    local ts caller
    ts=$(date +%H:%M:%S)
    caller=$(basename "${BASH_SOURCE[2]:-unknown}")
    echo "[${level}][${ts}][${caller}]"
}

log() {
    echo "$(_log_prefix INFO) $*"
}

warn() {
    echo "$(_log_prefix WARN) $*" >&2
}

error_exit() {
    echo "$(_log_prefix ERROR) $*" >&2
    exit 1
}

#######################################
# GDP workspace mock (DRY_RUN=1)
# Creates minimal workspace structure:
#   cds.lib, cds.libicm, oa/<lib>/<cell>/, oa/<lib>/cdsinfo.tag
# Reads MOCK_GDP_LIBS (space-separated) and MOCK_GDP_CELL from env.
#######################################
_mock_vse_run() {
    local replay_file="$1"
    local ts="$2"
    local caller="$3"

    echo "[MOCK:1][${ts}][${caller}] vse_run: parsing mkdir from $(basename "${replay_file}")" >&2
    [[ -f "${replay_file}" ]] || { echo "[MOCK:1][${ts}][${caller}] replay not found: ${replay_file}" >&2; return; }

    python3 - "${replay_file}" <<'PYEOF'
import sys, re, os

replay_file = sys.argv[1]

with open(replay_file) as f:
    lines = f.readlines()

def strip_i(line):
    line = line.strip()
    if line.startswith(r'\i'):
        line = line[2:].lstrip()
    return line

skill_lines = [strip_i(l) for l in lines]

# Pass 1: literal string assignments  varname = "value"
sv = {}
for s in skill_lines:
    m = re.match(r'^([A-Za-z_]\w*)\s*=\s*"([^"]*)"$', s)
    if m:
        sv[m.group(1)] = m.group(2)

def eval_strcat(args_str):
    """Evaluate SKILL strcat() args — literal strings and variable refs only."""
    result, s, i = "", args_str.strip(), 0
    while i < len(s):
        if s[i] in ' \t':
            i += 1
        elif s[i] == '"':
            j = s.index('"', i + 1)
            result += s[i+1:j]
            i = j + 1
        else:
            m = re.match(r'([A-Za-z_]\w*)', s[i:])
            if m:
                result += sv.get(m.group(1), "")
                i += len(m.group(0))
            else:
                i += 1
    return result

# Pass 2: strcat assignments  varname = strcat(...)
for s in skill_lines:
    m = re.match(r'^([A-Za-z_]\w*)\s*=\s*strcat\s*\((.+)\)\s*$', s)
    if m:
        sv[m.group(1)] = eval_strcat(m.group(2))

# Pass 3: system(strcat("mkdir -p " ...)) → mkdir
for s in skill_lines:
    m = re.match(r'^system\s*\(\s*strcat\s*\((.+)\)\s*\)\s*$', s)
    if m:
        cmd = eval_strcat(m.group(1))
        if cmd.startswith("mkdir -p "):
            dirpath = cmd[len("mkdir -p "):].strip()
            sys.stderr.write(f"[MOCK:1] mkdir -p {dirpath}\n")
            sys.stderr.flush()
            os.makedirs(dirpath, exist_ok=True)
PYEOF
}

_mock_gdp_workspace() {
    local ws_dir="$1"
    local ts="$2"
    local caller="$3"

    echo "[MOCK:1][${ts}][${caller}] gdp workspace: ${ws_dir}" >&2
    mkdir -p "${ws_dir}"
    touch "${ws_dir}/cds.lib"
    touch "${ws_dir}/cds.libicm"

    if [[ -n "${MOCK_GDP_LIBS:-}" && -n "${MOCK_GDP_CELL:-}" ]]; then
        local lib
        for lib in ${MOCK_GDP_LIBS}; do
            mkdir -p "${ws_dir}/oa/${lib}/${MOCK_GDP_CELL}"
            printf "DMTYPE p4\n" > "${ws_dir}/oa/${lib}/cdsinfo.tag"
        done
    fi
}

#######################################
# Dry-run wrapper
# Level 0: run all (echo command before exec)
# Level 1: skip gdp / xlp4 / rm / vse_sub / vse_run
# Level 2: skip all
#######################################
run_cmd() {
    local cmd="$1"
    local first_word ts caller
    first_word=$(awk '{print $1}' <<< "${cmd}")
    ts=$(date +%H:%M:%S)
    caller=$(basename "${BASH_SOURCE[1]:-unknown}")

    case "${DRY_RUN:-0}" in
        2)
            echo "[DRY-RUN:2][${ts}][${caller}] ${cmd}" >&2
            ;;
        1)
            case "${first_word}" in
                gdp|xlp4|rm|vse_sub|vse_run)
                    if [[ "${cmd}" == *"gdp build workspace"* ]]; then
                        # --gdp-name names the workspace dir; --location (if given)
                        # is its parent, as for the real gdp build workspace
                        local gdp_name gdp_loc
                        gdp_name=$(grep -oP '(?<=--gdp-name\s)\S+' <<< "${cmd}" | tr -d "\"'" || true)
                        gdp_loc=$(grep -oP '(?<=--location\s)\S+' <<< "${cmd}" | tr -d "\"'" || true)
                        if [[ -n "${gdp_name}" ]]; then
                            _mock_gdp_workspace "${gdp_loc:+${gdp_loc}/}${gdp_name}" "${ts}" "${caller}"
                        else
                            echo "[SKIP:1][${ts}][${caller}] ${cmd}" >&2
                        fi
                    elif [[ "${cmd}" == *"gdp rebuild workspace"* ]]; then
                        _mock_gdp_workspace "." "${ts}" "${caller}"
                    elif [[ "${first_word}" == "vse_run" || "${first_word}" == "vse_sub" ]]; then
                        local _replay_file=""
                        [[ "${cmd}" =~ -replay[[:space:]]+([^[:space:]]+) ]] && _replay_file="${BASH_REMATCH[1]}"
                        if [[ -n "${_replay_file}" ]]; then
                            _mock_vse_run "${_replay_file}" "${ts}" "${caller}"
                        else
                            echo "[SKIP:1][${ts}][${caller}] ${cmd}" >&2
                        fi
                    else
                        echo "[SKIP:1][${ts}][${caller}] ${cmd}" >&2
                    fi
                    ;;
                *)
                    echo "[RUN][${ts}][${caller}] ${cmd}" >&2
                    eval "${cmd}"
                    ;;
            esac
            ;;
        *)
            echo "[RUN][${ts}][${caller}] ${cmd}" >&2
            eval "${cmd}"
            ;;
    esac
}

#######################################
# VSE execution wrapper
# VSE_MODE=run  → vse_run  (synchronous, env 1)
# VSE_MODE=sub  → vse_sub + poll bjobs (async submit, env 2)
#######################################
run_vse() {
    local replay="$1" logfile="$2"
    local seen_run=0
    if [[ "${VSE_MODE:-run}" == "sub" ]]; then
        local vse_out job_id stat
        vse_out=$(run_cmd "vse_sub -v ${VSE_VERSION} -env ${ICM_ENV} -replay ${replay} -log ${logfile}")
        job_id=$(awk -F'[<>]' '{print $2}' <<< "${vse_out}")
        log "Submitted job: ${job_id}. Polling every 10s..."
        # bwait -w "ended(${job_id})"  # disabled: pending verification
        while true; do
            #stat=$(bjobs -noheader -o stat "${job_id}" 2>/dev/null | awk '{print $1}')
            stat=$(mjobs -noheader -o stat "${job_id}" 2>/dev/null | tail -1)
	    if [ "${stat}" = "RUN" ] && [ "${seen_run}" -eq 0 ]; then
            	log "  job ${job_id} stat=${stat:-unknown}"
		seen_run=1
	    fi
            case "${stat}" in
                DONE) log "Job ${job_id} finished: DONE"; break ;;
                EXIT) log "Job ${job_id} finished: EXIT"; break ;;
            esac
            sleep 10
        done
    else
        # No -nograph: some replay functions need a GUI. DISPLAY is the
        # suite's Xvfb display exported by start_display
        run_cmd "vse_run -v ${VSE_VERSION} -replay ${replay} -log ${logfile}"
    fi
}

#######################################
# Virtual X display (Xvfb) for vse_run
# Each suite has its own display number (CICO_DISPLAY / PERF_DISPLAY /
# FUNC_DISPLAY). The suite calls start_display before its tests, which
# inherit the exported DISPLAY, and stop_display when it ends (also from its
# EXIT trap). Runs of the same suite at the same time share the display:
# each registers its pid in /tmp/.cat_xvfb_<n>.users, and the last one to
# leave stops the Xvfb, only if a CAT run started it (.pid).
#######################################
_xvfb_num=""   # display this process registered on (for stop_display)

# _xvfb_alive <n>: an X server answers on :<n> (socket and live lock owner).
# CAT_X11_SOCKET_DIR is for tools/mock/Xvfb only, where /tmp/.X11-unix may
# not be writable
_xvfb_alive() {
    local n="$1" lock_pid
    [[ -e "${CAT_X11_SOCKET_DIR:-/tmp/.X11-unix}/X${n}" && -r "/tmp/.X${n}-lock" ]] || return 1
    lock_pid=$(tr -dc '0-9' < "/tmp/.X${n}-lock")
    [[ -n "${lock_pid}" ]] && ps -p "${lock_pid}" > /dev/null 2>&1
}

# _xvfb_prune_users <users file> [<pid to drop>]: keep live pids only
_xvfb_prune_users() {
    local users="$1" drop="${2:-}" p kept=""
    [[ -f "${users}" ]] || return 0
    while read -r p; do
        [[ -n "${p}" && "${p}" != "${drop}" ]] || continue
        ps -p "${p}" > /dev/null 2>&1 && kept+="${p}"$'\n'
    done < "${users}"
    printf '%s' "${kept}" > "${users}"
}

start_display() {
    local n="$1" base i me="${BASHPID}"
    [[ "${n}" =~ ^[0-9]+$ ]] || error_exit "start_display: invalid display number: ${n}"
    if [[ "${VSE_MODE:-run}" == "sub" ]]; then
        log "VSE_MODE=sub: jobs run on other hosts; no local display started"
        return 0
    fi
    if [[ "${DRY_RUN:-0}" -ge 1 ]]; then
        log "[DRY-RUN:${DRY_RUN}] Would start Xvfb :${n} -screen 0 ${XVFB_SCREEN} and export DISPLAY=:${n}"
        return 0
    fi
    command -v Xvfb > /dev/null || error_exit "Xvfb not found (needed for vse_run on display :${n})"

    base="/tmp/.cat_xvfb_${n}"
    # Other users' runs of the suite share these files: create them writable
    ( umask 000; touch "${base}.lock" "${base}.users" ) 2>/dev/null || true
    (
        flock 9
        _xvfb_prune_users "${base}.users"
        if _xvfb_alive "${n}"; then
            if [[ -s "${base}.pid" ]] && ps -p "$(< "${base}.pid")" > /dev/null 2>&1; then
                log "Display :${n} already running (Xvfb pid $(< "${base}.pid")); sharing it"
            else
                rm -f "${base}.pid"
                warn "Display :${n} is held by an X server CAT did not start; using it, never stopping it"
            fi
        else
            log "Starting Xvfb :${n} -screen 0 ${XVFB_SCREEN}"
            # 9>&-: the server must not inherit the lock fd, or it would hold
            # the lock for its whole life
            nohup Xvfb ":${n}" -screen 0 "${XVFB_SCREEN}" > /dev/null 2>&1 9>&- &
            echo $! > "${base}.pid"
            for (( i = 0; i < 50; i++ )); do
                _xvfb_alive "${n}" && break
                ps -p "$(< "${base}.pid")" > /dev/null 2>&1 || break
                sleep 0.2
            done
            if ! _xvfb_alive "${n}"; then
                kill "$(< "${base}.pid")" 2>/dev/null || true
                rm -f "${base}.pid"
                echo "$(_log_prefix ERROR) Xvfb :${n} did not start" >&2
                exit 1
            fi
        fi
        echo "${me}" >> "${base}.users"
    ) 9> "${base}.lock" || error_exit "Could not start display :${n}"
    _xvfb_num="${n}"
    export DISPLAY=":${n}"
    log "DISPLAY=${DISPLAY}"
}

stop_display() {
    local n="${_xvfb_num}" base pid i me="${BASHPID}"
    [[ -n "${n}" ]] || return 0
    _xvfb_num=""
    base="/tmp/.cat_xvfb_${n}"
    (
        flock 9
        _xvfb_prune_users "${base}.users" "${me}"
        if [[ -s "${base}.users" ]]; then
            log "Display :${n} still used by $(wc -l < "${base}.users") other run(s); leaving it running"
        elif [[ -s "${base}.pid" ]]; then
            pid=$(< "${base}.pid")
            log "Stopping Xvfb :${n} (pid ${pid})"
            if kill "${pid}" 2>/dev/null; then
                # Wait (up to 5 s) so a run starting right after does not
                # find the dying server and share it
                for (( i = 0; i < 25; i++ )); do
                    ps -p "${pid}" > /dev/null 2>&1 || break
                    sleep 0.2
                done
            else
                warn "Could not stop Xvfb :${n} (pid ${pid})"
            fi
            rm -f "${base}.pid"
        fi
    ) 9> "${base}.lock" || warn "stop_display :${n} failed"
}

#######################################
# GDP project creation with retry
# Usage: create_gdp_project <proj_path>
# - Runs gdp create project; after each attempt sleeps 10s and
#   verifies the project exists via gdp list.
# - Retries up to GDP_PROJ_MAX_ATTEMPTS times (default 5).
# - At DRY_RUN>=1 delegates to run_cmd without retry.
#######################################
create_gdp_project() {
    local proj_path="$1"
    local cmd="gdp create project ${proj_path}"

    if [[ "${DRY_RUN:-0}" -ge 1 ]]; then
        run_cmd "${cmd}"
        return
    fi

    local max_attempts="${GDP_PROJ_MAX_ATTEMPTS:-5}"
    local attempt=0
    while [[ ${attempt} -lt ${max_attempts} ]]; do
        attempt=$(( attempt + 1 ))
        log "[PROJ] gdp create project attempt ${attempt}/${max_attempts}: ${proj_path}"
        local _ts; _ts=$(date +%H:%M:%S)
        echo "[RUN][${_ts}][create_gdp_project] ${cmd}" >&2
        eval "${cmd}" || true
        sleep 10
        if [[ -n "$(gdp list "${proj_path}" 2>/dev/null)" ]]; then
            log "[PROJ] Project confirmed: ${proj_path}"
            return 0
        fi
        log "[PROJ] Project not found after attempt ${attempt}, retrying..."
    done
    error_exit "gdp create project failed after ${max_attempts} attempts: ${proj_path}"
}

#######################################
# gdp_path_state <gdp_path>
# Prints: exists | gone | unknown
#   exists  - gdp lists the path
#   gone    - gdp lists the parent folder but not the path
#   unknown - gdp lists neither (gdp not answering): callers must not
#             treat this as "gone" (fail closed)
# gdp list may exit non-zero for a missing path, so the decision is
# made on output, never on the exit status alone.
#######################################
gdp_path_state() {
    local path="$1"
    if [[ -n "$(gdp list "${path}" 2>/dev/null)" ]]; then
        echo exists
    elif [[ -n "$(gdp list "$(dirname "${path}")" 2>/dev/null)" ]]; then
        echo gone
    else
        echo unknown
    fi
}

#######################################
# gdp_ws_state <workspace_name> <project_gdp_path>
# Prints: registered | gone | unknown
#   registered - gdp find still returns the workspace
#   gone       - gdp find returns nothing and gdp answers for the
#                project or its folder (gdp_path_state is not unknown)
#   unknown    - gdp answers for neither: do not treat as gone
#######################################
gdp_ws_state() {
    local name="$1" proj="$2"
    if [[ -n "$(gdp find --type=workspace ":=${name}" 2>/dev/null)" ]]; then
        echo registered
    elif [[ "$(gdp_path_state "${proj}")" != unknown ]]; then
        echo gone
    else
        echo unknown
    fi
}

#######################################
# Safe rm
#######################################
safe_rm_rf() {
    local target="$1"

    [[ -n "${target}" ]] || error_exit "Empty path"
    [[ "${target}" != "/" ]] || error_exit "Refuse to delete /"
    [[ "${target}" != "/home" ]] || error_exit "Refuse to delete /home"

    run_cmd "rm -rf \"${target}\""
}

#######################################
# Utility
#######################################
format_num() {
    printf "%03d" "$1"
}

format_num_width() {
    printf "%0${2}d" "$1"
}

#######################################
# Move a directory to .trash/ for
# deferred deletion.
# Only call after verifying .gdpxl is
# gone (successful GDP workspace delete).
#######################################
safe_mv_to_trash() {
    local target="$1"
    [[ -n "${target}" ]]     || error_exit "safe_mv_to_trash: empty path"
    [[ "${target}" != "/" ]] || error_exit "safe_mv_to_trash: refuse to trash /"
    if [[ ! -e "${target}" ]]; then
        log "safe_mv_to_trash: ${target} not found, skipping"
        return
    fi
    local trash_dir="${script_dir}/.trash"
    mkdir -p "${trash_dir}"
    local dest="${trash_dir}/$(basename "${target}")_$(date +%s)"
    run_cmd "mv \"${target}\" \"${dest}\""
}

#######################################
# Delete the .trash/ staging area.
# Call at the end of each main script.
#######################################
flush_trash() {
    local trash_dir="${script_dir}/.trash"
    [[ -d "${trash_dir}" ]] || return
    log "Flushing trash: ${trash_dir}"
    # Bypass run_cmd: trash cleanup is a local op, not an ICM/GDP command;
    # rm is in the DRY_RUN=1 skip list but .trash/ must always be deleted.
    rm -rf "${trash_dir}"
}

#######################################
# Detect GDP/GDM tool versions from env.
# Sets globals: gdpver  gdmver
# Sources: ICM_SkillRoot, CDS_GDM_SHLIB_LOCATION
#######################################
get_tool_versions() {
    gdpver=""
    gdmver=""
    if [[ -n "${ICM_SkillRoot:-}" ]]; then
        gdpver=$(basename "${ICM_SkillRoot}")
    fi
    if [[ -n "${CDS_GDM_SHLIB_LOCATION:-}" ]]; then
        local _so="${CDS_GDM_SHLIB_LOCATION}/libgdmp4_sh.so"
        if [[ -f "${_so}" ]]; then
            local _change
            _change=$(strings "${_so}" 2>/dev/null \
                | grep '\$Change:' | grep -oP '\d{5,}' | head -1 || true)
            [[ -n "${_change}" ]] && gdmver="gdmp4.${_change}"
        fi
    fi
    log "Tool versions — gdpver=${gdpver:-n/a}  gdmver=${gdmver:-n/a}"
}
