#!/bin/bash

######################################################################
# default value
uniqueid_path=/tmp/uniqueid_cico
ws_name=cadence_cico_ws
proj_prefix=cadence_cico_
######################################################################

if [ $# -le 0 ]
then
    echo "Usage: $0 <libname> [<libname>...]"
    echo "Usage: $0 -id <uniqueid file path> --ws_name <workspace name> --proj_prefix <proj prefix> <libname> [<libname>...]"
    exit 1
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        -ws|--ws_name)
            ws_name=$2
            shift 2
            ;;
        -proj|--proj_prefix)
            proj_prefix=$2
            shift 2
            ;;
        -id|--uniqueid)
            uniqueid_path=$2
            shift 2
            ;;
        -*)
            echo "Unknown option: $1"
            exit 1
            ;;
        *)
            break
            ;;
    esac
done

dateno=$(date +%Y%m%d_%H%M%S)
export uniqueid=$dateno
echo uniqueid=$uniqueid > $uniqueid_path

proj_name="${proj_prefix}_${uniqueid}"
CONFIG=/MEMORY/TEST/CAT/$proj_name/rev01/dev
from_lib="/MEMORY/TEST/testProj/testVar/oa"

gdp create project --user=gdpxl_manager /MEMORY/TEST/CAT/$proj_name
gdp assign role --user=gdpxl_manager /MEMORY/TEST/CAT/$proj_name $(echo $USER) projman
gdp create variant /MEMORY/TEST/CAT/$proj_name/rev01
gdp create libtype /MEMORY/TEST/CAT/$proj_name/rev01/oa --libspec oa
gdp create config $CONFIG

libs=("$@")
for lib in ${libs[@]}; do
    ##########################################################
    ## Edit here: library from name, library to name
    lib_from=$lib
    lib_to=$lib
    OA_LIB=/MEMORY/TEST/CAT/$proj_name/rev01/oa/$lib_to
    ##########################################################
    echo Building $lib ...
    gdp create library $OA_LIB --from $from_lib/$lib_from --columns id,name,type,path,description
    gdp update $CONFIG --add $OA_LIB
done

gdp build workspace --content $CONFIG --gdp-name ${ws_name}_${uniqueid}
