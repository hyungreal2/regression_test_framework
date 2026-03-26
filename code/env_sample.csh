# ============================================================
# env_sample.csh
# Copy this file to env.csh and fill in your values.
#   cp code/env_sample.csh code/env.csh
# ============================================================

# User
setenv USER_NAME   "your_username"

# Naming
setenv WS_NAME     "cico_ws_your_username"
setenv PROJ_PREFIX "cico_your_username"

# Limits
setenv MAX_CASES   240

# External paths
setenv FROM_LIB    "/path/to/testProj/testVar/oa"
setenv GDP_BASE    "/path/to/CAT"

# Tool config
setenv VSE_VERSION "IC00.0.ISR0.EA000"
setenv ICM_ENV     "/path/to/icmanage.cshrc"
setenv CDS_LIB_MGR "/path/to/gdpxl/SKILL/cdsLibMgr.il"

# Dry-run level: 0=run all, 1=skip gdp/xlp4/rm/vse_sub, 2=skip all
setenv DRY_RUN     0
