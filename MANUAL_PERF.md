# CAT - Performance Test Runner Guide (perf_main.sh)

## 1. What Does This Program Do?

`perf_main.sh` is the **Virtuoso performance measurement automation tool**.

It runs Virtuoso operations across combinations of libraries and test types, measures the elapsed time for each test, and generates a summary report.

Each test runs in two modes — **Managed workspace** and **Unmanaged workspace** — allowing direct performance comparison between the two environments.

### Managed vs Unmanaged Workspace

| | Managed | Unmanaged |
|-|---------|-----------|
| Type | ICM-controlled (DMTYPE: p4) | Local only (DMTYPE: none) |
| Location | `WORKSPACES_MANAGED/<ws_name>/` | `WORKSPACES_UNMANAGED/<ws_name>/` |
| Characteristics | Registered in GDP/Perforce | Not GDP-registered; independent after xlp4 sync |

### Internal Workflow (Step by Step)

| Step | Description |
|------|-------------|
| 1. Replay generation | `perf_generate_replay.sh` → generates `.au` files (result path hard-coded inside) |
| 2. Workspace init | `perf_init.sh` → creates GDP project/library/workspace |
| 3. Replay distribution | Copies generated `.au` files into each workspace |
| 4. Test execution | `perf_run_single.sh` → runs Virtuoso and records elapsed time |
| 5. Teardown (optional) | `perf_teardown.sh` → removes workspaces |
| 6. Summary | `perf_summary.sh` → outputs elapsed time table per test |

### Workspace Tracking

Workspaces are tracked by **directory scan** — no session file required.

- Active workspaces exist under `WORKSPACES_MANAGED/`
- Each library/test combination can have **at most one** workspace at a time
- Init is automatically skipped for combinations that already have a workspace

```
WORKSPACES_MANAGED/
  perf_checkHier_BM01_20260422_093015_john/
  perf_renameRefLib_BM02_20260422_093020_john/
```

---

## 2. Prerequisites

### 2.1 Environment Variables (`code/env.sh`)

| Variable | Description | Example |
|----------|-------------|---------|
| `PERF_PREFIX` | Workspace name prefix | `perf` |
| `PERF_GDP_BASE` | Perf-dedicated GDP path | `<GDP_BASE>/perf` |
| `PERF_LIBS` | List of test libraries | `(BM01 BM02 BM03)` |
| `PERF_CELLS` | Cell name for each library (same order) | `(VP_FULLCHIP FULLCHIP XE_FULLCHIP_BASE)` |
| `PERF_TESTS` | List of test types | `(checkHier renameRefLib ...)` |
| `GDP_BASE` | Per-user GDP base path | `/MEMORY/TEST/CAT/CAT_WORKING/<user>` |
| `FROM_LIB` | Source library GDP path | `/MEMORY/TEST/CAT/CAT_LIB/TEST_PRJ/rev1/oa` |
| `VSE_VERSION` | Virtuoso version tag | `IC251_ISR5-023_CAT` |

**Important:** `PERF_LIBS` and `PERF_CELLS` must be in the same order.  
Example: `PERF_LIBS[0]=BM01` ↔ `PERF_CELLS[0]=VP_FULLCHIP`

### 2.2 Required External Tools

- `gdp` — IC Manage GDP client (must be in PATH)
- `xlp4` — Perforce client wrapper
- `python3` — for replay file generation
- Virtuoso (`vse_run` or `vse_sub`) — test execution engine
- `createReplay.pl` — Perl script for generating replay `.au` files

### 2.3 Verify GDP Access

```bash
gdp list /MEMORY/TEST/CAT/CAT_LIB
```

If the listing appears without errors, your connection is working.

---

## 3. Basic Usage

### Option Reference

```
./perf_main.sh [options]

  -h              Print help
  -lib <list>     Libraries to test, comma-separated (default: all)
                    Valid values: BM01 BM02 BM03
  -test <list>    Test types to run, comma-separated (default: all)
                    Valid values: checkHier renameRefLib replace deleteAllMarker
                                  copyHierToEmpty copyHierToNonEmpty
  -common <list>  Common libraries added to ALL test combos (any name accepted)
  -mode <mode>    Workspace mode to run (default: both)
                    managed | unmanaged
  -j <n>          Parallel job count (default: 4)
  -d [0|1|2]      Dry-run level
                    0 = run everything
                    1 = skip gdp/xlp4/rm/vse (mock)
                    2 = skip all commands (print only)
  -gen-replay     Generate replay files only; no init or run
  -no-run         Run init phases only; skip test execution
  -t              Run teardown; -lib/-test filters apply
  -auto-init      Auto-init workspaces if none found (no prompt)
```

---

## 4. Step-by-Step Examples

### Step 0: Preview with Dry-run

```bash
./perf_main.sh -d 2
```

Prints all commands that would run without making any changes.

### Step 1: Initialize Workspaces (first time only)

```bash
./perf_main.sh -no-run -lib BM01,BM02 -test checkHier,renameRefLib
```

- Creates GDP project, libraries, and workspaces
- Sets up both Managed and Unmanaged workspace directories
- Automatically skips combinations that already have a workspace

Verify created workspaces:

```bash
ls WORKSPACES_MANAGED/
```

### Step 2: Run Tests

```bash
./perf_main.sh -lib BM01,BM02 -test checkHier,renameRefLib
```

A new uniqueid is generated each run, so results are stored independently every time.

Run a specific mode only:

```bash
./perf_main.sh -lib BM01 -test checkHier -mode managed
```

### Step 3: Check Results

```
CDS_log/<uniqueid>/
  timing.tsv                         ← raw elapsed times (tab-separated)
  perf_summary.txt                   ← formatted summary report
  checkHier_BM01_managed.log         ← Virtuoso execution log
  checkHier_BM01_unmanaged.log
```

Example `perf_summary.txt`:

```
Performance Summary (20260422_093015_john)
================================================================
Test (testtype/lib)          Mode         Elapsed
----------------------------------------------------------------
checkHier/BM01               managed      00:02:34
checkHier/BM01               unmanaged    00:01:58
renameRefLib/BM02            managed      00:03:10
renameRefLib/BM02            unmanaged    00:02:45
----------------------------------------------------------------

Total  (4 tests)                          00:10:27
Average                                   00:02:36
```

### Step 4: Tear Down Workspaces

Tear down a specific combination:

```bash
./perf_main.sh -no-run -t -lib BM01 -test checkHier
```

Tear down everything:

```bash
./perf_main.sh -no-run -t
```

---

## 5. Usage by Purpose

### Full Run in One Shot (init → run → teardown)

```bash
./perf_main.sh -auto-init -t -lib BM01 -test checkHier
```

- Auto-inits workspaces if none found (no prompt)
- Tears down automatically after tests complete

### Repeated Measurements (Reuse Same Workspaces)

Initialize once, then run as many times as needed:

```bash
# One-time init
./perf_main.sh -no-run -lib BM01 -test checkHier

# Repeat runs — each stores results independently
./perf_main.sh -lib BM01 -test checkHier
./perf_main.sh -lib BM01 -test checkHier
```

### Managed Mode Only

```bash
./perf_main.sh -mode managed
```

### Add Common Libraries to All Test Combos

```bash
./perf_main.sh -lib BM01 -common COMMON_LIB1,COMMON_LIB2
```

Libraries specified with `-common` are accepted regardless of whether they are in `PERF_LIBS`.

### Generate Replay Files Only (No Execution)

```bash
./perf_main.sh -gen-replay -lib BM01 -test checkHier
```

Output: `GenerateReplayScript/checkHier_BM01_managed.au`, etc.

### Run All Combinations with Teardown

```bash
./perf_main.sh -auto-init -t -j 8
```

---

## 6. Key Concepts

### uniqueid

- Format: `YYYYMMDD_HHMMSS_<user>`
- **Init phase**: embedded in workspace name (`perf_checkHier_BM01_<uniqueid>`)
- **Run phase**: used as the CDS log and result directory name (`CDS_log/<uniqueid>/`)
- Generated fresh on every run — results never overwrite each other

### Replay Files (.au)

- Automation scripts passed to Virtuoso
- The result storage path (including uniqueid) is **hard-coded inside** the `.au` file
- Therefore, replay files are regenerated and redistributed to all workspaces on every run

### Workspace Naming Convention

```
perf_<testtype>_<lib>_<uniqueid>
Example: perf_checkHier_BM01_20260422_093015_john
```

---

## 7. Logs and Result File Locations

| Location | Content |
|----------|---------|
| `log/perf_main.log.<timestamp>.txt` | Full execution log |
| `WORKSPACES_MANAGED/<ws_name>/` | Managed workspace directories |
| `WORKSPACES_UNMANAGED/<ws_name>/` | Unmanaged workspace directories |
| `GenerateReplayScript/*.au` | Generated replay files |
| `CDS_log/<uniqueid>/timing.tsv` | Per-test elapsed times (tab-separated) |
| `CDS_log/<uniqueid>/perf_summary.txt` | Formatted performance summary report |
| `CDS_log/<uniqueid>/<testtype>_<lib>_<mode>.log` | Individual Virtuoso execution logs |
| `result/<uniqueid>/` | Test result data |

---

## 8. Common Errors and Solutions

| Error Message | Cause | Solution |
|---------------|-------|----------|
| `No workspaces found... Run init first with -no-run` | Running tests without any initialized workspaces | Run `./perf_main.sh -no-run -lib <lib> -test <test>` first |
| `Unknown lib: XYZ` | Specified an unregistered library with `-lib` | Check `PERF_LIBS` in `env.sh` (note: `-common` accepts any name) |
| `Unknown test: XYZ` | Specified a non-existent test type with `-test` | Check `PERF_TESTS` in `env.sh` |
| `gdp build workspace failed after 5 attempts` | GDP server overload or network issue | Retry after a few minutes, or contact IT support |
| `Workspace not found via gdp find` | Workspace not registered in GDP | Manually check `WORKSPACES_MANAGED/`, teardown and re-init if needed |
| `.gdp_ws_lock` file left behind | Previous run terminated abnormally | `rm .gdp_ws_lock` then re-run |

---

## 9. Important Notes

- **`-lib` and `-test` replace the concept of test case numbers.** There is no `--max` or `--cases` option.
- **Pressing Ctrl+C** triggers the `_cleanup()` trap, which automatically removes the lock file.
- **Running init again** for an existing library/test combination is safe — it is silently skipped without overwriting.
- **Replay files are auto-regenerated on every run.** You do not need to generate them manually.
- `gdp build workspace` is **serialized with flock** to reduce GDP server load — workspaces are built one at a time regardless of `-j`.
