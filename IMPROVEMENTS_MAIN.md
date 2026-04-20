# CAT — Regression Test Framework Improvements
## `legacy/1_cico/main.sh` → `main.sh`

> Korean version: [IMPROVEMENTS_MAIN_KR.md](IMPROVEMENTS_MAIN_KR.md)
> Combined overview: [IMPROVEMENTS.md](IMPROVEMENTS.md)

---

## Overview

| Area | Legacy (`1_cico/main.sh`) | Current (`main.sh`) |
|---|---|---|
| Code quality | Unformatted, no indentation | Structured, readable Bash |
| Error handling | `set -e` only | `set -euo pipefail` + trap + `error_exit` |
| Shared environment | Each script re-declares variables | `code/env.sh` + `code/common.sh` sourced once |
| Path resolution | Relative paths (`../../code/`) | `${script_dir}/code/` — works from any directory |
| Test execution | Sequential `for` loop | `xargs -P` parallel workers |
| VSE invocation | `virtuoso` (direct binary call) | `run_vse()` wrapper — `vse_run` / `vse_sub` switchable |
| Teardown timing | Inline, end of each test loop | Background worker — runs concurrently with tests |
| Dry-run | None — every run hits real infra | 3-level `DRY_RUN` system |
| Logging | `echo` to stdout only | `tee` to timestamped `log/main.log.*` file |
| Replay file handling | `cp` into test dir (source remains) | `mv` into test dir (source consumed) |
| Regression dir naming | Timestamp-based `regression_test_<user>_<date>` | Counter-based `regression_test_001`, `002`, … |
| Cleanup | `rm -rf` at the end (unless debugMode) | Separate `teardown.sh` + `teardown_all.sh` |
| Test order | Sorted numerically (`sort -n`) | Preserved as user specified |

---

## 1. Entry Point & Shared Infrastructure

### Legacy — Everything Inline

```bash
# legacy/1_cico/main.sh (unformatted, as written)
#!/bin/bash show_help() { ... } set -e
dateno=$(date +%Y%m%d_%H%M%S)
user_name=$(echo $USER)
max=256 cases="" ws_name=cadence_cico_ws_"$user_name"_"$dateno"
proj_name=cadence_cico_"$user_name"_"$dateno"
regression_test_name=regression_test_"$user_name"_"$dateno"
libname=ESD01 cellname=FULLCHIP
```

Every variable is defined inline in the script. No shared environment.
Changing a default means editing the script directly.

### Current — Centralised Config + Shared Utilities

```bash
# main.sh
#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
export script_dir

source "${script_dir}/code/env.sh"    # all variables: paths, defaults, DRY_RUN, VSE_MODE
source "${script_dir}/code/common.sh" # run_cmd(), run_vse(), log(), error_exit()
```

All defaults live in `code/env.sh`. All shared functions in `code/common.sh`.
Child scripts inherit `script_dir` and source the same files — one source of truth.

---

## 2. Error Handling

### Legacy

```bash
set -e           # exits on error, but no guarantee on unset vars or pipe failures
# No trap — signals like CTRL+C leave workspaces dangling
# No explicit error messages: scripts just exit silently
```

### Current

```bash
set -euo pipefail
# -e  : exit on error
# -u  : exit on unset variable reference
# -o pipefail : pipe fails if any command in the pipe fails

# Trap: ensures teardown worker is always waited on
_cleanup() {
    if [[ -n "${main_done_flag}" && ! -f "${main_done_flag}" ]]; then
        touch "${main_done_flag}" 2>/dev/null || true
    fi
    if [[ -n "${teardown_worker_pid}" ]]; then
        wait "${teardown_worker_pid}" 2>/dev/null || true
    fi
}
trap '_cleanup' EXIT INT TERM

# Explicit messages from common.sh
error_exit() { log "ERROR: $*"; exit 1; }
```

---

## 3. Path Resolution

### Legacy

```bash
# All paths relative to wherever the script is called from
../../code/init.sh -ws $ws_name -proj $proj_name $libname
cp ../../code/cdsLibMgr.il $ws_name/
cp ../../code/.cdsenv $ws_name/
rm -rf code/$replays_folder
python3 code/generate_templates.py ...
```

These paths assume the caller is always in a specific subdirectory.
If the script is called from the project root they break immediately.

### Current

```bash
# All paths anchored to script_dir, set once at startup
run_cmd "rm -rf \"${script_dir}/code/${replays_folder}\""
run_cmd "python3 \"${script_dir}/code/generate_templates.py\" ..."
run_cmd "mv -f \"${script_dir}/code/${replays_folder}/replay_${num}.il\" \"${testdir}/\""
```

Works correctly from any working directory.

---

## 4. Test Execution — Sequential vs Parallel

### Legacy — Sequential for Loop

```bash
# legacy/1_cico/main.sh
for i in $tests; do
    three_digit_num=$(printf "%03d" $i)
    testdir=$(pwd)/"$regression_test_name"/test_$three_digit_num

    echo "Running test $three_digit_num in $testdir"
    (
        cd $testdir || exit 1
        ../../code/init.sh -ws $ws_name -proj $proj_name $libname || true
        cp ../../code/cdsLibMgr.il $ws_name/
        virtuoso -replay ../replay_$three_digit_num.il -log ../../../CDS_log/$uniqueid/CDS_$three_digit_num".log" || true
        ../../code/teardown.sh -ws $ws_name -proj $proj_name
    )
done
```

One test at a time. Total wall time = sum of all test times.

### Current — xargs Parallel Workers

```bash
# main.sh
printf "%s\n" "${tests[@]}" | \
    xargs -n1 -P"${jobs}" bash "${script_dir}/code/run_single_test.sh"
```

```
Time ──────────────────────────────────────────────────────────►
  (legacy)
    test_001 ────────────────────────────────────────────────────►
                                                   test_002 ─────►

  (current, -j 4)
    test_001 ██████████████████████████
    test_002 ██████████████████████████
    test_003 ██████████████████████████
    test_004 ██████████████████████████
    test_005               ████████████  ← starts when a slot frees

  10 tests × 5 min / 4 workers ≈ 15 min  (vs 50 min sequential)
```

`run_single_test.sh` receives the test number and reads `libname`, `regression_dir`,
`uniqueid` from exported env vars — clean separation from the orchestrator.

---

## 5. VSE Invocation

### Legacy — Direct Binary Call

```bash
# legacy/1_cico/main.sh (inside test loop)
virtuoso \
    -replay ../replay_$three_digit_num.il \
    -log ../../../CDS_log/$uniqueid/CDS_$three_digit_num".log" || true
```

- Hardcoded to `virtuoso` binary — cannot switch to `vse_run` or `vse_sub`
- `|| true` suppresses errors silently
- No version specification
- No ICM environment setup

### Current — run_vse() Wrapper

```bash
# code/run_single_test.sh
run_vse "./${testtype}_${lib}.au" "${script_dir}/CDS_log/${uniqueid}/..."
```

```bash
# code/common.sh — run_vse()
run_vse() {
    local replay_file="$1" log_file="$2"
    if [[ "${VSE_MODE}" == "sub" ]]; then
        vse_out=$(vse_sub -v "${VSE_VERSION}" -env "${ICM_ENV}" \
                          -replay "${replay_file}" -log "${log_file}")
        job_id=$(...)
        # poll bjobs every 10s: DONE → success, EXIT → failure
        while true; do
            stat=$(bjobs -noheader -o stat "${job_id}")
            [[ "${stat}" == "DONE" ]] && break
            [[ "${stat}" == "EXIT" ]] && error_exit "VSE job failed"
            sleep 10
        done
    else
        run_cmd "vse_run -v \"${VSE_VERSION}\" -env \"${ICM_ENV}\" \
                         -replay \"${replay_file}\" -log \"${log_file}\""
    fi
}
```

Switch at runtime without editing any script:
```bash
VSE_MODE=sub ./main.sh -m 10     # batch submit + bjobs polling
VSE_MODE=run ./main.sh -m 10     # synchronous vse_run
```

---

## 6. Teardown Strategy

### Legacy — Inline, Blocking

```bash
# Inside the test loop
(
    cd $testdir || exit 1
    ...
    ../../code/teardown.sh -ws $ws_name -proj $proj_name
)
# test_001 teardown must complete before test_002 can start
```

Teardown blocked test start. Also: if the script was interrupted mid-loop,
all remaining workspaces were leaked. Cleanup was `rm -rf` at the very end —
no GDP/p4 cleanup unless teardown.sh ran for each test.

### Current — Background Queue Worker

```
main.sh (foreground)              teardown_worker.sh (background)
─────────────────────             ──────────────────────────────
test_001 completes                poll teardown_queue.txt (2s)
  → enqueue uniquetestid_001  ──► dequeue → teardown.sh
test_002 completes
  → enqueue uniquetestid_002  ──► dequeue → teardown.sh
...
touch main_done.flag          ──► sees flag + empty queue → exit
```

Teardown overlaps with test execution.
Even if main.sh is killed, `_cleanup()` trap sets the done flag so the worker exits cleanly.

---

## 7. Regression Directory Management

### Legacy

```bash
# Single timestamp-based name — changes every run
regression_test_name=regression_test_"$user_name"_"$dateno"

# Deleted at end (unless debug)
rm -rf $regression_test_name || true
```

No history of previous runs. Every run creates a new uniquely named dir and
destroys it at the end. With `-debug`, the dir is kept but its name is
unpredictable.

### Current

```bash
# Counter-based: regression_test_001, 002, ...
create_regression_dir() {
    num=$(<"${script_dir}/regression_num.txt")   # read last counter
    while true; do
        num=$(printf "%03d" $(( (10#${num} + 1) % 1000 )))
        dir="${script_dir}/regression_test_${num}"
        [[ ! -d "${dir}" ]] && break             # find next available
    done
    echo "${num}" > "${script_dir}/regression_num.txt"
    regression_dir="${dir}"
}
```

Predictable, sequential names. Old regression dirs remain available for
inspection until explicitly torn down via `teardown_all.sh`.

---

## 8. DRY_RUN System

### Legacy — None

Every run executes real GDP / p4 / VSE calls. Testing the script logic itself
required a fully configured environment.

### Current — 3 Levels

```
Level 2 : Print only  — log "[DRY-RUN:2] Would: <cmd>"
Level 1 : Mock mode   — skip gdp/xlp4/rm/vse; create local workspace dirs
Level 0 : Production  — all commands execute
```

```bash
# Preview what main.sh will do without touching anything
./main.sh -d 2

# Full smoke test with local mock workspaces
./main.sh -m 5 -d 1
```

---

## 9. Logging

### Legacy

```bash
echo "Running test $three_digit_num in $testdir"
echo "All selected tests finished."
# No timestamps, no log file, no central log
```

### Current

```bash
# main.sh — redirects all stdout/stderr to a timestamped log file
mkdir -p "${script_dir}/log"
logfile="${script_dir}/log/main.log.$(date +%Y%m%d_%H%M%S).txt"
exec > >(tee "${logfile}") 2>&1

# common.sh — all messages via log()
log() { echo "[$(date +%H:%M:%S)] $*"; }
```

Terminal and log file receive the same output simultaneously. Log files
accumulate in `log/` — useful for comparing runs.

---

## 10. Detailed Usage Comparison

### Legacy Options

```
./main.sh [OPTIONS]
  -m, --max N          Maximum case number          (default: 256)
  -c, --cases LIST     Comma-separated or range
  -ws, --ws_name NAME  Workspace name               (default: cadence_cico_ws_<user>_<date>)
  -proj, --proj_name   Project name                 (default: cadence_cico_<user>_<date>)
  -lib, --libname      Library name                 (default: ESD01)
  -cell, --cellname    Cell name
  -debug               Keep regression_test_* and replay folders
  -h, --help
```

### Current Options

```
./main.sh [options]
  -h  | --help                Print help
  -ws | --ws_name  <name>     Workspace prefix        (default: $WS_PREFIX from env.sh)
  -proj| --proj_prefix <p>    Project prefix          (default: $PROJ_PREFIX from env.sh)
  -cell| --cell    <name>     Cell name               (default: $CELLNAME from env.sh)
  -m  | --max      <n>        Run tests 1~N           (default: $MAX_CASES from env.sh)
  -c  | --cases    <list>     Specific tests: 1,3,5-9
  -j  | --jobs     <n>        Parallel workers        (default: 4)
  -d  | --dry-run  [0|1|2]    Dry-run level           (default: $DRY_RUN from env.sh)
  -t  | --teardown            Background teardown after tests
```

Key differences:
- `-j` / `--jobs`: new — parallelism control
- `-d` / `--dry-run`: new — 3-level dry-run
- `-t` / `--teardown`: replaces inline teardown (can opt-out)
- `-debug`: removed — teardown is now explicit via `-t` and `teardown_all.sh`
- `-lib`: removed — libname set once in `env.sh`, not per-run arg

---

## 11. Key File Changes

| File | Legacy | Current |
|---|---|---|
| `main.sh` | 148 lines, unformatted, all-in-one | Structured, modular, delegates to child scripts |
| `code/env.sh` | Not present — variables inline in main.sh | Central config: all paths, defaults, `DRY_RUN`, `VSE_MODE` |
| `code/common.sh` | Not present | `run_cmd()`, `run_vse()`, `log()`, `error_exit()`, `_mock_gdp_workspace()` |
| `code/init.sh` | Hardcoded paths, no DRY_RUN, no script_dir | `script_dir`-anchored, DRY_RUN-aware, `error_exit` |
| `code/run_single_test.sh` | Not present — test loop inline in main.sh | Dedicated per-test script: init + run_vse + enqueue teardown |
| `code/teardown_worker.sh` | Not present — teardown inline in test loop | Background queue worker |
| `code/teardown_all.sh` | `code/ICM_deleteProj.sh` (manual) | Iterates regression dir, calls `teardown.sh` per test |
| `code/summary.sh` | Called at end: `code/summary.sh $uniqueid` | Called with DRY_RUN: `bash summary.sh -d ${DRY_RUN} ${uniqueid}` |
