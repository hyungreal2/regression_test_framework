#!/bin/bash

if [ -z "$1" ]; then
    echo "Usage: $0 <folder name> "
    exit 1
fi

foldername=$1
target_dir=./result/$foldername
summary_file=$target_dir/summary.txt

if [ ! -d $target_dir ]; then
    echo "Error: Folder $target_dir does not exist"
    exit 1
fi

> $summary_file

for file in "$target_dir"/*; do
    if [ $(basename "$file") = "summary.txt" ]; then
	continue
    fi

    if [ -f $file ]; then
	echo $(basename $file) >> $summary_file # write log file name
	cat $file >> $summary_file # write log file content
	echo " " >> "$summary_file" # write new line
    fi
done

echo Summary genereated at $summary_file
