#!/bin/bash
#
# starts whole network

# set -x
set -o errexit # exit on error
set -o pipefail # catch errors in pipelines
set -o nounset # exit on undeclared variable
set -o xtrace # bash -v or bash -x for debugging

# Check for programs we'll need.
search_path () {
    # display the path to the command
    type -p "$1" > /dev/null && return 0
    echo >&2 "$0: $1 not found in \$PATH, please install and try again"
    exit 1
}

if (($UID != 0)); then
    echo "$0 needs to be run as root"
    exit 1
fi

# check dependencies and install if needed
if command -v apt > /dev/null 2>&1; then
    apt update
    apt -y install openvswitch-switch bc uuid-runtime openvpn
else
    echo "no apt found to install packages"
fi

# check if docker is already installed and install if needed
if !(command -v docker > /dev/null 2>&1;) then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
fi

search_path ovs-vsctl
search_path docker
search_path uuidgen


# # netns: used to create isolated network environments/namespaces
if (ip netns) > /dev/null 2>&1; then :; else
    echo >&2 "${0##*/}: ip utility not found (or it does not support netns),"\
             "cannot proceed"
    exit 1
fi

# # TODO: check the directory is platform/
#DIRECTORY=$(cd `dirname $0` && pwd)

# DIRECTORY is the location of this startup.sh file
DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)
echo $DIRECTORY
#TODO Working dir, with /groups auch parametrisiert
CONFIG_DIRECTORY="${DIRECTORY}"/config
if [ -n "${1:-}" ] && [ -d "$1" ] && [ "$(basename "$1")" = "config" ]; then
  CONFIG_DIRECTORY="$1"
else
  CONFIG_DIRECTORY="${DIRECTORY}"/config
fi
echo $CONFIG_DIRECTORY


echo "$(date +%Y-%m-%d_%H-%M-%S)"

echo "hard_reset.sh"
# time ./cleanup/cleanup.sh "${DIRECTORY}"

time $DIRECTORY/cleanup/hard_reset.sh

echo ""
echo ""

# increase the number of INotify instances that can be created per real user ID
sysctl fs.inotify.max_user_instances=1024
# change size of ARP table necessary for large networks
# ARP: IP-to-MAC resolution
sysctl net.ipv4.neigh.default.gc_thresh1=16384  # the kernel begins to purge unused entries periodically
sysctl net.ipv4.neigh.default.gc_thresh2=32768 # more aggresive purging
sysctl net.ipv4.neigh.default.gc_thresh3=131072 # no new entries are allowed
# apply changes ffrom sysctl.conf
sysctl -p

# Increase the max number of running processes
sysctl kernel.pid_max=4194304

# Load MPLS kernel modules
modprobe mpls_router # enables the kernel to process MPLS packets, which is necessary for VPN
modprobe mpls_gso # MPLS Generic Segmentation Offload, enables segmentation for large packets to offload the CPU
modprobe mpls_iptunnel # enables the kernel to create VPN to tunnel IP packets over MPLS

echo "folder_setup.sh $(($(date +%s%N)/1000000))" > "${DIRECTORY}"/log.txt
echo "folder_setup.sh: "
time $DIRECTORY/setup/folder_setup.sh "${DIRECTORY}" "${CONFIG_DIRECTORY}"

echo ""
echo ""

echo "dns_config.sh $(($(date +%s%N)/1000000))" >> "${DIRECTORY}"/log.txt
echo "dns_config.sh: "
time $DIRECTORY/setup/dns_config.sh "${DIRECTORY}"

echo ""
echo ""

echo "rpki_config.sh $(($(date +%s%N)/1000000))" >> "${DIRECTORY}"/log.txt
echo "rpki_config.sh: "
time $DIRECTORY/setup/rpki_config.sh "${DIRECTORY}"

echo ""
echo ""

# echo "vpn_config.sh $(($(date +%s%N)/1000000))" >> "${DIRECTORY}"/log.txt
# echo "vpn_config.sh: "
# time $DIRECTORY/setup/vpn_config.sh "${DIRECTORY}"

# echo ""
# echo ""

echo "goto_scripts.sh $(($(date +%s%N)/1000000))" >> "${DIRECTORY}"/log.txt
echo "goto_scripts.sh: "
time $DIRECTORY/setup/goto_scripts.sh "${DIRECTORY}"

echo ""
echo ""

echo "save_configs.sh $(($(date +%s%N)/1000000))" >> "${DIRECTORY}"/log.txt
echo "save_configs.sh: "
time $DIRECTORY/setup/save_configs.sh "${DIRECTORY}"

echo ""
echo ""

echo "container_setup.sh $(($(date +%s%N)/1000000))" >> "${DIRECTORY}"/log.txt
echo "container_setup.sh: "
time $DIRECTORY/setup/container_setup.sh "${DIRECTORY}"

echo ""
echo ""

echo "connect_l3_host_router.sh $(($(date +%s%N)/1000000))" >> "${DIRECTORY}"/log.txt
echo "connect_l3_host_router.sh: "
time $DIRECTORY/setup/connect_l3_host_router.sh "${DIRECTORY}"

echo ""
echo ""

echo "connect_l2_network.sh $(($(date +%s%N)/1000000))" >> "${DIRECTORY}"/log.txt
echo "connect_l2_network.sh: "
time $DIRECTORY/setup/connect_l2_network.sh "${DIRECTORY}"

echo ""
echo ""

echo "connect_internal_routers.sh $(($(date +%s%N)/1000000))" >> "${DIRECTORY}"/log.txt
echo "connect_internal_routers.sh: "
time $DIRECTORY/setup/connect_internal_routers.sh "${DIRECTORY}"

echo ""
echo ""

echo "connect_external_routers.sh $(($(date +%s%N)/1000000))" >> "${DIRECTORY}"/log.txt
echo "connect_external_routers.sh: "
time $DIRECTORY/setup/connect_external_routers.sh "${DIRECTORY}"

echo ""
echo ""

echo "configure_ssh.sh $(($(date +%s%N)/1000000))" >> "${DIRECTORY}"/log.txt
echo "configure_ssh.sh: "
time $DIRECTORY/setup/configure_ssh.sh "${DIRECTORY}"

echo ""
echo ""

echo "connect_services.sh $(($(date +%s%N)/1000000))" >> "${DIRECTORY}"/log.txt
echo "connect_services.sh: "
time $DIRECTORY/setup/connect_services.sh "${DIRECTORY}"

echo ""
echo ""

echo "layer2_config.sh: "
echo "layer2_config.sh $(($(date +%s%N)/1000000))" >> "${DIRECTORY}"/log.txt
time $DIRECTORY/setup/layer2_config.sh "${DIRECTORY}"

echo ""
echo ""

echo "router_config.sh: "
echo "router_config.sh $(($(date +%s%N)/1000000))" >> "${DIRECTORY}"/log.txt
time $DIRECTORY/setup/router_config.sh "${DIRECTORY}"

echo ""
echo ""

echo "mpls.sh: "
echo "mpls.sh $(($(date +%s%N)/1000000))" >> "${DIRECTORY}"/log.txt
time $DIRECTORY/setup/mpls_setup.sh "${DIRECTORY}"

echo ""
echo ""

# TODO 
echo "Waiting 60sec for RPKI CA and proxy to startup.."
sleep 10

echo "rpki_setup.sh $(($(date +%s%N)/1000000))" >> "${DIRECTORY}"/log.txt
echo "rpki_setup.sh: "
time $DIRECTORY/setup/rpki_setup.sh "${DIRECTORY}"

echo ""
echo ""

echo "website_setup.sh: "
echo "website_setup.sh $(($(date +%s%N)/1000000))" >> "${DIRECTORY}"/log.txt
time $DIRECTORY/setup/website_setup.sh "${DIRECTORY}"

echo ""
echo ""

echo "webserver_links.sh: "
echo "webserver_links.sh $(($(date +%s%N)/1000000))" >> "${DIRECTORY}"/log.txt
time $DIRECTORY/groups/rpki/webserver_links.sh

echo ""
echo ""

# TODO 
echo "history_setup.sh: "
echo "history_setup.sh $(($(date +%s%N)/1000000))" >> "${DIRECTORY}"/log.txt
time $DIRECTORY/setup/history_setup.sh "${DIRECTORY}"

echo ""
echo ""

# reload dns server config
if [ -n "$(docker ps | grep "DNS")" ]; then
    # docker exec -d DNS service bind9 restart
    docker kill --signal=HUP DNS
fi

echo ""
echo ""

# TODO 
echo "Applying hijacks: "
echo "hijacks $(($(date +%s%N)/1000000))" >> "${DIRECTORY}"/log.txt
time $DIRECTORY/setup/hijack_config.py "${DIRECTORY}"

echo "$(date +%Y-%m-%d_%H-%M-%S)"

echo ""
echo ""

# TODO 
echo "Waiting 60sec for BGP messages to propagate..."
sleep 10

echo "Refreshing selected advertisements: "
echo "bgp_clear $(($(date +%s%N)/1000000))" >> "${DIRECTORY}"/log.txt
time $DIRECTORY/setup/bgp_clear.sh "${DIRECTORY}"

echo "$(date +%Y-%m-%d_%H-%M-%S)"
