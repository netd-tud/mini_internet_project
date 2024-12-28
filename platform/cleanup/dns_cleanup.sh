#!/bin/bash
#
# delete links between groups and dns server
# delet link between measurement container to dns server

set -o errexit
set -o pipefail
set -o nounset

DIRECTORY="$1"
CONFIG_DIRECTORY="${DIRECTORY}"/config
if [ -n "${2:-}" ] && [ -d "$2" ] && [ "$(basename "$2")" = "config" ]; then
  CONFIG_DIRECTORY="$2"
fi
source "${CONFIG_DIRECTORY}"/subnet_config.sh

echo -n "-- --if-exists del-br dns " >> "${DIRECTORY}"/ovs_command.txt

# del bridge bewteen measurement to dns service
br_name="dns_measurement"
echo -n "-- --if-exists del-br "${br_name}" " >> "${DIRECTORY}"/ovs_command.txt
