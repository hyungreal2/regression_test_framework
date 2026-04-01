#!/bin/bash

# ============================================================
# env_sample.sh
# Copy this file to env.sh and fill in your values.
#   cp code/env_sample.sh code/env.sh
# ============================================================

# User
USER_NAME="${USER}"

# Naming
WS_PREFIX="cico_ws_${USER_NAME}"
PROJ_PREFIX="cico_${USER_NAME}"

# Test targets
LIBNAME="YOUR_LIBNAME"
CELLNAME="YOUR_CELLNAME"

# Limits
MAX_CASES=240

# External paths
FROM_LIB="/path/to/testProj/testVar/oa"
GDP_BASE="/path/to/CAT"

# Tool config
VSE_VERSION="IC00.0.ISR0.EA000"
ICM_ENV="/path/to/icmanage.cshrc"
CDS_LIB_MGR="/path/to/gdpxl/SKILL/cdsLibMgr.il"

# Dry-run level: 0=run all, 1=skip gdp/xlp4/rm/vse_sub/vse_run/bwait, 2=skip all
DRY_RUN=${DRY_RUN:-0}
