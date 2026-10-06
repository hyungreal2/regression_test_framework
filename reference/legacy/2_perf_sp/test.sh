#!/bin/bash

prefix="cadence_func"

all_proj=$(gdp list /VSM/:project | grep ^/VSM/$prefix)
echo $a
for gdp_path in $all_proj; do
    echo $gdp_path
    var=$(gdp list $gdp_path/:variant)
    config=$(gdp list $var/:config)
    ws=$(gdp list $config/:workspace)
    if [ -z  $ws ]; then
        echo "$ws is empty"
    fi
done