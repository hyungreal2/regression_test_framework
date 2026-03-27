# CAT - Cadence Automation Test Framework

Regression test automation framework for Virtuoso replay-based testing.
Supports parallel test execution, GDP workspace lifecycle management, and dry-run simulation.

---

## Directory Structure

```
CAT/
├── main.sh                      # Main entry point
├── clean.sh                     # Remove all generated outputs
├── code/
│   ├── env.sh                   # Environment config (not tracked by git)
│   ├── env_sample.csh           # Template for csh users
│   ├── common.sh                # Shared utilities (log, run_cmd, safe_rm_rf, ...)
│   ├── generate_templates.py    # Generate replay_001.il ~ replay_240.il
│   ├── init.sh                  # Create GDP project/workspace per test
│   ├── run_single_test.sh       # Execute a single test (called by xargs)
│   ├── teardown.sh              # Destroy GDP project/workspace for one test
│   ├── teardown_all.sh          # Batch teardown for all tests in a regression dir
│   └── summary.sh               # Parse CDS logs and generate pass/fail summary
└── org/                         # Original pre-refactor versions (reference only)
```

---

## Prerequisites

- `env.sh` must exist at `code/env.sh` (copy and fill from `code/env_sample.csh`)
- Tools: `gdp`, `xlp4`, `vse_sub`, `bwait` must be available in `$PATH`
- Python 3 (standard library only, no conda required)

---

## Configuration — `code/env.sh`

| Variable | Description |
|----------|-------------|
| `USER_NAME` | Current user (`$USER`) |
| `WS_PREFIX` | Workspace name prefix (e.g. `cico_ws_<user>`) |
| `PROJ_PREFIX` | GDP project name prefix (e.g. `cico_<user>`) |
| `MAX_CASES` | Maximum test count (default: 240) |
| `FROM_LIB` | Source library path for GDP library creation |
| `GDP_BASE` | GDP base path for all projects |
| `VSE_VERSION` | Virtuoso version string passed to `vse_sub` |
| `ICM_ENV` | ICManage environment setup script path |
| `CDS_LIB_MGR` | Path to `cdsLibMgr.il` |
| `DRY_RUN` | Default dry-run level (0/1/2) |

---

## Usage

### Run Regression

```bash
./main.sh [options]
```

| Option | Description | Default |
|--------|-------------|---------|
| `-h` / `--help` | Print help | |
| `-ws` / `--ws_name <name>` | Workspace prefix | `$WS_PREFIX` |
| `-proj` / `--proj_prefix <p>` | Project prefix | `$PROJ_PREFIX` |
| `-cell` / `--cell <name>` | Cell name | `XE_FULLCHIP_BASE` |
| `-m` / `--max <n>` | Run tests 1~N | `$MAX_CASES` |
| `-c` / `--cases <list>` | Run specific tests (e.g. `1,2,5`) | |
| `-j` / `--jobs <n>` | Parallel job count | `4` |
| `-d` / `--dry-run [0/1/2]` | Dry-run level | `2` |
| `-t` / `--teardown` | Run teardown after all tests | |

> `-m` and `-c` cannot be used together.

**Examples:**
```bash
# Dry-run all 240 tests (level 2, no commands executed)
./main.sh -d 2

# Run tests 1~10 with 8 parallel jobs
./main.sh -m 10 -j 8 -d 0

# Run specific tests and teardown after
./main.sh -c 1,3,5 -d 0 -t

# Dry-run level 1: skips gdp/xlp4/vse_sub/bwait, creates workspace dirs locally
./main.sh -m 5 -d 1
```

---

## Dry-Run Levels

| Level | Behavior |
|-------|----------|
| `0` | All commands execute normally |
| `1` | Skips `gdp`, `xlp4`, `rm`, `vse_sub`, `bwait` — `gdp build workspace` creates a local directory instead |
| `2` | All commands skipped (print only) |

Dry-run messages are printed to **stderr** so command output can still be captured:
```bash
job_id=$(run_cmd "vse_sub ...")   # captures real output on level 0, empty on level 1/2
```

---

## Test Lifecycle (per test)

```
main.sh
 └─ run_single_test.sh
     ├─ init.sh            # gdp create project / variant / libtype / config / library / workspace
     ├─ ln -sf cdsLibMgr   # link cdsLibMgr.il into workspace
     ├─ vse_sub            # submit Virtuoso replay job → job_id
     ├─ sleep 60           # wait for job to enter queue
     └─ bwait              # wait for job completion
```

Each test gets a unique ID: `<test_num>_<timestamp>_<PID>`
Saved to `regression_test_<NNN>/test_<NNN>/uniqueid.txt` for teardown reference.

---

## Teardown

### Single regression directory:
```bash
./code/teardown_all.sh [-d 0/1/2] <regression_dir>

# Example
./code/teardown_all.sh -d 0 regression_test_001
```

### Automatic (via main.sh):
```bash
./main.sh -m 10 -d 0 -t
```

Teardown per test:
1. Find and delete GDP workspace (`gdp find` → `gdp delete workspace`)
2. Unlock and remove local workspace directory
3. Delete p4 client (`xlp4 client -d -f`)
4. Delete GDP project (`gdp delete --recursive`)
5. Obliterate depot (`xlp4 obliterate`)

---

## Summary Report

```bash
./code/summary.sh [-d 0/1/2] <time_version> [summary_file]
```

Reads `result/<time_version>/*.log`, counts PASS/FAIL, and writes a summary file.
Default output: `result/<time_version>/summary.txt`

---

## Clean Local Outputs

```bash
./clean.sh
```

Removes: `regression_test_*/`, `CDS_log/`, `code/replay_files/`, dry-run workspaces (`cico_ws_*/`), Python cache.
