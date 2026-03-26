#!/bin/bash

#######################################
# Global environment config
#######################################

# User
USER_NAME="${USER}"

# Base paths
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Naming
WS_NAME="cico_ws_${USER_NAME}"
PROJ_PREFIX="cico_${USER_NAME}"

# Limits
MAX_CASES=240

# External paths
FROM_LIB="/MEMORY/TEST/testProj/testVar/oa"
GDP_BASE="/MEMORY/TEST/CAT"

# Tool config
VSE_VERSION="IC25.1.ISR5.EA010"
ICM_ENV="/user/baap/ICM/icmanage.cshrc"
CDS_LIB_MGR="/appl/LINUX/ICM/gdpxl.latest/SKILL/cdsLibMgr.il"

# Dry-run level: 0=run all, 1=skip gdp/xlp4/rm, 2=skip all
DRY_RUN=${DRY_RUN:-0}
