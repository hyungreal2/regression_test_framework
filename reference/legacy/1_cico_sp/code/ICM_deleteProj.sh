#!/bin/bash

prefix=""

if [ -z "$1" ]; then
	echo "ERROR: Expect -proj or -prefix input provided"
	exit 1
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
	-proj|--proj_name)
	    proj_name=$2
	    shift 2
		;;
	-prefix)
	    prefix=$2
	    shift 2
		;;
    *)
	    echo "Unknown option: $1"
	    exit 1
	    ;;
    esac
done

echo prefix=$prefix
if [ "$prefix" != "" ]; then
	all_proj=$(gdp list /VSM/:project | grep ^/VSM/$prefix)

	for gdp_path in $all_proj; do
		echo $gdp_path
		var=$(gdp list $gdp_path/:variant)
		config=$(gdp list $var/:config)
		ws=$(gdp list $config/:workspace)
		if [ -z  $ws ]; then
			echo "$ws is empty, deleting"
			# delete project on gdp (web gui)
			echo -e "\nDeleting the project $gdp_path "
			gdp delete $gdp_path --recursive --force --proceed

			# obliterate files from depot
			echo -e "\nObliterating the files from //depot$gdp_path..."
			xlp4 obliterate -y //depot/VSM$gdp_path/... &
		fi
	done
	wait
else
	# delete project on gdp (web gui)
	echo -e "\nDeleting the project /VSM/$proj_name "
	gdp delete /VSM/$proj_name --recursive --force --proceed

	# obliterate files from depot
	echo -e "\nObliterating the files from //depot/VSM/$proj_name/..."
	xlp4 obliterate -y //depot/VSM/$proj_name/...

	echo "done"
fi






