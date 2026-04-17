#!/bin/bash
while [[ $# -gt 0 ]]; do
case "$1" in -proj|--proj_name)
proj_name=$2
shift 2 ;;
*)
echo "Unknown option: $1"
exit 1 ;;

esac 
done # delete project on
gdp (web gui)
echo -e "\nDeleting the project /VSM/$proj_name "
gdp delete /VSM/$proj_name --recursive --force --proceed # obliterate files from depot
echo -e "\nObliterating the files from //depot/VSM/$proj_name/..."
xlp4 obliterate -y //depot/VSM/$proj_name/...
echo "done"
