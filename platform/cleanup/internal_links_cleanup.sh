#!/bin/bash
#
# delete links between routers inside the AS
# links defined in ./config/internal_links_config.txt

set -o errexit
set -o pipefail
set -o nounset

DIRECTORY="$1"
CONFIG_DIRECTORY="${DIRECTORY}"/config
if [ -n "${2:-}" ] && [ -d "$2" ] && [ "$(basename "$2")" = "config" ]; then
  CONFIG_DIRECTORY="$2"
fi
source "${CONFIG_DIRECTORY}"/subnet_config.sh


# read configs
readarray groups < "${CONFIG_DIRECTORY}"/AS_config.txt
group_numbers=${#groups[@]}

for ((k=0;k<group_numbers;k++)); do
    group_k=(${groups[$k]})
    group_number="${group_k[0]}"
    group_as="${group_k[1]}"
    group_config="${group_k[2]}"
    group_router_config="${group_k[3]}"
    group_internal_links="${group_k[4]}"

    if [ "${group_as}" != "IXP" ];then

        readarray intern_links < "${CONFIG_DIRECTORY}"/$group_internal_links
        n_intern_links=${#intern_links[@]}

        br_name="int-""${group_number}"
        echo -n "-- --if-exists del-br "${br_name}" " >> "${DIRECTORY}"/ovs_command.txt
    fi
done
