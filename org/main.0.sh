#!/bin/bash
set -e

user_name=$(echo $USER)
max=240
cases=""
ws_name=cadence_cico_ws_"$user_name"
proj_prefix=cadence_cico_"$user_name"
uniqueid_path=/tmp/uniqueid_cico_"$user_name"
libname=MS01
cellname="XE_FULLCHIP_BASE"

if [[ $max_set == true && $cases_set == true ]]; then
    echo "Error: --max and --cases cannot be used together."
    exit 1
fi

# 0. remove code/date_virtuosoVer.txt
rm -f code/date_virtuosoVer.txt

# 1. run python script
if [[ $cellname == "" ]]; then
    python3 code/generate_templates.py --libname $libname
else
    python3 code/generate_templates.py --libname $libname --cellname $cellname
fi

# validate max
if [[ $max_set == true ]]; then
    if ! [[ $max =~ ^[0-9]+$ ]]; then
        echo "Error: --max must be a positive integer."
        exit 1
    fi
    if (( $max > 240 )); then
        echo "Error: --max cannot be greater than 240."
        exit 1
    fi
fi

# validate cases
if [[ $cases_set == true ]]; then
    if ! [[ $cases =~ ^[0-9]+(,[0-9]+)*$ ]]; then
        echo "Error: --cases must be comma-separated digits. e.g., 1,2,3"
        exit 1
    fi
fi

#######################################
# Determine which tests to run
#######################################
#if [[ $max_set == true ]]; then
tests=$(seq 1 $max)
#fi

# process cases
if [[ $cases_set == true ]]; then
    IFS=',' read -ra nums <<< $cases
    declare -A seen
    unique=()
    for n in ${nums[@]}; do
        if [[ -z ${seen[$n]} ]]; then
            unique+=($n)
            seen[$n]=1
        fi
    done
    result=$(IFS=,; echo ${unique[*]})
    tests=$result
fi

#######################################
# Prepare folders and move files
#######################################
if [ -f regression_num.txt ]; then
    regression_num=$(cat regression_num.txt)
    while true; do
        regression_num=$(printf "%03d\n" $(($((${regression_num}+1))%1000)))
        regression_dir="regression_test_${regression_num}"
        if [ ! -d "${regression_dir}" ]; then
            echo "Regresstion Directory: ${regression_dir}"
            break
        fi
    done
else
    regression_num="000"
    echo $regression_num > regression_num.txt
fi

for i in $tests; do
    three_digit_num=$(printf "%03d" $i)
    testdir=${regression_dir}/test_$three_digit_num
    mkdir -p $testdir
    mv -f ./code/replay_files/replay_$three_digit_num.il $testdir/replay_$three_digit_num.il
done

#######################################
# Run virtuoso replay
#######################################
for i in $tests; do
    three_digit_num=$(printf "%03d" $i)
    testdir="$(pwd)/$regression_dir/test_$three_digit_num"  # absolute path
    echo "Running test $three_digit_num in $testdir"
    (
        cd $testdir || exit 1

        # Create library and workspace
        echo Running init.sh
        ../../code/init.sh -id $uniqueid_path -ws $ws_name -proj $proj_prefix $libname
        source $uniqueid_path
        echo $uniqueid

        # Copy (ICM) cdsLibMgr.il to ws
        echo Copying cdsLibMgr.il to ws
        ln -s /appl/LINUX/ICM/gdpxl.latest/SKILL/cdsLibMgr.il ${ws_name}_${uniqueid}

        # Run virtuoso replay (Cadence Virtuoso)
        echo Getting test number and source uniqueid_path
        cd ${ws_name}_${uniqueid}
        echo "$three_digit_num" > /tmp/CDS_PV_REG_NO_"$user_name"
        if [ -f $uniqueid_path ] ; then
            source $uniqueid_path
        fi
        echo Running virtuoso replay
        vse_sub -v IC25.1.ISR5.EA010 -env /user/baap/ICM/icmanage.cshrc -replay ../replay_$three_digit_num.il -log ../../../CDS_log/CDS_$uniqueid"_"$three_digit_num".log"

        # Delete/obliterate library and workspace
    )
done

echo "All selected tests finished."
