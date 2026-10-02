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
│       ├── summary.sh · teardown_worker.sh                                                 (cico, func)
│       ├── mgHierParse.il · virtuosoVer.il                                                 (cico, func)
│       └── .cdsenv                # Virtuoso env shared by cico and func
├── suites/
│   ├── cico/                      # = 1_cico_mp
│   │   ├── main.sh                # Regression test entry point
│   │   └── code/                  # run_single_test.sh, init.sh, teardown.sh, teardown_all.sh, validate.il,
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
│   └── mock/                      # Mock gdp / xlp4 for DRY_RUN testing (not deployed)
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
outputs never end up in a deployment.

Check a deployment against a prod snapshot (runtime outputs and generated replays are ignored):

```bash
tools/compare_deploy.sh build/prod/2_perf_mp reference/prod/2_perf_mp
```

Expected differences (all intended):
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
| `WS_PREFIX` | Workspace name prefix (e.g. `cico_ws_<user>`) |
| `PROJ_PREFIX` | GDP project name prefix (e.g. `cico_<user>`) |
| `LIBNAME` | Default target library name |
| `CELLNAME` | Default target cell name |
| `MAX_CASES` | Maximum test count (default: 256) |
| `FROM_LIB` | Source library path for GDP library creation |
| `GDP_BASE` | GDP base path for all projects |
| `CICO_GDP_BASE` | GDP base path for CICO projects (default: `${GDP_BASE}/cico`) |
| `PERF_GDP_BASE` | GDP base path for perf projects (default: `${GDP_BASE}/perf`) |
| `VSE_VERSION` | Virtuoso version string passed to `vse_run` / `vse_sub` |
| `VSE_MODE` | `run` (synchronous) or `sub` (batch submit + poll) |
| `ICM_ENV` | ICManage environment setup script path |
| `CDS_LIB_MGR` | Path to `cdsLibMgr.il` |
| `DRY_RUN` | Default dry-run level (0/1/2) |
| `PERF_LIBS` | Array of library names for perf testing |
| `PERF_CELLS` | Array of cell names (index-paired with PERF_LIBS) |
| `PERF_TESTS` | Array of perf test types |
| `PERF_PREFIX` | GDP workspace name prefix for perf workspaces |

---

## Dry-Run Levels

| Level | Behavior |
|-------|----------|
| `0` | All commands execute normally |
| `1` | Skips `gdp`, `xlp4`, `rm`, `vse_run`, `vse_sub` — `gdp build workspace` creates a local directory instead |
| `2` | All commands skipped (print only) |

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
| `-d` / `--dry-run [0/1/2]` | Dry-run level | `$DRY_RUN` |
| `-t` / `--teardown` | Run teardown after all tests | |

> `-m` and `-c` cannot be used together.

**Examples:**
```bash
# Dry-run all tests (print only)
./main.sh -d 2

# Run tests 1~10 with 8 parallel jobs
./main.sh -m 10 -j 8

# Run with a different library
./main.sh -lib MY_LIB -c 1-20

# Run specific tests and teardown after
./main.sh -c 1,3,5-9 -t
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

```bash
# Single regression directory (standalone)
./code/teardown_all.sh [-d 0/1/2] <regression_dir>

# Automatic (via main.sh)
./main.sh -m 10 -t
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
| `-mode <managed\|unmanaged>` | Workspace mode | both |
| `-common <lib[,lib,...]>` | Libraries added to ALL test combos (any name accepted) | |
| `-j` / `--jobs <n>` | Parallel job count | `4` |
| `-d` / `--dry-run [0/1/2]` | Dry-run level | `$DRY_RUN` |
| `-gen-replay` / `--gen-replay` | Generate replay files only (no init or run) | |
| `-no-run` / `--no-run` | Init workspaces only; skip test execution | |
| `-t` / `--teardown` | Run teardown; `-lib`/`-test` filters apply | |
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
```

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

> `gdp build workspace` is serialized with `flock` regardless of `-j` to reduce GDP server load.

---

## Summary Reports

### Regression summary (`summary.sh`)

```bash
./code/summary.sh [-d 0/1/2] <uniqueid>
```

Reads `result/<uniqueid>/*.log`, counts PASS/FAIL, and writes `result/<uniqueid>/summary.txt`.

### Performance summary (`perf_summary.sh`)

Automatically called at the end of each `perf_main.sh` run. Reads `CDS_log/<uniqueid>/timing.tsv` and writes a formatted elapsed-time table to `CDS_log/<uniqueid>/perf_summary.txt`.

---

## Clean Local Outputs

```bash
cd suites/<suite> && ./clean.sh
```

Cleans the suite directory it is run from. Removes: `regression_test_*/`, `CDS_log/`, `code/replay_files/`, dry-run workspaces (`cico_ws_*/`), Python cache.

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
