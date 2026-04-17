#!/bin/bash show_help() {
    cat << EOF Usage: ./main.sh [OPTIONS] Options: -m, --max N Maximum
case number (default: 256) -c, --cases LIST Comma-separated
case numbers. Available - (hyphen)
for range of
case numbers Run only the specify cases, and the duplicate cases will be removed. -ws, --ws_name NAME Workspace name (default: cadence_cico_ws_<USERNAME>_<TIME>) -proj, --proj_name NAME Project name (default: cadence_cico_<USERNAME>_<TIME>) -lib, --libname NAME Library name (default: ESD01) -cell, --cellname NAME Cell name (check code/Flat_list or code/Hierarchical_List) If this argument is defined, it will ignore the above files and only run on the assigned cell. -debug Enable debugMode will not delete replay_files and regression_test folder -h, --help Show this help message Example: ./main.sh -lib lib1 -cell top ./main.sh ./main.sh -m 20 ./main.sh -c 1,3,5,7,10-15 ./main.sh --ws_name test_ws --proj_prefix demo -debug EOF
} set -e
dateno=$(date +%Y%m%d_%H%M%S)
user_name=$(echo $USER) debugMode=false max=256 cases=""
ws_name=cadence_cico_ws_"$user_name"_"$dateno"
proj_name=cadence_cico_"$user_name"_"$dateno" regression_test_name=regression_test_"$user_name"_"$dateno" libname=ESD01 cellname=FULLCHIP # pre. collect all the input args
while [[ $# -gt 0 ]]; do
case "$1" in -m|--max) max=$2 max_set=true
shift 2 ;;
-c|--cases) cases=$2 cases_set=true
shift 2 ;;
-ws|--ws_name)
ws_name=$2
shift 2 ;;
-proj|--proj_name)
proj_name=$2
shift 2 ;;
-lib|--libname) libname=$2
shift 2 ;;
-cell|--cellname) cellname=$2
shift 2 ;;
-debug) debugMode=true
shift 1 ;;
-h|--help) show_help
exit 0 ;;
*)
echo "Unknown option: $1"
echo "Use -h
for help"
exit 1 ;;

esac 
done
if [[ $max_set == true && $cases_set == true ]];
then
echo "Error: --max and --cases cannot be used together."
exit 1 
fi uniqueid="$dateno"_"$user_name"_"$libname"_"$cellname" replays_folder=replay_files_$uniqueid # 0. remove replay folder
rm -rf code/$replays_folder # 1. run python script
if [[ $cellname == "" ]];
then python3 code/generate_templates.py --result_folder $uniqueid --libname $libname --results $replays_folder
else python3 code/generate_templates.py --result_folder $uniqueid --libname $libname --cellname $cellname --results $replays_folder 
fi # validate max
if [[ $max_set == true ]];
then
if ! [[ $max =~ ^[0-9]+$ ]];
then
echo "Error: --max must be a positive integer."
exit 1 
fi
if (( $max > 256 ));
then
echo "Error: --max cannot be greater than 256."
exit 1 
fi 
fi # validate cases
if [[ $cases_set == true ]];
then
if ! [[ $cases =~ ^[0-9,-]+$ ]];
then
echo "Error: --cases must be comma-separated digits. e.g., 1,2,3"
exit 1 
fi 
fi #######################################
# Determine which tests to run ####################################### #if [[ $max_set == true ]];
then tests=$(seq 1 $max)
#
fi # process cases
if [[ $cases_set == true ]];
then IFS=',' read -ra parts <<< $cases declare -A seen unique=()
for part in "${parts[@]}"; do
if [[ $part =~ ^[0-9]+-[0-9]+$ ]];
then # handle range start=${part%-*} end=${part#*-}
if (( start > end ));
then
echo "Error: invalid range $part"
exit 1 
fi
for ((i=start; i<=end; i++)); do
if [[ -z ${seen[$i]} ]];
then unique+=("$i") seen[$i]=1 
fi 
done
elif [[ $part =~ ^[0-9]+$ ]];
then # single number
if [[ -z ${seen[$part]} ]];
then unique+=("$part") seen[$part]=1 
fi
else
echo "Error: invalid format '$part'"
exit 1 
fi 
done # sort numerically sorted=($(printf "%s\n" "${unique[@]}" | sort -n)) result=$(IFS=,;
echo ${sorted[*]}) tests=$result 
fi #######################################
# Prepare folders and move files #######################################
mkdir -p CDS_log/$uniqueid
rm -rf "$regression_test_name"
for i in $tests;
do three_digit_num=$(printf "%03d" $i) testdir="$regression_test_name"/test_$three_digit_num
mkdir -p $testdir
cp -f ./code/$replays_folder/replay_$three_digit_num.il $testdir/replay_$three_digit_num.il 
done #######################################
# Run virtuoso replay #######################################
for i in $tests;
do three_digit_num=$(printf "%03d" $i) testdir=$(pwd)/"$regression_test_name"/test_$three_digit_num # absolute path
echo "Running test $three_digit_num in $testdir" ( cd $testdir ||
exit 1 # Create library and workspace
echo Running init.sh ../../code/init.sh -ws $ws_name -proj $proj_name $libname || true # Copy (ICM) cdsLibMgr.il & .cdsenv to ws
echo Copying cdsLibMgr.il to ws
cp ../../code/cdsLibMgr.il $ws_name/
cp ../../code/.cdsenv $ws_name/
# Run virtuoso replay (Cadence Virtuoso)
echo Getting test number cd $ws_name
echo Running virtuoso replay virtuoso -replay ../replay_$three_digit_num.il -log ../../../CDS_log/$uniqueid/CDS_$three_digit_num".log" || true # Delete/obliterate library and workspace
echo Deleting library and workspace cd .. ../../code/teardown.sh -ws $ws_name -proj $proj_name ) 
done
echo "All selected tests finished." # Removing tmp files
if [[ $debugMode == true ]];
then
echo ""
echo "*****************************************************************"
echo "Debug mode is enabled. $regression_test_name and code/$replays_folder folders are NOT deleted."
echo "Remove manually by:"
echo "rm -rf $(pwd)/$regression_test_name"
echo "rm -rf $(pwd)/$code/$replays_folder"
echo "*****************************************************************"
echo ""
else
echo "Removing $regression_test_name folder"
rm -rf $regression_test_name || true
rm -rf code/$replays_folder || true # Deleting CDS_log folder
if it is older than 1 day.
#
echo "" # find CDS_log -mindepth 1 -maxdepth 1 -type d -mtime +1 |
while read -r folder;
do #
echo " Deleting folder '$folder' because it is older than 1 day." #
rm -rf "$folder" # 
done #
echo "" 
fi # Run summary.sh code/summary.sh $uniqueid
