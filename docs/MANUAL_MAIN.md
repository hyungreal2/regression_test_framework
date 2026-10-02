# CAT - CICO Regression Test Runner Guide (main.sh)

## 1. What Does This Program Do?

`main.sh` is the **CICO (Check-In Check-Out) regression test automation tool**.

It generates Virtuoso scripts (replay `.il` files) for IC design libraries such as ESD01, runs dozens to hundreds of tests in parallel, and produces a pass/fail summary report.

### Internal Workflow (Step by Step)

| Step | Description |
|------|-------------|
| 1. Environment validation | Validates inputs, checks/creates GDP folders |
| 2. Template generation | Runs `generate_templates.py` → auto-generates replay `.il` files |
| 3. Test directory setup | Creates `regression_test_NNN/test_NNN/` folders and places replay files |
| 4. Parallel test execution | Runs `run_single_test.sh` with up to `-j` concurrent jobs |
| 5. Teardown (optional) | Deletes workspaces after tests complete |
| 6. Summary | Runs `summary.sh` → aggregates pass/fail results |

---

## 2. Prerequisites

### 2.1 Environment Variables (`code/env.sh`)

| Variable | Description | Example |
|----------|-------------|---------|
| `LIBNAME` | Target library name | `ESD01` |
| `CELLNAME` | Target cell name | `FULLCHIP` |
| `WS_PREFIX` | Workspace name prefix | `cico_ws_<user>` |
| `PROJ_PREFIX` | GDP project name prefix | `cico_<user>` |
| `FROM_LIB` | Source library GDP path | `/MEMORY/TEST/CAT/CAT_LIB/TEST_PRJ/rev1/oa` |
| `GDP_BASE` | Per-user GDP working base path | `/MEMORY/TEST/CAT/CAT_WORKING/<user>` |
| `MAX_CASES` | Maximum test case number | `256` |
| `VSE_VERSION` | Virtuoso version tag | `IC251_ISR5-023_CAT` |

### 2.2 Required External Tools

- `gdp` — IC Manage GDP client (must be in PATH)
- `xlp4` — Perforce client wrapper
- `python3` — for template generation
- Virtuoso (`vse_run` or `vse_sub`) — test execution engine

### 2.3 Verify GDP Access

```bash
gdp list /MEMORY/TEST/CAT/CAT_LIB
```

If the listing appears without errors, your connection is working.

---

## 3. Basic Usage

### Option Reference

```
./main.sh [options]

  -h     | --help             Print help
  -lib   | --library <name>   Library name           (default: LIBNAME in env.sh)
  -ws    | --ws_name <name>   Workspace name prefix  (default: cico_ws_<user>)
  -proj  | --proj_prefix <p>  GDP project prefix     (default: cico_<user>)
  -cell  | --cell <name>      Cell name              (default: CELLNAME in env.sh)
  -m     | --max <n>          Max test number 1-256  (default: MAX_CASES)
  -c     | --cases <list>     Test numbers to run, comma-sep or ranges (e.g. 1,3,5-9)
  -j     | --jobs <n>         Parallel job count     (default: 4)
  -d     | --dry-run [0|1|2]  Dry-run level
                                0 = run everything
                                1 = skip gdp/xlp4/rm/vse (mock)
                                2 = skip all commands (print only)
  -t     | --teardown         Tear down workspaces after tests complete
```

---

## 4. Step-by-Step Examples

### Step 1: Preview with Dry-run

Check what will happen without executing anything.

```bash
./main.sh -d 2
```

### Step 2: Run a Small Subset First

```bash
./main.sh -c 1,2,3
```

Or specify a range:

```bash
./main.sh -c 1-10
```

### Step 3: Run All Tests

```bash
./main.sh
```

Default: runs all cases up to `MAX_CASES` with 4 parallel jobs.

### Step 4: Increase Parallelism

```bash
./main.sh -j 8
```

### Step 5: Run and Auto-teardown

```bash
./main.sh -t
```

---

## 5. Usage by Purpose

### Quick Smoke Test (cases 1–5 only)

```bash
./main.sh -c 1-5
```

### Test a Specific Cell

```bash
./main.sh -cell MY_CELL -c 1-20
```

### CI Automated Run with Teardown

```bash
./main.sh -t -j 8
```

### Test a Different Library

```bash
./main.sh -lib MY_LIB
```

### Custom Workspace Naming

```bash
./main.sh -ws my_ws_prefix -proj my_proj_prefix
```

### Manual Teardown After a Previous Run

```bash
# Check what teardown would do first
./main.sh -d 2 -t

# Actually tear down
./main.sh -t
```

---

## 6. Logs and Results

| Location | Content |
|----------|---------|
| `log/main.log.<timestamp>.txt` | Full execution log |
| `regression_test_NNN/` | Per-test-case directories |
| `regression_test_NNN/test_NNN/` | Individual test folder with replay file |
| `CDS_log/<uniqueid>/` | Virtuoso CDS execution logs |
| `result/<uniqueid>/` | Test result data |

### uniqueid Format

```
YYYYMMDD_HHMMSS_<user>_<libname>[_<cellname>]
```

Example: `20260422_093015_john_ESD01_FULLCHIP`

A new uniqueid is generated on every run, so results never overwrite each other.

---

## 7. Common Errors and Solutions

| Error | Cause | Solution |
|-------|-------|----------|
| `gdp list` fails | Cannot reach GDP server | Check `gdp` environment, VPN connection |
| Source library not found | Wrong `FROM_LIB` path | Verify `FROM_LIB` in `env.sh` |
| `regression_num.txt` error | File corrupted | Delete it and re-run (`rm regression_num.txt`) |
| Virtuoso execution fails | Wrong `VSE_VERSION` | Verify `VSE_VERSION` in `env.sh` |
| Some parallel jobs fail | GDP server overload | Reduce parallelism (e.g. `-j 2`) |

---

## 8. Important Notes

- **Do not `cd` into the directory before running.** `script_dir` is automatically resolved to the script's location.
- **`--max` and `--cases` cannot be used together.**
- Dry-run level 1 skips GDP/xlp4 commands — useful for testing local file operations only.
- Pressing Ctrl+C triggers the `_cleanup()` trap, which automatically cleans up the teardown worker.
