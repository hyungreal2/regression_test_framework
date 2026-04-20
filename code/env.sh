#!/bin/bash

#######################################
# Global environment config
#######################################

# User
USER_NAME="${USER}"

# Naming
WS_PREFIX="cico_ws_${USER_NAME}"
PROJ_PREFIX="cico_${USER_NAME}"

# Test targets
LIBNAME="ESD01"
CELLNAME="FULLCHIP"

# Limits
MAX_CASES=256

# External paths
FROM_LIB="/MEMORY/TEST/CAT/CAT_LIB/TEST_PRJ/rev1/oa"
GDP_BASE="/MEMORY/TEST/CAT/CAT_WORKING/${USER_NAME}"
CICO_GDP_BASE="${GDP_BASE}/cico"

# Tool config
#VSE_VERSION="IC25.1.ISR5.EA010"
VSE_VERSION="IC251_ISR5-023_CAT"
ICM_ENV="/user/baap/ICM/icmanage.cshrc"
CDS_LIB_MGR="/appl/LINUX/ICM/gdpxl.latest/SKILL/cdsLibMgr.il"

# Dry-run level: 0=run all, 1=skip gdp/xlp4/rm, 2=skip all
DRY_RUN=${DRY_RUN:-0}

# VSE execution mode: "run" (vse_run, synchronous) or "sub" (vse_sub + bwait)
VSE_MODE="${VSE_MODE:-run}"

#######################################
# Perf test config
#######################################
PERF_PREFIX="perf"
PERF_GDP_BASE="${GDP_BASE}/perf"
PERF_LIBS=(BM01 BM02 BM03)
PERF_CELLS=(VP_FULLCHIP FULLCHIP XE_FULLCHIP_BASE)
PERF_TESTS=(checkHier renameRefLib replace deleteAllMarker copyHierToEmpty copyHierToNonEmpty)
