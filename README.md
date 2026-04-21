# CAT - Cadence Automation Test Framework

Regression and performance test automation framework for Virtuoso replay-based testing.
Supports parallel test execution, GDP workspace lifecycle management, and dry-run simulation.

---

## Directory Structure

```
CAT/
├── main.sh                        # Regression test entry point
├── perf_main.sh                   # Performance test entry point
├── clean.sh                       # Remove all generated outputs
├── MANUAL_MAIN.md                 # Beginner guide for main.sh (English)
├── MANUAL_MAIN_KR.md              # Beginner guide for main.sh (Korean)
├── MANUAL_PERF.md                 # Beginner guide for perf_main.sh (English)
├── MANUAL_PERF_KR.md              # Beginner guide for perf_main.sh (Korean)
├── code/
│   ├── env.sh                     # Environment config (not tracked by git)
│   ├── common.sh                  # Shared utilities (log, run_cmd, run_vse, build_gdp_workspace, ...)
│   ├── generate_templates.py      # Generate replay_001.il ~ replay_256.il
│   ├── init.sh                    # Create GDP project/workspace per test
│   ├── run_single_test.sh         # Execute a single test (called by xargs)
│   ├── teardown.sh                # Destroy GDP project/workspace for one test
│   ├── teardown_all.sh            # Batch teardown for all tests in a regression dir
│   ├── teardown_worker.sh         # Background teardown queue worker
│   ├── summary.sh                 # Parse CDS logs and generate pass/fail summary
│   ├── perf_generate_replay.sh    # Generate perf replay .au files
│   ├── perf_init.sh               # Create GDP project/workspace per perf combo
│   ├── perf_run_single.sh         # Execute a single perf test + record elapsed time
│   ├── perf_teardown.sh           # Destroy GDP workspace for one perf combo
│   └── perf_summary.sh            # Generate per-test elapsed time summary
```

---

## Prerequisites

- `env.sh` must exist at `code/env.sh`
- Tools: `gdp`, `xlp4`, `vse_run` (or `vse_sub`) must be available in `$PATH`
- Python 3 (standard library only, no conda required)

---

## Configuration — `code/env.sh`

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
./clean.sh
```

Removes: `regression_test_*/`, `CDS_log/`, `code/replay_files/`, dry-run workspaces (`cico_ws_*/`), Python cache.

---

## Documentation

| File | Content |
|------|---------|
| `MANUAL_MAIN.md` | Beginner guide for main.sh (English) |
| `MANUAL_MAIN_KR.md` | Beginner guide for main.sh (Korean) |
| `MANUAL_PERF.md` | Beginner guide for perf_main.sh (English) |
| `MANUAL_PERF_KR.md` | Beginner guide for perf_main.sh (Korean) |
