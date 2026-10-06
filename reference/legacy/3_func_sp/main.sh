#!/bin/bash

show_help() {
cat << EOF
Usage: ./main.sh [OPTIONS]

Options:
    -mode MODE              Mode for the test (required)
                            Options: checkHier, renameRefLib, changeLibRef,
                                     replace, deleteAllMarkers, copyHierToEmpty,
                                     copyHierToNonEmpty

    -prefix                 Prefix case for the test (optional)	
                            Options: oo, ox, xo, xx

    -m, -min N              Minimum case number
                            (default: first line in ./code/list_<mode>)

    -M, -max N              Maximum case number
                            (default: number of lines in ./code/list_<mode>)

    -c, -cases LIST         Comma-separated case numbers.
                            Run only the specified cases;
                            duplicates will be removed.

    -ws, -ws_name NAME      Workspace name (default: cadence_func_ws)

    -proj, -proj_prefix NAME
                            Project prefix (default: cadence_func_)

    -id, -uniqueid FILE     Unique ID file (default: /tmp/uniqueid_func)

    # Mode-specific arguments:

    -lib, -libname NAME     Library name
                            (required for: checkHier, renameRefLib,
                             changeLibRef, replace, deleteAllMarkers)

    -cell, -cellname NAME   Cell name
                            (required for: checkHier, replace, deleteAllMarkers)

    -fromLib NAME           Source library name
                            (required for: renameRefLib, changeLibRef,
                             copyHierToEmpty, copyHierToNonEmpty)
                            (default "All" for changeLibRef)

    -toLib NAME             Destination library name
                            (required for: renameRefLib, changeLibRef,
                             copyHierToEmpty, copyHierToNonEmpty)

    -fromCell NAME          Source cell name
                            (required for: copyHierToEmpty, copyHierToNonEmpty)

    -h, -help               Show this help message

Examples:
    ./main.sh -mode checkHier -lib ESD01 -cell myCell
    ./main.sh -mode checkHier -prefix oo -lib ESD01 -cell myCell
    ./main.sh -mode renameRefLib -lib ESD01 -fromLib OldLib -toLib NewLib -cell myCell
    ./main.sh -mode changeLibRef -lib ESD01 -toLib NewLib -cell myCell
    ./main.sh -mode replace -lib ESD01 -cell myCell -m 20
    ./main.sh -mode deleteAllMarkers -lib ESD01 -cell myCell -c 1,3,5
    ./main.sh -mode copyHierToEmpty -fromLib SrcLib -fromCell myCell -toLib DstLib
    ./main.sh -mode copyHierToNonEmpty -fromLib SrcLib -fromCell myCell -toLib DstLib

EOF
}

set -e

# Defaults
user_name=$(echo $USER)
min=""
max=""
cases=""
ws_name=cadence_func_ws_"$user_name"
proj_prefix=cadence_func_"$user_name"
uniqueid_path=/tmp/uniqueid_func_"$user_name"
mode=""
prefix=""
libname=""
cellname=""
fromLib="All"
toLib=""
fromCell=""

min_set=false
max_set=false
cases_set=false

# ─── Parse arguments ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        -mode)
            mode=$2
            shift 2
            ;;
        -prefix)
            prefix=$2
            shift 2
            ;;
	-m|-min)
            min=$2
            min_set=true
            shift 2
            ;;
        -M|-max)
            max=$2
            max_set=true
            shift 2
            ;;
        -c|-cases)
            cases=$2
            cases_set=true
            shift 2
            ;;
        -ws|-ws_name)
            ws_name=$2
            shift 2
            ;;
        -proj|-proj_prefix)
            proj_prefix=$2
            shift 2
            ;;
        -id|-uniqueid)
            uniqueid_path=$2
            shift 2
            ;;
        -lib|-libname)
            libname=$2
            shift 2
            ;;
        -cell|-cellname)
            cellname=$2
            shift 2
            ;;
        -fromLib)
            fromLib=$2
            shift 2
            ;;
        -toLib)
            toLib=$2
            shift 2
            ;;
        -fromCell)
            fromCell=$2
            shift 2
            ;;
        -h|-help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use -h for help"
            exit 1
            ;;
    esac
done

# ─── Validate mode ────────────────────────────────────────────────────────────
valid_modes="checkHier renameRefLib changeLibRef replace deleteAllMarkers copyHierToEmpty copyHierToNonEmpty"
if [[ -z "$mode" ]]; then
    echo "Error: -mode is required."
    echo "Use -h for help"
    exit 1
fi
if ! echo "$valid_modes" | grep -qw "$mode"; then
    echo "Error: Invalid mode '$mode'."
    echo "Valid modes: $valid_modes"
    exit 1
fi

valid_prefixes=" oo ox xo xx"
if ! echo "$valid_prefixes" | grep -qw "$prefix"; then
    echo "Error: Invalid prefix '$prefix'."
    echo "Valid prefixes: $valid_prefixes"
    exit 1
fi

# ─── Validate mode-specific required arguments ────────────────────────────────
check_required() {
    local argname=$1
    local argval=$2
    if [[ -z "$argval" ]]; then
        echo "Error: $argname is required for mode '$mode'."
        exit 1
    fi
}

case "$mode" in
    checkHier)
        check_required "-lib"      "$libname"
        check_required "-cell"     "$cellname"
        ;;
    renameRefLib)
        check_required "-lib"      "$libname"
        check_required "-fromLib"  "$fromLib"
        check_required "-toLib"    "$toLib"
	check_required "-cell"     "$cellname"
        ;;
    changeLibRef)
        check_required "-lib"      "$libname"
        # -fromLib defaults to "All", so always present
        check_required "-toLib"    "$toLib"
        check_required "-cell"     "$cellname"
        ;;
    replace)
        check_required "-lib"      "$libname"
        check_required "-cell"     "$cellname"
        ;;
    deleteAllMarkers)
        check_required "-lib"      "$libname"
        check_required "-cell"     "$cellname"
        ;;
    copyHierToEmpty|copyHierToNonEmpty)
        check_required "-fromLib"  "$fromLib"
        check_required "-fromCell" "$fromCell"
        check_required "-toLib"    "$toLib"
        ;;
esac

mkdir -p temp

# ─── Save mode-specific arguments to ./temp/pv_func_args ───────────────────────
{
    echo "mode: $mode"
    case "$mode" in
        checkHier)
            echo "lib: $libname"
            echo "cell: $cellname"
            ;;
        renameRefLib)
            echo "lib: $libname"
            echo "fromLib: $fromLib"
            echo "toLib: $toLib"
	    echo "cell: $cellname"
            ;;
        changeLibRef)
            echo "lib: $libname"
            echo "fromLib: $fromLib"
            echo "toLib: $toLib"
            echo "cell: $cellname"
            ;;
        replace)
            echo "lib: $libname"
            echo "cell: $cellname"
            ;;
        deleteAllMarkers)
            echo "lib: $libname"
            echo "cell: $cellname"
            ;;
        copyHierToEmpty|copyHierToNonEmpty)
            echo "fromLib: $fromLib"
            echo "fromCell: $fromCell"
            echo "toLib: $toLib"
            ;;
    esac
} > ./temp/pv_func_args

echo "Saved arguments to ./temp/pv_func_args"

# ─── Validate mutual exclusivity of -M || -m and -c ─────────────────────────────────
if [[ $max_set == true && $cases_set == true ]]; then
    echo "Error: -max and -cases cannot be used together."
    exit 1
fi

if [[ $min_set == true && $cases_set == true ]]; then
    echo "Error: -min and -cases cannot be used together."
    exit 1
fi

# ─── Determine list file and default min/max ──────────────────────────────────────
list_file="./code/list_${mode}${prefix:+_${prefix}}"
if [[ ! -f "$list_file" ]]; then
    echo "Error: List file '$list_file' not found."
    exit 1
fi

total_lines=$(grep -c '' "$list_file")

if [[ -z "$max" ]]; then
    max=$total_lines
fi

if [[ -z "$min" ]]; then
    min=1
fi


# Compute zero-padding width from total number of lines in list file
pad_width=${#total_lines}   # e.g. 400 → 3, 40 → 2, 4000 → 4

# ─── Validate min / max ─────────────────────────────────────────────────────────────
if [[ $max_set == true ]]; then
    if ! [[ $max =~ ^[0-9]+$ ]]; then
        echo "Error: -max must be a positive integer."
        exit 1
    fi
    if (( max > total_lines )); then
        echo "Error: -max ($max) cannot be greater than the number of lines in $list_file ($total_lines)."
        exit 1
    fi
fi

if [[ $min_set == true ]]; then
    if ! [[ $min =~ ^[0-9]+$ ]]; then
        echo "Error: -min must be a positive integer."
        exit 1
    fi
    if (( min > total_lines )); then
        echo "Error: -min ($min) cannot be greater than the number of lines in $list_file ($total_lines)."
        exit 1
    fi
fi

# ─── Validate cases ───────────────────────────────────────────────────────────
if [[ $cases_set == true ]]; then
    if ! [[ $cases =~  ^[0-9,-]+$ ]]; then
        echo "Error: -cases must be comma-separated digits. e.g., 1,2,3,5-8"
        exit 1
    fi
fi

# �~T~@�~T~@� add mode in ws/project/uniqueid  �~T~@�~T~@�~T~@�~T~@�~T~@�~T~@�~T~@�~T~@�~T~@�~T~@�~T~@�~T~@�~T~@�~T~@�~T~@�~T~@�~T~@�~T~@�~T~@�~T~@�~T~@�~T~@�~T~@�~T~@�~T~@�~T~@�~T~@�~T~@�~T~@�~T~@
ws_name="$ws_name"_"$mode"
proj_prefix="$proj_prefix"_"$mode"
uniqueid_path="$uniqueid_path"_"$mode"

# ─── Step 0: remove stale date file ───────────────────────────────────────────
rm -f code/date_virtuosoVer"$mode".txt

# +@) Create template_{mode}.il
sed "s/mode *= *\"[^\"]*\"/mode = \"${mode}\"/g" ./code/template.il > ./code/template_${mode}.il


# ─── Step 1: run python script ────────────────────────────────────────────────
python3_args="--mode $mode"
[[ -n "$prefix"    ]] && python3_args+=" --prefix $prefix"
[[ -n "$libname"   ]] && python3_args+=" --libname $libname"
[[ -n "$cellname"  ]] && python3_args+=" --cellname $cellname"
[[ -n "$fromLib"   ]] && python3_args+=" --fromLib $fromLib"
[[ -n "$toLib"     ]] && python3_args+=" --toLib $toLib"
[[ -n "$fromCell"  ]] && python3_args+=" --fromCell $fromCell"

python3 code/generate_templates.py $python3_args

# ─── Step 2: create regression_test folder ────────────────────────────────────
mkdir -p regression_test/$mode

# ─── Determine which tests to run ─────────────────────────────────────────────
tests=$(seq $min $max)

if [[ $cases_set == true ]]; then
    IFS=',' read -ra parts <<< $cases

    declare -A seen
    unique=()
	for part in "${parts[@]}"; do
		if [[ $part =~ ^[0-9]+-[0-9]+$ ]]; then
			# handle range
			start=${part%-*}
			end=${part#*-}

			if (( start > end )); then
				echo "Error: invalid range $part"
				exit 1
			fi

			for ((i=start; i<=end; i++)); do
				if [[ -z ${seen[$i]} ]]; then
					unique+=("$i")
					seen[$i]=1
				fi
			done

		elif [[ $part =~ ^[0-9]+$ ]]; then
			# single number
			if [[ -z ${seen[$part]} ]]; then
				unique+=("$part")
				seen[$part]=1
			fi
		else
			echo "Error: invalid format '$part'"
			exit 1
		fi
	done

	# sort numerically
	sorted=($(printf "%s\n" "${unique[@]}" | sort -n))
	
	result=$(IFS=,; echo ${sorted[*]})
	tests=$result
fi

# ─── Prepare folders and move files ───────────────────────────────────────────
rm -rf regression_test/$mode
for i in $tests; do
    padded_num=$(printf "%0${pad_width}d" $i)
    testdir=regression_test/$mode/test_${padded_num}
    mkdir -p "$testdir"

    mv -f ./code/replay_files/replay_${padded_num}.il "$testdir/replay_${padded_num}.il"
done

# ─── Run virtuoso replay ──────────────────────────────────────────────────────
dateno=$(date +%Y%m%d%H%M%S)
echo "$dateno" > ./temp/func_date_"$user_name"_"$mode"
mkdir -p CDS_log/${mode}/${dateno}

for i in $tests; do
    padded_num=$(printf "%0${pad_width}d" $i)
    testdir=$(pwd)/regression_test/${mode}/test_${padded_num}

    echo "Running test $padded_num in $testdir"
    (
        cd "$testdir" || exit 1

        echo "Running init.sh"
        ../../../code/init.sh -id $uniqueid_path -ws $ws_name -proj $proj_prefix $libname

        echo "Copying cdsLibMgr.il to ws"
        cp ../../../code/cdsLibMgr.il $ws_name/

        echo "Getting test number and sourcing uniqueid_path"
        cd $ws_name
        echo "$padded_num" > ../../../../temp/CDS_PV_REG_NO_"$user_name"_"$mode"
        if [[ -f $uniqueid_path ]]; then
            source $uniqueid_path
        fi
        echo "Running virtuoso replay"
        virtuoso -replay ../replay_${padded_num}.il \
                 -log ../../../../CDS_log/${mode}/${dateno}/CDS_${mode}_${uniqueid}_${padded_num}.log

        echo "Deleting library and workspace"
        cd ..
        ../../../code/teardown.sh -id $uniqueid_path -ws $ws_name -proj $proj_prefix
    )
done

echo "All selected tests finished."

# Run summary.sh
date_virtuosoVer=$(cat code/date_virtuosoVer"$mode".txt)
code/summary.sh $mode/$dateno 
