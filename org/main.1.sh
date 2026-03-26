#!/bin/bash

set -euo pipefail

#######################################
# Global variables
#######################################
user_name="${USER}"
max=240
cases=""

ws_name="cadence_cico_ws_${user_name}"
proj_prefix="cadence_cico_${user_name}"
uniqueid_path="/tmp/uniqueid_cico_${user_name}"

libname="MS01"
cellname="XE_FULLCHIP_BASE"

#######################################
# Utility functions
#######################################

# Format number to 3 digits
format_num() {
    printf "%03d" "$1"
}

# Print error and exit
error_exit() {
    echo "Error: $1" >&2
    exit 1
}

#######################################
# Validation
#######################################
validate_inputs() {
    if [[ ${max_set:-false} == true && ${cases_set:-false} == true ]]; then
        error_exit "--max and --cases cannot be used together."
    fi

    if [[ ${max_set:-false} == true ]]; then
        [[ $max =~ ^[0-9]+$ ]] || error_exit "--max must be integer"
        (( max <= 240 )) || error_exit "--max cannot exceed 240"
    fi

    if [[ ${cases_set:-false} == true ]]; then
        [[ $cases =~ ^[0-9]+(,[0-9]+)*$ ]] || \
            error_exit "--cases format invalid (e.g. 1,2,3)"
    fi
}

#######################################
# Generate templates
#######################################
generate_templates() {
    rm -f code/date_virtuosoVer.txt

    if [[ -n "$cellname" ]]; then
        python3 code/generate_templates.py \
            --libname "$libname" \
            --cellname "$cellname"
    else
        python3 code/generate_templates.py \
            --libname "$libname"
    fi
}

#######################################
# Determine tests
#######################################
get_tests() {
    if [[ ${cases_set:-false} == true ]]; then
        IFS=',' read -ra nums <<< "$cases"

        declare -A seen=()
        tests=()

        for n in "${nums[@]}"; do
            [[ -z ${seen[$n]:-} ]] && {
                tests+=("$n")
                seen[$n]=1
            }
        done
    else
        tests=($(seq 1 "$max"))
    fi
}

#######################################
# Create regression directory
#######################################
create_regression_dir() {
    local num

    if [[ -f regression_num.txt ]]; then
        num=$(<regression_num.txt)
    else
        num="000"
    fi

    while true; do
        num=$(printf "%03d" $(( (10#$num + 1) % 1000 )))
        dir="regression_test_${num}"

        [[ ! -d "$dir" ]] && break
    done

    echo "$num" > regression_num.txt
    regression_dir="$dir"

    echo "Regression Directory: $regression_dir"
}

#######################################
# Prepare test directories
#######################################
prepare_tests() {
    for i in "${tests[@]}"; do
        num=$(format_num "$i")
        testdir="${regression_dir}/test_${num}"

        mkdir -p "$testdir"

        mv -f "./code/replay_files/replay_${num}.il" \
              "$testdir/"
    done
}

#######################################
# Run tests
#######################################
run_tests() {
    for i in "${tests[@]}"; do
        num=$(format_num "$i")
        testdir="$(pwd)/${regression_dir}/test_${num}"

        echo "Running test $num"

        (
            cd "$testdir" || exit 1

            # init
            ../../code/init.sh \
                -id "$uniqueid_path" \
                -ws "$ws_name" \
                -proj "$proj_prefix" \
                "$libname"

            source "$uniqueid_path"

            # link cdsLibMgr
            ln -s /appl/LINUX/ICM/gdpxl.latest/SKILL/cdsLibMgr.il \
                "${ws_name}_${uniqueid}"

            cd "${ws_name}_${uniqueid}"

            echo "$num" > "/tmp/CDS_PV_REG_NO_${user_name}"

            [[ -f "$uniqueid_path" ]] && source "$uniqueid_path"

            vse_sub \
                -v IC25.1.ISR5.EA010 \
                -env /user/baap/ICM/icmanage.cshrc \
                -replay "../replay_${num}.il" \
                -log "../../../CDS_log/CDS_${uniqueid}_${num}.log"
        )
    done
}

#######################################
# Main
#######################################
main() {
    validate_inputs
    generate_templates
    get_tests
    create_regression_dir
    prepare_tests
    run_tests

    echo "All tests finished."
}

main "$@"
