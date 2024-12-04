#!/bin/bash
#
# delete links between groups and matrix container

set -o errexit
set -o pipefail
set -o nounset

DIRECTORY="$1"
CONFIG_DIRECTORY="$2"
source "${CONFIG_DIRECTORY}"/subnet_config.sh

# read configs
readarray groups < "${CONFIG_DIRECTORY}"/AS_config.txt
group_numbers=${#groups[@]}

echo -n "-- --if-exists del-br matrix " >> "${DIRECTORY}"/ovs_command.txt
