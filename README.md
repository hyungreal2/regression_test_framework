# CAT - Cadence Automation Test Framework

Regression and performance test automation framework for Virtuoso replay-based testing.
Supports parallel test execution, GDP workspace lifecycle management, and dry-run simulation.

---

## Directory Structure

The repo mirrors the three prod deployments (`1_cico_mp`, `2_perf_mp`, `3_func_mp`).
Each `suites/<suite>/` directory has the same layout as its deployment and runs in place.
Files that more than one suite actually uses live once in `shared/` and are symlinked into those suites.
Files a suite ships in prod but never uses are kept in `archive/` and are not deployed.

```
CAT/
├── shared/
│   ├── clean.sh                   # Remove generated outputs (symlinked as suites/*/clean.sh)
│   └── code/
│       ├── env.sh                 # Environment config; site values default to site/dev.env
│       ├── common.sh              # log, run_cmd, run_vse (vse_run -nograph), mocks
│       ├── generate_templates.py  # Build replay_NNN.il from control + list + template (cico, func)
│       ├── teardown_worker.sh                                                             (cico, func)
│       ├── mgHierParse.il · virtuosoVer.il                                                 (cico, func)
│       └── .cdsenv                # Virtuoso env shared by cico and func
├── suites/
│   ├── cico/                      # = 1_cico_mp
│   │   ├── main.sh                # Regression test entry point
│   │   └── code/                  # run_single_test.sh, init.sh, summary.sh, teardown.sh, teardown_all.sh, validate.il,
│   │                              # control, list, template.il, Flat_list, Hierarchical_List (+ shared links)
│   ├── perf/                      # = 2_perf_mp
│   │   ├── perf_main.sh           # Performance test entry point
│   │   ├── GenerateReplayScript/  # createReplay.pl + replay templates (*.au outputs are ignored)
│   │   └── code/                  # perf_*.sh, perfFunctions.il, perf .cdsenv / functions.il, revert SKILL (+ shared links)
│   └── func/                      # = 3_func_mp
│       ├── func_main.sh           # Functional test entry point
│       └── code/                  # func_*.sh, func_control, func_template.il, validate.il, list_<mode>*, functions.il (+ shared links)
├── site/
│   ├── dev.env                    # Site values for local development (same as shared/code/env.sh)
│   └── prod.env                   # Site values of the prod deployments
├── deploy.sh                      # Assemble a suite for a site in its prod layout
├── archive/                       # Unused prod files kept for reference (not deployed)
├── tools/
│   ├── compare_deploy.sh          # Diff a deployment against a prod snapshot
│   └── mock/                      # Mock gdp (object registry) / xlp4 for local runs (not deployed)
├── docs/                          # Manuals, improvement notes, analysis
└── reference/                     # Local prod / legacy snapshots (git-ignored)
```

Run a suite from its own directory, for example `cd suites/perf && ./perf_main.sh -h`.
Runtime outputs (`log/`, `CDS_log/`, `WORKSPACES_*`, `result/`, ...) are created inside that suite directory.

Site values (`MAX_CASES`, `FROM_LIB`, `GDP_BASE`, `VSE_VERSION`, `ICM_ENV`, `CDS_LIB_MGR`) are the only
difference between sites. `site/<site>.env` lists them as `KEY=value` lines that replace the matching lines of
`shared/code/env.sh` when a suite is deployed.

---

## Deploy

`deploy.sh` assembles one suite in its prod layout: tracked files of `suites/<suite>/` with the
`shared/` links dereferenced, and `code/env.sh` rendered with `site/<site>.env`.

```bash
./deploy.sh perf prod                 # → build/prod/2_perf_mp
./deploy.sh cico prod /path/to/1_cico_mp
```

The destination must not exist or must be empty. Only git-tracked files are copied, so runtime
outputs never end up in a deployment. Their content is taken from the working tree: uncommitted
changes under the suite, `shared/` or `site/` are deployed too, with a warning listing them.
Every deployment gets a `.deploy_info` file (commit, dirty or not, suite, site, time, user).

Check a deployment against a prod snapshot (runtime outputs and generated replays are ignored):

```bash
tools/compare_deploy.sh build/prod/2_perf_mp reference/prod/2_perf_mp
```

Expected differences (all intended):
- Fixes made in this repo since the prod snapshot (scripts, cico `control`/`list`, func `func_control`,
  perf `GenerateReplayScript/changeLibRef`, `copyHierToEmpty`), and the `VSE_VERSION` line of `env.sh`.
- cico adds `code/.cdsenv` (cico uses the func `.cdsenv`) and `code/validate.il` (the legacy cico
  version; `template.il` loads it and `control` calls `Validate()`, but the prod snapshot lacks it).
- perf and func leave out the files listed in `archive/README.md`, plus the cico scripts prod also
  ships but they never call (perf: `init.sh`, `run_single_test.sh`, `summary.sh`, `teardown.sh`,
  `teardown_all.sh`, `teardown_worker.sh`; func: `run_single_test.sh`).

---

## Prerequisites

- Tools: `gdp`, `xlp4`, `vse_run` (or `vse_sub`) must be available in `$PATH`
- Python 3 (standard library only, no conda required)

---

## Configuration — `shared/code/env.sh`

| Variable | Description |
|----------|-------------|
| `USER_NAME` | Current user (`$USER`) |
| `WS_PREFIX` | cico workspace name prefix (default `cico_ws_<user>`, override: `CAT_WS_PREFIX` or `-ws`) |
| `PROJ_PREFIX` | cico GDP project name prefix (default `cico_<user>`, override: `CAT_PROJ_PREFIX` or `-proj`) |
| `FUNC_WS_PREFIX` / `FUNC_PROJ_PREFIX` | func prefixes (override: `CAT_FUNC_WS_PREFIX` / `CAT_FUNC_PROJ_PREFIX` or `-ws` / `-proj`) |
| `LIBNAME` | Default target library name |
| `CELLNAME` | Default target cell name |
| `MAX_CASES` | cico test count (site value: dev 144 = the legacy cases, prod 256) |
| `FROM_LIB` | Source library path for GDP library creation |
| `GDP_BASE` | GDP base path for all projects |
| `CICO_GDP_BASE` | GDP base path for CICO projects (default: `${GDP_BASE}/cico`) |
| `PERF_GDP_BASE` | GDP base path for perf projects (default: `${GDP_BASE}/perf`) |
| `VSE_VERSION` | Virtuoso version passed to `vse_run` / `vse_sub` (site value; override: `CAT_VSE_VERSION`, perf also `-version`) |
| `GDP_PROJ_MAX_ATTEMPTS` | `gdp create project` attempts, 10 s apart (default 5) |
| `VSE_MODE` | `run` (synchronous) or `sub` (batch submit + poll) |
| `ICM_ENV` | ICManage environment setup script path |
| `CDS_LIB_MGR` | Path to `cdsLibMgr.il` |
| `DRY_RUN` | Default dry-run level (0/1/2) |
| `PERF_LIBS` | Array of library names for perf testing |
| `PERF_CELLS` | Array of cell names (index-paired with PERF_LIBS) |
| `PERF_TESTS` | Array of perf test types |
| `PERF_PREFIX` | GDP workspace name prefix for perf workspaces |
| `PERF_BASE_LIBS` | Libraries added to every perf workspace (`DRAMLIB`) |
| `PERF_PRISTINE_OA` | UNMANAGED: untouched copy of `oa/` restored before every run (`.oa_pristine`) |

Overrides use framework-specific names (`CAT_*`), so an unrelated `WS_PREFIX` or `VSE_VERSION`
exported in the shell is never picked up. The entry scripts export the `CAT_*` names for their children.

---

## Dry-Run Levels

| Level | Behavior |
|-------|----------|
| `0` | All commands execute normally |
| `1` | Skips `gdp`, `xlp4`, `rm`, `vse_run`, `vse_sub` — `gdp build workspace` creates a local directory instead (honours `--location`) |
| `2` | All commands skipped (print only) |

To run level 0 locally, put `tools/mock` first in `PATH` (and set `ICM_SkillRoot` to any value).
The mock `gdp` keeps the GDP objects it creates in a registry file and answers like the real gdp:
`gdp list <path>` prints the path only if the object exists, `<path>/` adds everything below it,
`<path>/:<type>` lists the children of that type. `MOCK_GDP_STATE` sets the registry file
(default `${TMPDIR:-/tmp}/mock_gdp_<user>.tsv`); `MOCK_GDP_DOWN=1` makes every call fail with no output
(gdp not answering), to check that teardown and sweeps fail closed.

---

## Regression Tests — `main.sh`

### Usage

```bash
./main.sh [options]
```

| Option | Description | Default |
|--------|-------------|---------|
| `-h` / `--help` | Print help | |
| `-lib` / `--library <name>` | Library name | `$LIBNAME` |
| `-ws` / `--ws_name <name>` | Workspace prefix | `$WS_PREFIX` |
| `-proj` / `--proj_prefix <p>` | Project prefix | `$PROJ_PREFIX` |
| `-cell` / `--cell <name>` | Cell name | `$CELLNAME` |
| `-m` / `--max <n>` | Run tests 1~N | `$MAX_CASES` |
| `-c` / `--cases <list>` | Run specific tests (e.g. `1,2,5-9`) | |
| `-j` / `--jobs <n>` | Parallel job count | `4` |
| `-d` / `--dry-run [0/1/2]` | Dry-run level (`-d` alone = 2) | `$DRY_RUN` |
| `-k` / `--keep` / `--no-teardown` | Skip teardown: keep GDP projects, workspaces and p4 clients | |
| `-t` / `--teardown` | Accepted for compatibility (teardown is the default) | on |
| `-debug` / `-keep-artifacts` | Keep `regression_test_NNN/` and `code/replay_files_<id>/` after a successful teardown | |

> `-m` and `-c` cannot be used together.
>
> Test numbers are line numbers of `code/list`: 1–144 are the legacy 144 cases in legacy order,
> 145–256 the Fast-series cases.
>
> Exit status: non-zero if a test could not run (init or Virtuoso failed), the summary crashed or a
> teardown failed; summary and teardown still run. It does not reflect the PASS/FAIL verdicts (as in
> legacy): read `result/<id>/summary.txt` for those. The same applies to `func_main.sh`.

**Examples:**
```bash
# Dry-run all tests (print only)
./main.sh -d 2

# Run tests 1~10 with 8 parallel jobs
./main.sh -m 10 -j 8

# Run with a different library
./main.sh -lib MY_LIB -c 1-20

# Run specific tests and keep their GDP projects for debugging
./main.sh -c 1,3,5-9 -k
```

### Test Lifecycle (per test)

```
main.sh
 └─ run_single_test.sh
     ├─ init.sh            # gdp create project / variant / libtype / config / library / workspace
     ├─ ln -sf cdsLibMgr   # link cdsLibMgr.il into workspace
     └─ run_vse()          # vse_run (sync) or vse_sub + bjobs poll (batch)
```

### Teardown

Each test is torn down in the background as soon as it finishes (`teardown_worker.sh`). A failed
teardown is recorded in `<regression_dir>/teardown_queue.txt.failed`; after a successful run the
regression directory and the replay folder are removed (unless `-debug`).

```bash
# Tear down a -k run, or retry failed teardowns (reads teardown_queue.txt(.failed) and run_prefixes)
./code/teardown_all.sh [-d 0/1/2] [-j <n>] <regression_dir>

# Sweep leftover GDP projects by name (e.g. after clean.sh or an interrupted run)
./code/teardown_all.sh -p cico_<user>_          # list candidates only
./code/teardown_all.sh -p cico_<user>_ -y       # delete them
```

A project whose gdp query fails is never treated as gone: it is skipped (sweep) or the delete is
attempted and counted (teardown), so a GDP outage cannot make a teardown report success.

---

## Functional Tests — `func_main.sh`

```bash
./func_main.sh -mode <mode> [-prefix oo|ox|xo|xx] -lib <lib> -cell <cell> [options]
```

| Option | Description | Default |
|--------|-------------|---------|
| `-mode <mode>` | `checkHier`, `renameRefLib`, `changeLibRef`, `replace`, `deleteAllMarkers`, `copyHierToEmpty`, `copyHierToNonEmpty` | required |
| `-prefix <p>` | Variant list `code/list_<mode>_<p>` | |
| `-lib`, `-cell`, `-fromLib`, `-toLib`, `-fromCell` | Targets substituted into the scenarios | |
| `-m` / `-M` / `-c <list>` | Min / max test number, or a list (`1,3,5-9`) | all lines of the list |
| `-j <n>` | Parallel jobs | `4` |
| `-d [0/1/2]` | Dry-run level (`-d` alone = 2) | `$DRY_RUN` |
| `-ws` / `-proj` | Workspace / project prefix | `func_ws_<user>` / `func_<user>` |
| `-k` / `--keep` / `--no-teardown` | Skip teardown | |
| `-t` | Accepted for compatibility (teardown is the default) | on |

Scenarios are generated from `code/func_control` + `code/list_<mode>[_<prefix>]` + `code/func_template.il`.
Results are judged by `code/func_summary.sh` with the legacy rules, on the result files the replay
writes (`result/<id>/test_<N>_<ver>.log`): no `End Time` → FAIL, a `=== ... ===` section without a
`Row_` line → FAIL, a FAIL token → FAIL (check-in/out FAIL reported as WARNING), otherwise PASS.
A selected test that left no result file counts as FAIL.

```bash
# After a -k run, or to retry failed teardowns (run before clean.sh)
./code/func_teardown_all.sh [-d 0/1/2] [-j <n>] <regression_test_<mode>_NNN>
```

---

## Performance Tests — `perf_main.sh`

Performance tests use a **directory-based** workflow: workspaces are tracked by scanning `WORKSPACES_MANAGED/` — no session file needed. Each library/test combination can have at most one workspace at a time.

### Usage

```bash
./perf_main.sh [options]
```

| Option | Description | Default |
|--------|-------------|---------|
| `-h` / `--help` | Print help | |
| `-lib <lib[,lib,...]>` | Libraries to test | all `$PERF_LIBS` |
| `-test <test[,test,...]>` | Test types to run | all `$PERF_TESTS` |
| `-mode <managed\|unmanaged>[,...]` | Workspace mode(s), comma or space separated | both |
| `-version <ver>` | Virtuoso version for `vse_run -v` | `$VSE_VERSION` |
| `-common <lib[,lib,...]>` | Libraries added to ALL test combos (any name accepted) | |
| `-j` / `--jobs <n>` | Parallel job count | `4` |
| `-d` / `--dry-run [0/1/2]` | Dry-run level | `$DRY_RUN` |
| `-gen-replay` / `--gen-replay` | Generate replay files only (no init or run) | |
| `-no-run` / `--no-run` | Init workspaces only; skip test execution | |
| `-t` / `--teardown` | Run teardown; `-lib`/`-test` filters apply; also runs when tests failed | |
| `-auto-init` / `--auto-init` | Auto-init if no workspaces found (no prompt) | |

### Workflow

```bash
# Step 1: Set up workspaces (once)
./perf_main.sh -no-run -lib BM01,BM02 -test checkHier,renameRefLib

# Step 2: Run tests (repeat as needed)
./perf_main.sh
./perf_main.sh -lib BM01 -mode managed

# Step 3: Tear down when done
./perf_main.sh -no-run -t -lib BM01       # specific combo
./perf_main.sh -no-run -t                 # all workspaces

# One-shot: init → run → teardown
./perf_main.sh -auto-init -t

# Generate replay files only
./perf_main.sh -gen-replay -lib BM01 -test checkHier

# Sweep GDP projects whose local workspace is gone (not reached by -t)
./code/perf_teardown_all.sh [-d 0/1/2] [-j <n>] [-min-age <minutes>] [-y]
```

`perf_teardown_all.sh` lists `PERF_GDP_BASE/perf_*` projects and tears down those without a
registered workspace or whose workspace directory is gone. It keeps projects younger than
`-min-age` (default 120 min) and every combination with a local `WORKSPACES_MANAGED/<ws>`, and
deletes nothing when a gdp query fails. `-y` skips the confirmation prompt.

### Workspace Tracking

Active workspaces are stored under `WORKSPACES_MANAGED/` and `WORKSPACES_UNMANAGED/`:

```
WORKSPACES_MANAGED/
  perf_checkHier_BM01_20260422_093015_john/
  perf_renameRefLib_BM02_20260422_093020_john/
```

Workspace names follow the pattern: `perf_<testtype>_<lib>_<uniqueid>`

### Phases

| Phase | Script | Parallelism |
|-------|--------|-------------|
| 1 — Generate replays | `perf_generate_replay.sh` | Sequential |
| 2 — Init workspaces | `perf_init.sh` | Parallel (`xargs -P`) |
| 3 — Run tests | `perf_run_single.sh` | Parallel (`xargs -P`) |
| 4 — Summary | `perf_summary.sh` | Sequential |
| 5 — Teardown | `perf_teardown.sh` | Parallel (`xargs -P`) |

> Workspace builds (`perf_init.sh`) run in parallel, up to `-j` at a time; nothing serialises them.

Every run starts from the same data. Before each replay (not timed), `perf_run_single.sh` resets the workspace:
- MANAGED: `xlp4 revert` of files left opened, `xlp4 sync`, and `sync -f` only for files sync refuses to clobber
- UNMANAGED: restore `oa/` from `.oa_pristine/`, the copy `perf_init.sh` saves after setup
  (workspaces created before this change have no copy and run without reset)

Every perf workspace also gets `PERF_BASE_LIBS` (`DRAMLIB`), which the HierCopy templates skip.

---

## Summary Reports

All summaries are called by their entry script; they are listed here for reruns.

### cico (`code/summary.sh`)

```bash
./code/summary.sh [-d 0/1/2] [--logdir <dir>] [<time_version>]
```

Reads the result files under `result/<time_version>/`, counts PASS/FAIL and writes `summary.txt` there.

### func (`code/func_summary.sh`)

```bash
./code/func_summary.sh [-d 0/1/2] [-t "<test numbers>"] <mode> <uniqueid> <result_folder_id> [summary_file_name]
```

Legacy judging rules (see Functional Tests); writes the summary into `result/<result_folder_id>/`.

### perf (`code/perf_summary.sh`)

Reads `CDS_log/<uniqueid>/timing.tsv` and writes
- `CDS_log/<uniqueid>/perf_summary.txt`: elapsed-time table
- `result/<uniqueid>/summary.txt`: the legacy per-replay summary
- `perf_metrics/history.jsonl`: one JSON record per measurement (append-only trend data)

---

## Clean Local Outputs

```bash
cd suites/<suite> && ./clean.sh
```

Cleans the suite directory it is run from (`-n` only prints what would be removed).

- Every suite: `CDS_log/`, `log/`, `.trash/`, `code/replay_files*`, `code/date_virtuosoVer.txt`, Python cache
- cico / func: `regression_test_*/`, `regression_num*.txt`, `code/func_template_*.il`, mock `*_ws_*/` dirs
- perf: generated `GenerateReplayScript/*.au` and `lcv.txt`, mock workspaces (no `.gdpxl`), and
  `WORKSPACES_UNMANAGED/<ws>` copies whose MANAGED workspace is gone

Kept: `result/`, `perf_metrics/`, real GDP workspaces (with `.gdpxl`) and regression directories that
still owe a teardown (`-k` run or failed teardowns); the teardown command is printed for them.

---

## Documentation

| File | Content |
|------|---------|
| `docs/MANUAL_MAIN.md` | Beginner guide for main.sh (English) |
| `docs/MANUAL_MAIN_KR.md` | Beginner guide for main.sh (Korean) |
| `docs/MANUAL_PERF.md` | Beginner guide for perf_main.sh (English) |
| `docs/MANUAL_PERF_KR.md` | Beginner guide for perf_main.sh (Korean) |
| `docs/IMPROVEMENTS*.md` | Changes compared to legacy |
| `docs/ANALYSIS_PERF_KR.md` | perf code and replay template analysis (Korean) |

The manuals still describe the pre-restructure layout (root-level `main.sh`, `code/`); run commands from the suite directory.
