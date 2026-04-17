#!/bin/bash

#############################################################

user_name=$(echo $USER)
## Edit default value: uniqueid file ##
uniqueid_path=/tmp/uniqueid_perf_"$user_name"


## Edit default value: workspace name, proj_prefix, project_name ##
ws_name=cadence_perf_ws_"$user_name"
proj_prefix=cadence_perf_"$user_name"

#############################################################

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
    	*)
	    echo "Unknown option: $1"
	    exit 1
	    ;;
    esac
done



if [ -f $uniqueid_path ] ; then
    source $uniqueid_path
fi

project_name=$proj_prefix$uniqueid
project_depot_path=//depot/VSM/$project_name/...
ws_gdp_path=$(gdp find --type=workspace :=$ws_name)
ws_local_path=$(gdp list $ws_gdp_path --columns=rootDir)
echo -e "\nWorkspace local path: $ws_local_path"

# collect original path
pushd $(pwd)

# revert all opened files
cd $ws_local_path
echo -e "\nReverting all opened files: $project_depot_path"
xlp4 -c $ws_name revert $project_depot_path > /tmp/null_"$user_name"

# go to one dir before the ws
cd ..

# delete workspace on gdp
echo -e "\nDeleting workspace on gdpxl: $ws_name"
gdp delete workspace --leave-files --force --name $ws_name 

# delete workspace on local machine
echo -e "\nRemoving workspace on local: $ws_local_path"
chmod -R 777 $ws_local_path/.gdpxl
rm -rf $ws_local_path

# delete project on gdp (web gui)
echo -e "\nDeleting the project /VSM/$project_name "
gdp delete /VSM/$project_name --recursive --force --proceed

# obliterate files from depot
echo -e "\nObliterating the files from //depot/VSM/$project_name/..."
xlp4 obliterate -y //depot/VSM/$project_name/... > /tmp/null_"$user_name"

# back to original path
popd
