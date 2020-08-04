#!/bin/bash
set -u

# usage
# ./clean.sh test_dir_name		# default 100 MB
# ./clean.sh test_dir_name 20M	# target files > 20 MB size (Eg. 20k, 20M, 1G, etc)
# ./clean.sh test_dir_name force	# size 100 MB, delete ASCII if zip'd size > 100 MB
# ./clean.sh 'test_dir*' 20M force	# same as a, but size check 20 MB

# VARS
FORCE_STR="force"
DEFAULT_SIZE="100M"

[ $# -eq 0 ] && echo "Provide search directory" && exit 1

PATH_DIR="$1"
SIZE="$DEFAULT_SIZE"
FORCE=""

# SETUP
if [ $# -ge 2 ]
then
	if [ -n "$2" ]
	then
		if [ "$2" == "$FORCE_STR" ]
		then
			FORCE="1"
		else
			SIZE="$2"
		fi
	fi
fi

[ $# -ge 3 ] && [ "$3" == "$FORCE_STR" ] && FORCE="1"

echo -e "SEARCH DIRS: $PATH_DIR ; SIZE: $SIZE ; FORCE: $FORCE\n"

# LOGIC

for file in $(find ""$PATH_DIR"" -type f -size "+${SIZE}")
do
	if [[ "$(file "$file")" =~ "ASCII text" ]]
	then
		echo "$file is ASCII; archive it"
		gzip -v "$file"
		gzip_file="${file}.gz"
		gzip_file_dir=$(dirname "$gzip_file")
		gzip_file_name=$(basename "$gzip_file")


		gzip_file_over=$(find "$gzip_file_dir" -type f -name "$gzip_file_name" -size "+${SIZE}")
		if [ -n "$gzip_file_over" ]
		then
			if [ -n "$FORCE" ]
			then
				rm -v "$gzip_file_over"
			else
				echo "File: $gzip_file_over over $SIZE; suggest 'force' to remove it"
			fi	
		fi
	else
		rm -v "$file"
	fi
done
