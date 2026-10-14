#!/bin/bash

#######################################
# Global environment config
#######################################

# User
USER_NAME="${USER:-$(id -un)}"

# Naming
# Overrides use framework-specific names (CAT_*), so an unrelated
# WS_PREFIX / VSE_VERSION exported in the shell is never picked up.
WS_PREFIX="${CAT_WS_PREFIX:-cico_ws_${USER_NAME}}"
PROJ_PREFIX="${CAT_PROJ_PREFIX:-cico_${USER_NAME}}"

# Test targets
LIBNAME="ESD01"
CELLNAME="FULLCHIP"

# Limits
MAX_CASES=144

# External paths
FROM_LIB="/MEMORY/TEST/CAT/CAT_LIB/TEST_PRJ/rev1/oa"
GDP_BASE="/MEMORY/TEST/CAT/CAT_WORKING/${USER_NAME}"
CICO_GDP_BASE="${GDP_BASE}/cico"

# Tool config
VSE_VERSION="${CAT_VSE_VERSION:-IC251SM_ISR8_003-260902}"
ICM_ENV="/user/baap/ICM/icmanage.cshrc"
CDS_LIB_MGR="/appl/LINUX/ICM/gdpxl.latest/SKILL/cdsLibMgr.il"

# gdp create project retries (sleeps 10 s after each attempt -> up to ~50 s by default)
GDP_PROJ_MAX_ATTEMPTS=${GDP_PROJ_MAX_ATTEMPTS:-5}

# Dry-run level: 0=run all, 1=skip gdp/xlp4/rm, 2=skip all
DRY_RUN=${DRY_RUN:-0}

# Maximum parallel jobs (hard cap applied to -j)
MAX_JOBS=${MAX_JOBS:-32}

# VSE execution mode: "run" (vse_run, synchronous) or "sub" (vse_sub + bwait)
VSE_MODE="${VSE_MODE:-run}"
# VSE_MODE=sub: bjobs (and its LSF config) used to poll the submitted job
VSE_SUB_LSF_ENVDIR="/user/mcr1spool/lsfmcr1/conf"
VSE_SUB_BJOBS="/user/mcr1spool/lsfmcr1/10.1/linux3.10-glibc2.17-x86_64/bin/bjobs"

# Virtual X display (Xvfb) for vse_run: replays use functions that need a GUI,
# so Virtuoso runs on a per-suite display instead of with -nograph
CICO_DISPLAY=97
PERF_DISPLAY=98
FUNC_DISPLAY=99
XVFB_SCREEN="1920x1080x24"
USE_XVFB=1                      # 0 (-no-xvfb): no Xvfb; vse_run uses the caller's DISPLAY

#######################################
# Functional test config
#######################################
FUNC_WS_PREFIX="${CAT_FUNC_WS_PREFIX:-func_ws_${USER_NAME}}"
FUNC_PROJ_PREFIX="${CAT_FUNC_PROJ_PREFIX:-func_${USER_NAME}}"
FUNC_GDP_BASE="${GDP_BASE}/func"

#######################################
# Perf test config
#######################################
PERF_PREFIX="perf"
PERF_GDP_BASE="${GDP_BASE}/perf"
PERF_LIBS=(BM01 BM02 BM03 MEMGEN5K)
PERF_CELLS=(VP_FULLCHIP FULLCHIP XE_FULLCHIP_BASE test)
PERF_TESTS=(checkHier renameRefLib changeLibRef replace deleteAllMarker copyHierToEmpty copyHierToNonEmpty)  # order = Test<N> number in the replay templates
PERF_BASE_LIBS=(DRAMLIB)        # added to every perf workspace (legacy's single workspace always had it)
PERF_PRISTINE_OA=".oa_pristine" # UNMANAGED: untouched copy of oa/, restored before every run
PERF_INIT_CL=".init_cl"         # MANAGED: changelist the workspace held right after init (rollback target)
PERF_CLEAN_CL=".clean_cl"       # MANAGED: newest changelist at which the depot equals the init state
