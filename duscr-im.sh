#!/bin/bash

#set -Eeuo pipefail #https://stackoverflow.com/questions/14970663/why-doesnt-bash-flag-e-exit-when-a-subshell-fails

function get_stack () { # https://gist.github.com/akostadinov/33bb2606afe1b334169dfbf202991d36
   STACK=""
   local i message="${1:-""}"
   local stack_size=${#FUNCNAME[@]}
   # to avoid noise we start with 1 to skip the get_stack function
   for (( i=1; i<$stack_size; i++ )); do
      local func="${FUNCNAME[$i]}"
      [ x$func = x ] && func=MAIN
      local linen="${BASH_LINENO[$(( i - 1 ))]}"
      local src="${BASH_SOURCE[$i]}"
      [ x"$src" = x ] && src=non_file_source

      STACK+=$'\n'"   at: "$func" "$src" "$linen
   done
   STACK="${message}${STACK}"
}

DUSCR_JOURNALESS_FORMAT_START_YEAR=2012;
DUSCR_OLDEST_ACT_YEAR=1918;
DUSCR_DIR_RELPATH='.duscr';
DUSCR_HEADPOINT_RELPATH="$DUSCR_DIR_RELPATH/headpoint";
DUSCR_ACTCOUNT_RELPATH="$DUSCR_DIR_RELPATH/actcount";
DUSCR_CHANGELOG_RELPATH="$DUSCR_DIR_RELPATH/changelog";

# $1 - new file basename
function duscr_mq_push_redis() {
  local ftag='duscr_notify_redis';

  local new_file_basename="$1";
  if [ "$new_file_basename" = "" ]; then
    echo "$ftag: No new file basename provided. Quit";
    exit 1;
  fi;

  redis-cli rpush duscr:file_mq "$new_file_basename";
  if [ $? -ne 0 ]; then
    echo "$ftag: Failed to push $new_file_basename to redis file mq. Quit";
    exit 1;
  fi;
}

# $1 - year : 1-4 digits
# $2 - journal no : 1-3 digits
# $3 - position : 1-4 digits
# $4 - part no: 1-2 digits
function duscr_implode_path() {
  local ftag='duscr_implode_path';

  local year="$1";
  local journalno="$2";
  local position="$3";
  local partno="$4";
  if [[ ! "$year" =~ ^[0-9]{1,4}$ ]]; then
    echo "$ftag: Invalid year '$year'. Quit";
    exit 1;
  elif [[ ! "$journalno" =~ ^[0-9]{1,3}$ ]]; then
    echo "$ftag: Invalid journal no '$journalno'. Quit";
    exit 1;
  elif [[ ! "$position" =~ ^[0-9]{1,4}$ ]]; then
    echo "$ftag: Invalid position '$position'. Quit";
    exit 1;
  elif [[ ! "$partno" =~ ^[0-9]{1,2}$ ]]; then
    echo "$ftag: Invalid part no '$partno'. Quit";
    exit 1;
  fi;

  local yyyy="$(printf '%04d' "$year")";
  local jjj="$(printf '%03d' "$journalno")";
  local pppp="$(printf '%04d' "$position")";
  local tt="$(printf '%02d' "$partno")";

  REPLY="https://dziennikustaw.gov.pl/D$yyyy$jjj$pppp$tt.pdf";
}

function duscr_fetch_num_acts() {
  local ftag='duscr_fetch_num_acts';

  local resp="$(until curl -sf 'https://api.sejm.gov.pl/eli/acts'; do sleep 5; done)"; #retry on failure
  if [ $? -ne 0 ]; then
    echo "$ftag: Failed to fetch sejm API endpoint";
    exit 1;
  fi;
  local num_acts="$(echo "$resp" | jq '.[0].actsCount')";
  if [ $? -ne 0 ]; then
    echo "$ftag: Failed to parse JSON received from sejm API endpoint";
    exit 1;
  fi;
  if [[ ! "$num_acts" =~ ^[0-9]+$ ]]; then
    echo "$ftag: Invalid acts number fetched from sejm API endpoint: '$num_acts'";
    exit 1;
  fi;
  REPLY="$num_acts";
}

# $1 - start code
# $2 param index (1 - year, 2 - journal no. 3 - position. 4 - part no)
function duscr_start_code_get_param() {
  local ftag='duscr_start_code_get_param';
  
  local start_code="$1";
  local param_index="$2";

  if [[ ! "$start_code" =~ ^[0-9]{1,4},[0-9]{1,3},[0-9]{1,4},[0-9]{1,2}$ ]]; then
    echo "$ftag: Invalid start code '$start_code'. Quit";
    get_stack;
    echo "$STACK";
    exit 1;
  fi; 

  if [[ ! "$param_index" =~ ^[1-4] ]]; then
    echo "$ftag: Invalid param index '$param_index'. Quit";
    exit 1;
  fi;

  local param_names=('' 'year' 'journal no' 'position' 'part no');
  local param_name="${param_names["$param_index"]}";

  local param_val="$(echo "$start_code" | awk -F ',' "{print \$$param_index}")"; 
  if [ $? -ne 0 ]; then
    echo "$ftag: Failed to obtain $param_name while parsing start code. Quit";
    exit 1;
  fi;
  REPLY="$param_val";  
}

## $1 - start code
#function duscr_start_code_get_year() {
#  local ftag='duscr_start_code_get_year'; 
#
#  local year="$(awk -F ',' '{print $1}')"; 
#  if [ $? -ne 0 ]; then
#    echo "$ftag: Failed to obtain year while parsing start code. Quit";
#    exit 1;
#  fi;
#  REPLY="$year"; 
#}

# $1 - start code
function duscr_start_code_get_year() {
  duscr_start_code_get_param "$1" 1;
}

# $1 - start code
function duscr_start_code_get_journalno() {
  duscr_start_code_get_param "$1" 2;
}


# $1 - start code
function duscr_start_code_get_position() {
  duscr_start_code_get_param "$1" 3;
}

# $1 - start code
function duscr_start_code_get_partno() {
  duscr_start_code_get_param "$1" 4;
}

# $1 - target directory
# # $2 - start code
#
# $REPLY: number of acts added to the target directory
function duscr_download_acts() {
  local ftag='duscr_download_acts';
  
  local target_dir="$1";
  # local start_code="$2";
  
  if [ "$target_dir" = "" ]; then
    echo "$ftag: No target directory provided. Quit";
    exit 1;
  fi;
  # if [ "$start_point" = "" ];
  #   echo "$ftag: No start point provided, using default";
  #   start_code='1918,1,1,0'
  # fi;

  local current_year=$(date +%Y);
  if [ $? -ne 0 ]; then
    echo "$ftag: Failed to obtain current year. Quit";
    exit 1;
  fi;  
  
  local year=1918;
  local journalno=1;
  local position=1;
  local partno=1;
  # duscr_start_code_get_year "$start_code";
  # year="$REPLY";
  # duscr_start_code_get_journalno "$start_code";
  # journalno="$REPLY";
  # duscr_start_code_get_position "$start_code";
  # position="$REPLY";
  # duscr_start_code_get_partno "$start_code";
  # partno="$REPLY";

  if [ ! -d "$target_dir" ]; then
    echo "$ftag: Target directory $target_dir does not exist. Creating";
    mkdir -p "$target_dir";
    if [ $? -ne 0 ]; then
      echo "$ftag: Failed to create target directory $target_dir. Quit";
      exit 1;
    fi;
  fi;

  local num_local_acts=0;
  local original_num_local_acts=0;
  if [ -d "$target_dir/$DUSCR_DIR_RELPATH" ]; then
    echo "$ftag: Target directory $target_dir/$DUSCR_DIR_RELPATH already exists. Processing";
    if [ ! -f "$target_dir/$DUSCR_HEADPOINT_RELPATH" ]; then
      echo "$ftag: $target_dir/$DUSCR_HEADPOINT_RELPATH is missing. Quit";
      exit 1;
    elif [ ! -f "$target_dir/$DUSCR_ACTCOUNT_RELPATH" ]; then
      echo "$ftag: $target_dir/$DUSCR_ACTCOUNT_RELPATH is missing. Quit";
      exit 1;
    fi;
    local headpoint=$(cat "$target_dir/$DUSCR_HEADPOINT_RELPATH");
    if [ $? -ne 0 ]; then
      echo "$ftag: Failed to read headpoint from $target_dir/$DUSCR_HEADPOINT_RELPATH. Quit";
      exit 1;
    fi;
    duscr_start_code_get_year "$headpoint";
    year="$REPLY";
    duscr_start_code_get_journalno "$headpoint";
    journalno="$REPLY";
    duscr_start_code_get_position "$headpoint";
    position="$REPLY";
    duscr_start_code_get_partno "$headpoint";
    partno="$REPLY";
    num_local_acts=$(cat "$target_dir/$DUSCR_ACTCOUNT_RELPATH");
    if [ $? -ne 0 ]; then
      echo "$ftag: Failed to read act count from $target_dir/$DUSCR_ACTCOUNT_RELPATH. Quit";
      exit 1;
    fi;
    original_num_local_acts="$num_local_acts";
  else
    echo "$ftag: Target directory $target_dir/$DUSCR_DIR_RELPATH does not exist. Creating";
    mkdir -p "$target_dir/$DUSCR_DIR_RELPATH";
    if [ $? -ne 0 ]; then
      echo "$ftag: Failed to create target directory $target_dir/$DUSCR_DIR_RELPATH. Quit";
      exit 1;
    fi;
  fi;

  if [ "$year" -lt "$DUSCR_OLDEST_ACT_YEAR" ]; then
    echo "$ftag: Year $year is older than the oldest act year $DUSCR_OLDEST_ACT_YEAR. Quit";
    exit 1;
  fi;
  if [ "$year" -gt "$current_year" ]; then
    echo "$ftag: Year $year is newer than the current year $current_year. Quit";
    exit 1;
  fi;

  local num_acts=0;
  duscr_fetch_num_acts;
  num_acts="$REPLY";
  if [ $num_acts -le 0 ]; then
    echo "$ftag: Invalid number of acts fetched from sejm API endpoint: $num_acts. This is unexpected. Quit";
    exit 1;
  fi;

  while [ "$year" -lt "$current_year" ] ; do #iterate over years
    local should_switch_year=0;
    local iter_follows_journal_switch=0;
    echo "$ftag: Processing year $year";
    while : ; do #iterate over journalno+position
      local should_switch_journal=0;
      #echo "$ftag: Processing journalno $journalno, position $position";
      echo "[ $num_local_acts / $num_acts ]";
      while : ; do #iterate over partno
        echo "$ftag: Processing partno $partno";
        local url='';
        duscr_implode_path "$year" "$journalno" "$position" "$partno";
        url="$REPLY";
        local target_file="$target_dir/$(basename "$url")";
        if [ -f "$target_file" ]; then
          echo "$ftag: File $target_file already exists (this could be a result of interrupted download). Skipping";
        else
          echo "$ftag: Querying $url";
          # a) If we get 404, we should skip to next position
          # b) If we get other error, we should retry until success
          local headers=$(until curl -sI "$url"; do sleep 5; done);
          if [ $? -ne 0 ]; then
            echo "$ftag: Failed to fetch headers for $url which is not a problem itself, however we the script is in an unexpected state as the curl command was called via until. Quit";
            exit 1;
          fi;
          local http_status=$(echo "$headers" | head -n 1 | awk -F ' ' '{print $2}');
          if [ "$http_status" = "" ]; then
            echo "$ftag: Failed to obtain HTTP status for $url (awk returned empty string). Quit";
            exit 1;
          fi;

          if [ "$http_status" = "404" ]; then
            # PDF doesn't exist
            echo "$ftag: Remote file at $url does not exist. Skipping";
            if [ "$partno" = "1" ]; then
              should_switch_journal=1;
              if [ "$year" -ge "$DUSCR_JOURNALESS_FORMAT_START_YEAR" ]; then
                should_switch_year=1;
              elif [ "$iter_follows_journal_switch" = "1" ]; then
                should_switch_year=1;
                iter_follows_journal_switch=0;
              fi;
            fi;
            partno=1;
            echo "!!Breaking!! year=$year, journalno=$journalno, position=$position, partno=$partno; should_switch_journal=$should_switch_journal; should_switch_year=$should_switch_year; iter_follows_journal_switch=$iter_follows_journal_switch";
            break;
          elif [ "$http_status" = "200" ]; then
            # PDF exists
            iter_follows_journal_switch=0;
            should_switch_journal=0; #defensive
            should_switch_year=0; #defensive
        
            echo "$ftag: Downloading $url to $target_file...";
            until curl -s "$url" -o "$target_file"; do sleep 5; done;
            if [ $? -ne 0 ]; then
              echo "$ftag: Failed to download remote file at $url to $target_file which is not a problem itself, however we the script is in an unexpected state as the curl command was called via until. Quit";
              exit 1;
            fi;
            echo "$ftag: Done downloading remote file at $url to $target_file";

            echo "$(date): $(basename "$target_file")" >> "$target_dir/$DUSCR_CHANGELOG_RELPATH";
            if [ $? -ne 0 ]; then
              echo "$ftag: Failed to append to $target_dir/$DUSCR_CHANGELOG_RELPATH. Quit";
              exit 1;
            fi;

            duscr_mq_push_redis "$(basename "$target_file")";

            # Update headpoint and act count to persist the progress
            if [ "$partno" = "1" ]; then
              num_local_acts=$((num_local_acts + 1));
              echo "$num_local_acts" > "$target_dir/$DUSCR_ACTCOUNT_RELPATH";
              if [ $? -ne 0 ]; then
                echo "$ftag: Failed to write act count to $target_dir/$DUSCR_ACTCOUNT_RELPATH. Quit";
                exit 1;
              fi;
            fi;
            echo "$year,$journalno,$position,$partno" > "$target_dir/$DUSCR_HEADPOINT_RELPATH";
            if [ $? -ne 0 ]; then
              echo "$ftag: Failed to write headpoint to $target_dir/$DUSCR_HEADPOINT_RELPATH. Quit";
              exit 1;
            fi;
          else
            echo "$ftag: Unexpected HTTP status $http_status for $url. Are we being rate limited? Quit";
            exit 1;
          fi;

        fi;
        
        partno=$((partno + 1));
      done; #partno
      if [ "$should_switch_year" = "1" ]; then
        # reset journalno and position
        if [ "$year" -ge "$DUSCR_JOURNALESS_FORMAT_START_YEAR" ]; then
          journalno=0;
        else
          journalno=1;
        fi;
        position=1;
        should_switch_year=0;
        break;
      elif [ "$should_switch_journal" = "1" ]; then
        journalno=$((journalno + 1));
        should_switch_journal=0;
        iter_follows_journal_switch=1;
      else
        position=$((position + 1));
      fi;
    done; #journalno+position
    year=$((year+1));
  done; #year
}

echo "duscr-im (Dziennik Ustaw SCRaper IMproved) - duscr-im.sh <target_dir>";
echo "===============================";
duscr_download_acts "$1";
echo "===============================";
echo "Added $REPLY acts to $1. Done";