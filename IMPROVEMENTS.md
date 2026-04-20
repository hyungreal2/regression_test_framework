# CAT Framework — Improvements over Legacy

## Overview

| | Legacy (1_cico / 2_perf) | Current |
|---|---|---|
| Entry points | `init.sh`, `main.pl` (1-line scripts) | `main.sh`, `perf_main.sh` (structured bash) |
| Dry-run support | None | 3-level DRY_RUN system |
| Parallel execution | Sequential | `xargs -P` parallel |
| Path resolution | Each script resolves own path | `script_dir` exported from entry point |
| Workspace mock | None | GDP mock at DRY_RUN=1 |
| VSE environment | Hardcoded `vse_sub` | `run_vse()` wrapper — `vse_run` / `vse_sub` switchable |
| Perf workflow | Single-shot script | Session-based init / run / teardown separation |
| Workspace lookup | Fixed relative paths | `gdp find` dynamic lookup |
| Race condition | Unhandled | `flock` on `gdp build workspace` |
| GDP folder setup | Manual prerequisite | `ensure_gdp_folders()` auto-creates GDP_BASE / PERF_GDP_BASE |
| Common libraries | Not supported | `-common LIB` adds shared libraries to all test combos |
| Log management | Scattered | Centralised `log/` directory |
| Error handling | Silent failures | Fail-fast with explicit messages |

---

## 1. Script Architecture

### Legacy — each script stands alone

```
main.pl ──────────────────────────────────────────────────────┐
                                                              │ (no relationship)
init.sh   teardown.sh   summary.sh                            │
  │           │             │                                 │
  └── each resolves $(dirname $0) independently               │
      no shared env, no common logging                        │
```

### Current — entry points propagate context

```
main.sh                          perf_main.sh
  │  export script_dir              │  export script_dir
  │  source code/env.sh             │  source code/env.sh
  │  source code/common.sh          │  source code/common.sh
  │                                 │
  ├── run_single_test.sh            ├── perf_generate_replay.sh
  │     └── init.sh                ├── perf_init.sh
  ├── teardown_worker.sh            ├── perf_run_single.sh
  │     └── teardown.sh            └── perf_teardown.sh
  └── summary.sh
                    teardown_all.sh (standalone, self-resolves)
                          └── teardown.sh
```

**Key rule:** `code/*.sh` scripts cannot run standalone — they require `script_dir`
to be exported by the parent. This guarantees all paths are derived from a
single source of truth.

---

## 2. DRY_RUN System

```
DRY_RUN=2  ──  Print only (no commands executed)
               Used for: previewing, CI checks

DRY_RUN=1  ──  Skip: gdp / xlp4 / rm / vse_run / vse_sub
               Mock: gdp build/rebuild workspace
                     → creates WORKSPACES_MANAGED/<name>/
                       cds.lib, cds.libicm
                       oa/<lib>/<cell>/
                       oa/<lib>/cdsinfo.tag  (DMTYPE p4)
               Used for: local smoke test without real infra

DRY_RUN=0  ──  Run everything
               Used for: production
```

### Legacy
```
No DRY_RUN system.
Every run attempted real GDP / p4 / VSE calls.
Testing the script itself required a fully configured environment.
```

---

## 3. Parallel Execution

### Legacy
```
for lib in ${libs}; do
    init.sh $lib        # sequential
done
```

### Current — main.sh
```
tests: [1, 2, 3, ... N]
  │
  └── xargs -n1 -P4 run_single_test.sh
        ├── test_001  ─┐
        ├── test_002  ─┤ parallel (up to 4 jobs)
        ├── test_003  ─┤
        └── test_004  ─┘
```

### Current — perf_main.sh
```
combos_init: ["checkHier BM01 VP_FULLCHIP", "checkHier BM02 FULLCHIP", ...]
  │
  ├── Phase 1: generate_replays()   sequential (createReplay.pl dependency)
  │
  ├── Phase 2: init_workspaces()    xargs -n3 -P4
  │     ├── GDP create project/library  ─┐ parallel
  │     ├── gdp build workspace ─────── flock (serialised, protect table)
  │     └── MANAGED → UNMANAGED setup ──┘ parallel
  │
  └── Phase 3: run_tests()          xargs -n4 -P4
        ├── checkHier/BM01/managed    ─┐
        ├── checkHier/BM01/unmanaged  ─┤ parallel
        ├── checkHier/BM02/managed    ─┤
        └── checkHier/BM02/unmanaged  ─┘
```

---

## 4. Perf Workflow — Session-based

### Legacy (2_perf)
```
main.pl
  └── (single-shot: init → run → teardown, all or nothing)
```

### Current
```
┌─────────────────────────────────────────────────────────────┐
│  perf_session.txt                                           │
│  ─────────────────────────────────────────────────────────  │
│  20260417_120000_username           ← uniqueid (log dirs)   │
│  checkHier BM01 perf_checkHier_BM01_20260417_120000_username│
│  renameRefLib BM02 perf_renameRefLib_BM02_...               │
│  ...                                                        │
└─────────────────────────────────────────────────────────────┘

Step 1  perf_main.sh -no-run          generates replays + inits workspaces
                                      saves session file
          ↓
Step 2  perf_main.sh                  reads session → gdp find → run VSE
        perf_main.sh -lib BM01        filter by lib
        perf_main.sh -mode managed    filter by mode
          ↓  (repeatable)
Step 3  perf_main.sh -no-run -t       teardown all workspaces
                                      removes session file
```

**Workspace lookup (legacy vs current)**

| | Legacy | Current |
|---|---|---|
| MANAGED path | hardcoded relative `../../` | `gdp find --type=workspace` |
| UNMANAGED path | not supported | derived from MANAGED parent path |
| Works across sessions | ✗ | ✓ |

---

## 5. Workspace Structure (MANAGED / UNMANAGED)

```
WORKSPACES_MANAGED/<ws_name>/
  cds.lib
  cds.libicm
  oa/<lib>/<cell>/
  oa/<lib>/cdsinfo.tag      DMTYPE p4
  cdsLibMgr.il  ──symlink──► $CDS_LIB_MGR
  .cdsenv       ──symlink──► code/.cdsenv
  <testtype>_<lib>.au

WORKSPACES_UNMANAGED/<ws_name>/
  cds.lib       (= MANAGED's cds.libicm)
  oa/<lib>/<cell>/
  oa/<lib>/cdsinfo.tag      DMTYPE none   ← patched from p4
  <testtype>_<lib>.au
```

### Legacy
```
Single workspace type only.
No UNMANAGED concept.
No automatic symlink setup.
```

---

## 6. VSE Environment Abstraction

### Legacy
```bash
vse_sub -v IC25.1... -env ... -replay ... -log ...
job_id=$(...)
bwait -w "ended($job_id)"       # hardcoded, not switchable
```

### Current
```bash
# env.sh
VSE_MODE="${VSE_MODE:-run}"     # "run" or "sub"

# common.sh — run_vse()
run_vse() {
    if [[ "${VSE_MODE}" == "sub" ]]; then
        vse_out=$(vse_sub ...)
        job_id=$(...)
        # poll bjobs every 10s until DONE/EXIT
    else
        vse_run ...              # synchronous
    fi
}
```

Switch environments by changing one line in `env.sh` or at runtime:
```bash
VSE_MODE=sub perf_main.sh
```

---

## 7. Race Condition Fix — p4 Protect Table

```
Legacy: no parallel init → no conflict

Current (parallel init):
  perf_init.sh (BM01) ─┐
  perf_init.sh (BM02) ─┤─ gdp create project/library  (fully parallel ✓)
  perf_init.sh (BM03) ─┘

                        gdp build workspace (writes p4 protect table)
                          ↓
  perf_init.sh (BM01) ── flock acquire ── build ── release ─┐
  perf_init.sh (BM02) ── flock wait ──────────────────────── acquire ── build ─┐  serialised
  perf_init.sh (BM03) ── flock wait ────────────────────────────────────────── acquire ── build
```

---

## 8. Key File Changes

| File | Legacy | Current |
|---|---|---|
| `main.sh` | Deleted (missing) | Restored + structured |
| `perf_main.sh` | `main.pl` (Perl, 1-line) | Bash, session-based, phased |
| `code/common.sh` | Not present | `run_cmd()`, `run_vse()`, `_mock_gdp_workspace()`, `safe_rm_rf()` |
| `code/env.sh` | Inline per-script | Centralised, `DRY_RUN`, `VSE_MODE` |
| `code/perf_init.sh` | `ICM_createProj.sh` (basic) | MANAGED+UNMANAGED, flock, symlinks |
| `code/perf_teardown.sh` | `ICM_deleteProj.sh` | `gdp find` dynamic lookup |
| `code/perf_run_single.sh` | Not present | Dynamic workspace lookup, `run_vse()` |
| `code/teardown_worker.sh` | Not present | Background teardown queue |
| `.gitignore` | Minimal | Runtime outputs, logs, legacy/ excluded |

---

## 9. GDP Folder Auto-Setup

```
Legacy:
  GDP_BASE and PERF_GDP_BASE had to exist before running init.
  Missing folders caused opaque gdp errors.

Current — ensure_gdp_folders() in perf_main.sh:
  Before Phase 1 / Phase 2, checks each folder with gdp list.
  If not found → gdp create folder (creates it automatically).
  Skipped at DRY_RUN >= 1 (no real GDP calls).
```

---

## 10. Common Libraries (`-common`)

```
Legacy:
  No way to share a library across multiple test types.
  Each test combo was fully independent.

Current:
  perf_main.sh -common LIB1,LIB2

  checkHier/BM01 → libs: [BM01, LIB1, LIB2]
  checkHier/BM02 → libs: [BM02, LIB1, LIB2]
  renameRefLib/BM01 → libs: [BM01, BM01_ORIGIN, BM01_TARGET, LIB1, LIB2]

  Validated against PERF_LIBS at startup (same as -lib).
  Appended in perf_init.sh after perf_libs() expands the per-testtype set.
```
