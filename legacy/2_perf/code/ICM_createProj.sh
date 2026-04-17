#!/bin/bash ######################################################################
dateno=$(date +%Y%m%d_%H%M%S)
user_name=$(echo $USER)
# default value
ws_name=cadence_perf_ws_"$user_name"
proj_name=cadence_perf_"$user_name"_"$dateno"
postfix="" #
libs=(DRAMLIB BM01 BM01_CHIP BM01_COPY BM01_ORIGIN BM01_TARGET BM02 BM02_CHIP BM02_COPY BM02_ORIGIN BM02_TARGET BM03 BM03_CHIP BM03_COPY BM03_ORIGIN BM03_TARGET)
libs=(DRAMLIB BM02_CHIP BM02_TARGET)
######################################################################
while [[ $# -gt 0 ]]; do
case "$1" in -p|--postfix)
postfix=$2
shift 2 ;;
-lib|--library)
libs=$2
shift 2 ;;
-ws|--ws_name)
ws_name=$2
shift 2 ;;
-proj|--proj_name)
proj_name=$2
shift 2 ;;
*)
echo "Unknown input: $1"
exit 1 ;;

esac 
done
if [[ $postfix != "" ]];
then
ws_name="$ws_name"_"$postfix" 
fi # Check
if the project name is existed
if [[ $(gdp list /VSM/$proj_name) != "" ]];
then
echo ""
echo "****************************************************************************"
echo "The project name is existed: /VSM/$proj_name"
echo "Please use a unique project name, or add postfix argument"
echo "For example: code/ICM_createProj.sh --postfix A"
echo "****************************************************************************"
exit 1 
fi # Check
if the ws name is existed
if [[ $(gdp find --type=workspace :=$ws_name) != "" ]];
then
echo ""
echo "****************************************************************************"
echo "The workspace name is existed in : $(gdp find --type=workspace :=$ws_name)"
echo "Please use a unique workspace name, or add postfix argument"
echo "For example: code/ICM_createProj.sh --postfix A"
echo "****************************************************************************"
exit 1 
fi
gdp create project /VSM/$proj_name
gdp create variant /VSM/$proj_name/rev01
gdp create libtype /VSM/$proj_name/rev01/OA --libspec OA
gdp create config /VSM/$proj_name/rev01/dev
for lib in ${libs[@]};
do ##########################################################
## Edit here: library from name, library to name
lib_from=$lib
lib_to=$lib ##########################################################
echo Building $lib ...
gdp create library /VSM/$proj_name/rev01/OA/$lib_to --from /VSM/cadence_perf_20260317064432/rev01/OA/$lib_from --location=OA/{{library}} --columns id,name,type,path,description
gdp update /VSM/$proj_name/rev01/dev --add /VSM/$proj_name/rev01/OA/$lib_to 
done # Creating MANAGED workspace... pushd managed
echo Creating MANAGED workspace...
gdp build workspace --content /VSM/$proj_name/rev01/dev --gdp-name $ws_name --location $(realpath .) popd # Creating UNMANAGED workspace... pushd unmanaged
echo Creating UNMANAGED workspace...
cp -rf ../managed/$ws_name ./$ws_name popd
