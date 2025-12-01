#!/bin/bash

# This script is used to configure ASes that were originally not preconfigured (NoConfig flag)
# It configures only the L3 network and hosts (not Layer2)

#########################################
### VALIDATE PLATFORM DIRECTORY CONTEXT
#########################################
PLATFORM_DIR=$(pwd)
if [[ $(basename "$PLATFORM_DIR") != "platform" ]]; then
    echo "Error: This script must be run from the 'platform' directory."
    exit 1
fi

#########################################
### DEFAULT CONFIG AND FLAG PARSING
#########################################
RPKI_ENABLED=true
ASN_TO_CONFIGURE=()

for arg in "$@"; do
    case "$arg" in
        --rpki)
            RPKI_ENABLED=true
            ;;
        --no-rpki)
            RPKI_ENABLED=false
            ;;
        *)
            ASN_TO_CONFIGURE+=("$arg")
            ;;
    esac
done

if [[ ${#ASN_TO_CONFIGURE[@]} -eq 0 ]]; then
    echo "Usage: $0 [--no-rpki] <ASN1> [ASN2 ASN3 ...]"
    exit 1
fi

if $RPKI_ENABLED; then
    CONFIG_FILES=("conf_init.sh" "conf_full.sh" "conf_rpki.sh")
else
    CONFIG_FILES=("conf_init.sh" "conf_full.sh")
fi

#########################################
### LOAD ROUTER NAMES FROM FILE
#########################################
WORKDIR="$PLATFORM_DIR"
ROUTER_FILE="$WORKDIR/config/l3_routers.txt"
if [[ ! -f "$ROUTER_FILE" ]]; then
    echo "Error: $ROUTER_FILE not found."
    exit 1
fi

routers=($(awk '{print $1}' "$ROUTER_FILE"))
if [[ ${#routers[@]} -eq 0 ]]; then
    echo -e "Error: Unable to find router names in l3_routers.txt\n"
    exit 1
fi

#########################################
### BEGIN CONFIGURATION
#########################################
echo "Updating configs with RPKI: $RPKI_ENABLED"
echo "You can ignore 'route-map' does not exist error (it will be defined)"
echo "You can ignore 'clear ip ospf process' message (the script does that)"

for group_number in "${ASN_TO_CONFIGURE[@]}"; do
    rid=1
    for router_name in "${routers[@]}"; do
        echo "$group_number $router_name: Configuring"
        config_dir="$PLATFORM_DIR/groups/g${group_number}/${router_name}/config"

        for config_file in "${CONFIG_FILES[@]}"; do
            config_file_full="${config_dir}/${config_file}"
            chmod 755 "${config_file_full}"
            docker cp "${config_file_full}" "${group_number}_${router_name}router":"/home/${config_file}" > /dev/null
            docker exec -it "${group_number}_${router_name}router" "./home/${config_file}"
        done

        docker exec -it ${group_number}_${router_name}host ip address add ${group_number}.$((100 + rid)).0.1/24 dev ${router_name}router
        docker exec -it ${group_number}_${router_name}host ip route add default via ${group_number}.$((100 + rid)).0.2

        echo "$group_number $router_name: Clearing BGP and OSPF"
        docker exec -it "${group_number}_${router_name}router" vtysh -c 'clear ip bgp *' -c 'clear ip ospf process'

        rid=$((rid + 1))
    done
done
