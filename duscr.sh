#!/bin/bash

### === EXTERNALS DESCRIPTION ===
## Arguments
# $1 - mode, one of the following options:
#     init - downloads everything starting from 1944 and ending today
#     sync - checks for new stuff and updates the dataset if needed
# $2 - data directory path

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
DUSCR_DIR_RELPATH=".duscr";
DUSCR_HEADPOINT_RELPATH="headpoint";

# $1 - YYYY
function duscr_year_scrap() {
    YYYY=$1;
    HEADPOINT_SAVE_FLAG=0;
    if [ "$YYYY" = "$CURRENT_YEAR" ]; then
        HEADPOINT_SAVE_FLAG=1;
    fi;

    echo -n "Scraping year $YYYY... ";	
    while read relpath; do	
        if [ "$HEADPOINT_SAVE_FLAG" = "1" ]; then
            # save the headpoint to .duscr/headpoint
	    echo "$relpath" > "$DUSCR_DIR_RELPATH/$DUSCR_HEADPOINT_RELPATH" || (echo "Failed to write to $DUSCR_HEADPOINT_RELPATH"; exit 1);
	    HEADPOINT_SAVE_FLAG=0;
        fi;

	until wget -q "$BASE_URL_DIRECT/$relpath"; do sleep 5; done;
done < <(until curl -s "$BASE_URL/$1"; do sleep 5; done | pup '#c_table tbody tr a' | sed -n 's/.*href=\"\([^"]*\)".*/\1/p' | grep .pdf);
    echo "Done";
}


# $1 - mode option
# $2 - data directory path
function duscr_arg_common_sanity_checks() {
    MODE=$1;
    DATA_DIR=$2;
    
    if [ ! -d $DATA_DIR ]; then
        echo "The provided directory \"$DATA_DIR\" doesn't exist!";
	exit 1;
    fi;
    if [ "$DATA_DIR" = "" ]; then
        echo "Missing data directory path as second argument";
	exit 1;
    fi;
}

# $1 - mode option
# $2 - data directory path
function duscr_args_handler() {
    MODE=$1;
    DATA_DIR=$2;
    case $MODE in
        init)
	    duscr_arg_common_sanity_checks $MODE $DATA_DIR;
	    cd $DATA_DIR || (echo "Failed to cd $DATA_DIR"; exit 1);
	    # check if .duscr exists
	    if [ -d "$DUSCR_DIR_RELPATH" ]; then
	        echo "$DATA_DIR already is a duscr initialized directory. Quit.";
	        exit 1;
	    fi;
            mkdir "$DUSCR_DIR_RELPATH";
            
            # download everything starting from 1944 and ending CURRENT_YEAR
	    for year in $(seq $FIRST_YEAR $CURRENT_YEAR);
	    do
                duscr_year_scrap $year; 
	    done;
	    cd - || (echo  "Failed to cd -"; exit 1);	    
	    ;;
        sync)
	    # check for new stuff and update the dataset if needed
	    duscr_arg_common_sanity_checks $MODE $DATA_DIR;
	    echo "Not implemented!"
	    exit 1;
	    ;;
        *)
	    echo "------ duscr (the Dziennik Ustaw SCRaper)------";
            echo "Usage: duscr.sh [mode] [data_dir]";
	    echo "    mode - one of the following options:";
	    echo "        init - downloads everything starting from 1944 and ending today";
	    echo "        sync - checks for new stuff and updates the dataset if needed";
	    ;;
    esac;
	   
}

duscr_args_handler $1 $2;
#duscr_year_scrap 2024;

