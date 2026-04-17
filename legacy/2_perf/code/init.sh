#!/bin/bash

######################################################################
user_name=$(echo $USER)
# default value
uniqueid_path=/tmp/uniqueid_perf_"$user_name"
ws_name=cadence_perf_ws_"$user_name"
proj_prefix=cadence_perf_"$user_name"
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

dateno=$(date +%Y%m%d%H%M%S)
export uniqueid=$dateno

echo uniqueid=$uniqueid > $uniqueid_path
proj_name=$proj_prefix$uniqueid

gdp create project /VSM/$proj_name
gdp create variant /VSM/$proj_name/rev01
gdp create libtype /VSM/$proj_name/rev01/OA --libspec OA
gdp create config /VSM/$proj_name/rev01/dev

libs=("$@")
for lib in ${libs[@]}; do
	##########################################################
	## Edit here: library from name, library to name
	lib_from=$lib
	lib_to=$lib
	##########################################################
	echo Building $lib ...
	gdp create library /VSM/$proj_name/rev01/OA/$lib_to --from /VSM/demo/rev1/OA/$lib_from --location=OA/{{library}} --columns id,name,type,path,description
	gdp update /VSM/$proj_name/rev01/dev --add /VSM/$proj_name/rev01/OA/$lib_to 

done
gdp build workspace --content /VSM/$proj_name/rev01/dev --gdp-name $ws_name --location $(realpath .)
