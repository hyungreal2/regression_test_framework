# archive

Files that ship in the prod deployments (or were kept from them) but that no
entry script, replay template or loaded SKILL file uses. They stay in the repo
for reference and are never deployed: `deploy.sh` only copies `suites/<suite>/`.

| File | Why it is unused |
|---|---|
| `perf/code/copyHierToEmpty_revertICM.il` | The `copyHierToEmpty` template keeps its `load` commented out |
| `perf/code/changeRefLib_revertICM.il_mcr` | The `changeLibRef` template loads the `_mcr_modified` version |
| `perf/GenerateReplayScript/lib_cell_view.txt` | `createReplay.pl` reads it only without `-lib`; `perf_generate_replay.sh` always passes `-lib` |
| `perf/GenerateReplayScript/loop.pl` | Manual helper, not called |
| `func/code/cdsLibMgr.il` | Workspaces link `CDS_LIB_MGR` from `env.sh`, not this file |
| `func/code/list_changeRefLib*` | `changeRefLib` is not a valid `func_main.sh -mode` (renamed to `changeLibRef`) |
| `func/code/func_control_260602`, `func_control_real`, `validate.il.260602` | Backups of earlier prod versions |
