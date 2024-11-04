#!/bin/bash

# duscr - the Dziennik Ustaw SCRaper
# Copyright (C) 2024 adameus03 <amad.sitnicki@v2024.pl>.
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

### === EXTERNALS DESCRIPTION ===
## Arguments
# $1 - mode, one of the following options:
#     init - downloads everything starting from 1944 and ending today
#     sync - checks for new stuff and updates the dataset if needed
# $2 - data directory path
# $3 - log file path
# $4 - stdout logs flag (1 or 0)


### === INTERNALS DESCRIPTION ===
## Formats
# 2012 - 2024 - new format (F02)
# 1944 - 2011 - old format (F01)

# BASE_URL https://dziennikustaw.gov.pl/DU/rok/<YYYY> (both formats F01 and F02)

# target elements: #c_table > tbody > tr > a
# target attribute: href
# target path: "${BASE_URL}<target attribute value>"

BASE_URL='https://dziennikustaw.gov.pl/DU/rok'; # to obtain list
BASE_URL_DIRECT='https://dziennikustaw.gov.pl'; # to avoid redirections when downloading pdf
CURRENT_YEAR=$(date +%Y); # so that we now when to stop scraping
FIRST_YEAR=1944;
#FIRST_YEAR=2023;
FIRST_YEAR_F01="$FIRST_YEAR";
FIRST_YEAR_F02=2012;
DUSCR_DIR_RELPATH=".duscr";
DUSCR_HEADPOINT_RELPATH="headpoint";

# $1 - URL
# $2 - headpoint save flag
# $3 - sync check flag
# $4 - old headpoint
# $5 - log file path
# $6 - stdout logs flag (1 or 0)
function duscr_bulk_download() {
    BULK_DOWNLOAD_URL=$1;
    HEADPOINT_SAVE_FLAG=$2;
    SYNC_CHECK_FLAG=$3;
    OLD_HEADPOINT=$4;
    LOG_FILE_PATH=$5;
    STDOUT_LOGS_FLAG=$6;

    #echo "SYNC_CHECK_FLAG = $SYNC_CHECK_FLAG";

    while read relpath; do	
        if [ "$HEADPOINT_SAVE_FLAG" = "1" ]; then
            # save the headpoint to .duscr/headpoint
	    HEADPOINT_PDF_RELPATH=$(echo $relpath | awk -F '/' '{print $5}');
	    echo "${HEADPOINT_PDF_RELPATH:1:-4}" > "$DUSCR_DIR_RELPATH/$DUSCR_HEADPOINT_RELPATH" || (echo "Failed to write to $DUSCR_HEADPOINT_RELPATH" >> "$LOG_FILE_PATH"; exit 1);
	    if [ "$STDOUT_LOGS_FLAG" = "1" ]; then	
	        echo "${HEADPOINT_PDF_RELPATH:1:-4}";
	    fi;
	    HEADPOINT_SAVE_FLAG=0;
        fi;
	if [ "$SYNC_CHECK_FLAG" = "0" ]; then
	    until wget -q "$BASE_URL_DIRECT/$relpath"; do sleep 5; done;
        elif [ "$SYNC_CHECK_FLAG" = "1" ]; then
            CURRPOINT_PDF_RELPATH=$(echo $relpath | awk -F '/' '{print $5}');
	    if [[ "${CURRPOINT_PDF_RELPATH:1:-4}" > "$OLD_HEADPOINT" ]]; then
		echo "Sync: adding $relpath" >> "$LOG_FILE_PATH";
                if [ "$STDOUT_LOGS_FLAG" = "1" ]; then	    
		    echo "Sync: adding $relpath";
		fi;
		until wget -q "$BASE_URL_DIRECT/$relpath"; do sleep 5; done;
	    fi;
	else
	    echo "Invalid SYNC_CHECK_FLAG. Quit" >> "$LOG_FILE_PATH"; 
            if [ "$STDOUT_LOGS_FLAG" = "1" ]; then    
		echo "Invalid SYNC_CHECK_FLAG. Quit"; 
	    fi;
	    exit 1; # TODO FIXME
	fi;
    done < <(until curl -s "$BULK_DOWNLOAD_URL"; do sleep 5; done | pup '#c_table tbody tr a' | sed -n 's/.*href=\"\([^"]*\)".*/\1/p' | grep .pdf);
    echo $HEADPOINT_SAVE_FLAG;
}

# $1 - YYYY
# $2 - journalno
# $3 - log file path
# $4 - stdout logs flag (1 or 0)
function duscr_journal_scrap() {
    YYYY=$1;
    JOURNALNO=$2;
    LOG_FILE_PATH=$3;
    STDOUT_LOGS_FLAG=$4;
    duscr_bulk_download "$BASE_URL/$YYYY/wydanie/$JOURNALNO" 0 0 0 "$LOG_FILE_PATH" "$STDOUT_LOGS_FLAG" > /dev/null; 
}

# $1 - YYYY
# $2 - sync flag
# $3 - log file path
# $4 - stdout logs flag (1 or 0)
function duscr_year_scrap() {
    YYYY=$1;
    SYNC_FLAG=$2;
    LOG_FILE_PATH=$3;
    STDOUT_LOGS_FLAG=$4;
    HEADPOINT_SAVE_FLAG=0;
    HEADPOINT_OLD=0;
    if [ "$YYYY" = "$CURRENT_YEAR" ]; then
        HEADPOINT_SAVE_FLAG=1;
    fi;
    if [ "$SYNC_FLAG" = "1" ]; then
	if [ ! -f "$DUSCR_DIR_RELPATH/$DUSCR_HEADPOINT_RELPATH" ]; then
		echo "Sync: missing headpoint! The duscr scraping data directory was not initialized correctly (interrupted download process?). You need to empty the directory '$DATA_DIR' (or choose a different one) and then run 'duscr init <directory_path>'. Quit" >> $LOG_FILE_PATH;
		if [ "$STDOUT_LOGS_FLAG" = "1" ]; then    
		    echo "Sync: missing headpoint! The duscr scraping data directory was not initialized correctly (interrupted download process?). You need to empty the directory '$DATA_DIR' (or choose a different one) and then run 'duscr init <directory_path>'. Quit";
		fi;
	    exit 1;
        fi;
	HEADPOINT_OLD=$(cat "$DUSCR_DIR_RELPATH/$DUSCR_HEADPOINT_RELPATH");
    fi;

    if [ "$YYYY" -gt "$CURRENT_YEAR" ]; then
        echo "Invalid attempt to scrap the future. Quit";
	exit 1;
    elif [ "$YYYY" -ge "$FIRST_YEAR_F02" ]; then
	#echo "[dbg] LOG_FILE_PATH=$LOG_FILE_PATH";
        echo -n "Scraping year $YYYY... " >> "$LOG_FILE_PATH";    
	if [ "$STDOUT_LOGS_FLAG" = "1" ]; then
	    echo -n "Scraping year $YYYY...";
	fi;
	#echo "[dbg] SYNC_FLAG = $SYNC_FLAG";
	HEADPOINT_SAVE_FLAG=$(duscr_bulk_download "$BASE_URL/$YYYY" "$HEADPOINT_SAVE_FLAG" "$SYNC_FLAG" "$HEADPOINT_OLD" "$LOG_FILE_PATH" "$STDOUT_LOGS_FLAG");
	echo "Done" >> "$LOG_FILE_PATH";
	if [ "$STDOUT_LOGS_FLAG" = "1" ]; then
	    echo "Done";
	fi;
    elif [ "$YYYY" -ge "$FIRST_YEAR_F01" ]; then
	# Scan through the available journals
	echo "Processing journal list for year $YYYY" >> "$LOG_FILE_PATH";
	if [ "$STDOUT_LOGS_FLAG" = "1" ]; then
	    echo "Processing journal list for year $YYYY";
	fi;
	JOURNALNO_MAX_SET_FLAG=1;
	JOURNALNO_MAX=0;
        while read journalno; do
	    if [ "$JOURNALNO_MAX_SET_FLAG" = "1" ]; then
	        JOURNALNO_MAX="$journalno";
		JOURNALNO_MAX_SET_FLAG=0;
		echo "Number of journals: $JOURNALNO_MAX" >> "$LOG_FILE_PATH";
		if [ "$STDOUT_LOGS_FLAG" = "1" ]; then
		    echo "Number of journals: $JOURNALNO_MAX";
		fi;
	    fi;
	    PROGRESSBAR_PROGRESS=$(( $JOURNALNO_MAX - $journalno + 1 )); 
	    progressbar  "Scraping year $YYYY, journal $journalno... " $PROGRESSBAR_PROGRESS $JOURNALNO_MAX;
	    duscr_journal_scrap "$YYYY" "$journalno" "$LOG_FILE_PATH" "$STDOUT_LOGS_FLAG";
        done < <(until curl -s "$BASE_URL/$YYYY"; do sleep 5; done | pup '#c_table tbody tr td.numberAlign a' | sed -n 's/.*href=\"\([^"]*\)".*/\1/p' | grep wydanie | awk -F '/' '{print $6}');	
    else
        echo "Invalid attempt to scrap distant past before $FIRST_YEAR_F01" >> "$STDOUT_LOGS_FLAG";
	if [ "$STDOUT_LOGS_FLAG" = "1" ]; then    
            echo "Invalid attempt to scrap distant past before $FIRST_YEAR_F01";
	fi;
	exit 1;
    fi;
}


# $1 - mode option
# $2 - data directory path
# $3 - log file path
# $4 - stdout logs flag
function duscr_arg_common_sanity_checks() {
    MODE=$1;
    DATA_DIR=$2;
    LOG_FILE_PATH=$3;
    STDOUT_LOGS_FLAG=$4;
    if [ ! -d $DATA_DIR ]; then
        echo "The provided directory \"$DATA_DIR\" doesn't exist!";
	exit 1;
    fi;
    if [ "$DATA_DIR" = "" ]; then
        echo "Missing data directory path as second argument";
	exit 1;
    fi;
    if [ "$LOG_FILE_PATH" = "" ]; then
        echo "Missing log file path as third argument";
	exit 1;
    fi;
    if [ -d "$LOG_FILE_PATH" ]; then
       echo "$LOG_FILE_PATH is a directory";
       exit 1;
    fi;
    if [ "$STDOUT_LOGS_FLAG" = "" ]; then
        echo "Missing stdout_logs_flag as fourth argument";
	exit 1;
    fi;
    if [[ ! "$STDOUT_LOGS_FLAG" =~ ^[01]$ ]]; then 
        echo "Invalid value of fourth argument: stdout_logs_flag should be either '0' or '1'";
	exit 1;
    fi;
}

# $1 - mode option
# $2 - data directory path
# $3 - log file path
# $4 - stdout logs flag (1 or 0)
function duscr_args_handler() {
    MODE=$1;
    DATA_DIR=$2;
    LOG_FILE_PATH=$3;
    STDOUT_LOGS_FLAG=$4;
    case $MODE in
        init)
	    duscr_arg_common_sanity_checks $MODE "$DATA_DIR" "$LOG_FILE_PATH" "$STDOUT_LOGS_FLAG";
	    LOG_FILE_PATH="$(realpath "$LOG_FILE_PATH")";
	    cd $DATA_DIR || (echo "Failed to cd $DATA_DIR"; exit 1);
	    # check if .duscr exists
	    if [ -d "$DUSCR_DIR_RELPATH" ]; then
	        echo "$DATA_DIR already is a duscr initialized directory. Quit.";
	        exit 1;
	    fi;
	    if [ ! -z "$( ls -A . )" ]; then
		read -p "$DATA_DIR is a non-empty directory. Are you sure you want to use it instead of an empty directory? " -n 1 -r
                echo;
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
		    echo "Exiting";
                    exit 1;
                fi;
	    fi;
            
	    # Create .duscr
            mkdir "$DUSCR_DIR_RELPATH";
            
            # download everything starting from 1944 and ending CURRENT_YEAR
	    for year in $(seq $FIRST_YEAR $CURRENT_YEAR);
	    do
		#echo "[dbg1] LOG_FILE_PATH = $LOG_FILE_PATH";
	        duscr_year_scrap "$year" 0 "$LOG_FILE_PATH" "$STDOUT_LOGS_FLAG"; 
	    done;
	    cd - > /dev/null || (echo  "Failed to cd -"; exit 1);	    
	    ;;
        sync)
	    # check for new stuff and update the dataset if needed
	    duscr_arg_common_sanity_checks $MODE "$DATA_DIR" "$LOG_FILE_PATH" "$STDOUT_LOGS_FLAG";
	    LOG_FILE_PATH="$(realpath "$LOG_FILE_PATH")";
	    cd $DATA_DIR || (echo "Failed to cd $DATA_DIR"; exit 1);
	    # check if .duscr doesn't exist
	    if [ ! -d "$DUSCR_DIR_RELPATH" ]; then
                echo "$DATA_DIR is not a duscr data directory. Use 'duscr init <directory_path>' to initialize a duscr scraping data directory. Quit";
		exit 1;
	    fi;
	    # sync (check for any new acts available)"
	    duscr_year_scrap "$CURRENT_YEAR" 1 "$LOG_FILE_PATH" "$STDOUT_LOGS_FLAG";
	    cd - > /dev/null || (echo "Failed to cd -"; exit 1); 
	    ;;
        *)
	    echo "------ duscr (the Dziennik Ustaw SCRaper)------";
            echo "Usage: duscr.sh [mode] [data_dir] [log_file] [stdout_logs_flag]";
	    echo "    mode - one of the following options:";
	    echo "        init - downloads everything starting from 1944 and ending today";
	    echo "        sync - checks for new stuff and updates the dataset if needed";
	    echo "    stdout_logs_flag - one of the following values:";
	    echo "        0 - stdout logs disabled";
	    echo "        1 - stdout logs enabled";
	    ;;
    esac;
	   
}

source progressbar.sh || (echo "Missing progressbar.sh script from https://github.com/roddhjav/progressbar"; exit 1);

#echo "Third argument is: $3";
#echo "realpath: $(realpath $3)";
#echo "realpath fixed: $(realpath /dev/stdout)";
duscr_args_handler $1 "$2" "$3" "$4";

