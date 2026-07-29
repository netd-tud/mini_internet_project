#!/bin/bash

if [ -z "$1" ]; then
  echo "Error: Missing parameter <number>."
  echo "Usage: $0 <number>"
  exit 1
fi

setup/restart_container.sh ssh "$1"

setup/restart_container.sh router "$1" HAM
setup/restart_container.sh router "$1" AMS
setup/restart_container.sh router "$1" BER
setup/restart_container.sh router "$1" FRA
setup/restart_container.sh router "$1" DRS
setup/restart_container.sh router "$1" ZRH
setup/restart_container.sh router "$1" MUC
setup/restart_container.sh router "$1" PRG

#setup/restart_container.sh l3-host "$1" HAM host
#setup/restart_container.sh l3-host "$1" AMS host
#setup/restart_container.sh l3-host "$1" BER host
#setup/restart_container.sh l3-host "$1" FRA host
#setup/restart_container.sh l3-host "$1" DRS host
#setup/restart_container.sh l3-host "$1" ZRH host
#setup/restart_container.sh l3-host "$1" MUC host
#setup/restart_container.sh l3-host "$1" PRG host

setup/restart_container.sh switch "$1" S1
setup/restart_container.sh switch "$1" S2
setup/restart_container.sh switch "$1" S3

# setup/restart_container.sh l2-host "$1" A_HAW
# setup/restart_container.sh l2-host "$1" S_HAW
# setup/restart_container.sh l2-host "$1" A_NETD
# setup/restart_container.sh l2-host "$1" S_NETD
# setup/restart_container.sh l2-host "$1" A_HPC
# setup/restart_container.sh l2-host "$1" S_HPC
