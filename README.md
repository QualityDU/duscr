# duscr - the Dziennik Ustaw SCRaper

## Package requirements
### Please ensure that pup, curl, awk, sed, bash are available on the host system for this command-line utility to work correctly.

## Installation
1. Clone this repository
2. (optional) create a symlink `duscr -> duscr.sh` and add the project directory to PATH
3. (optional) Add the PATH update to .bashrc

## How to use
1. Create an empty directory for storing duscr scrap data
2. Run `duscr init <directory_path> <log_file_path>` and wait until the files are downloaded
3. Add a cron job containing `duscr sync <directory_path> <log_file_path>` so that any updates are synced with a desired frequency
