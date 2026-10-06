#!/bin/bash
# check argument
if [ $# -lt 1 ]; then
	    echo "Usage: $0 <time_version> [summary_file]"
	        exit 1
	fi

	time_version="$1"
	summary_name="${2:-summary.txt}"

	logdir="result/$time_version"
	summary_file="$logdir/$summary_name"

	[ -d "$logdir" ] || { echo "Directory $logdir not found"; exit 1; }

	> "$summary_file"

	echo "Regression Summary ($time_version)" >> "$summary_file"
	echo "==================================" >> "$summary_file"
	printf "%-20s %-5s\n" "Test" "Result" >> "$summary_file"
	echo "----------------------------------" >> "$summary_file"

	pass_count=0
	fail_count=0
	total_count=0

	for logfile in "$logdir"/*.log; do
		[ -f "$logfile" ] || continue
			((total_count++))

			testname=$(basename "$logfile" .log)

			if grep -q "FAIL" "$logfile"; then
				result="FAIL"
				((fail_count++))
			else
				result="PASS"
					((pass_count++))
			fi

			printf "%-20s %-5s\n" "$testname" "$result" >> "$summary_file"
	done

	echo "" >> "$summary_file"
	echo "Total: $total_count" >> "$summary_file"
	echo "PASS : $pass_count" >> "$summary_file"
	echo "FAIL : $fail_count" >> "$summary_file"

	if [ "$fail_count" -gt 0 ]; then
		echo "" >> "$summary_file"
		echo "Fail Details:" >> "$summary_file"
		echo "----------------------------------" >> "$summary_file"

		for logfile in "$logdir"/*.log; do
			[ -f "$logfile" ] || continue
			if grep -q "FAIL" "$logfile"; then
				echo "$(basename "$logfile"):" >> "$summary_file"
				grep "FAIL" "$logfile" >> "$summary_file"
			fi
		done
	fi

	echo "Summary written to $summary_file"
