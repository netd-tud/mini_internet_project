# This script is used to configure ASes that were originally not preconfigured (NoConfig flag)
# The Layer2 network is not configured, only the L3 network as well as the hosts

### TO UPDATE ###
# this variable is the absolute path to the platform directory.
PLATFORM_DIR="$(pwd)"
# this variable includes all the AS number that need to be configured.
ASN_TO_CONFIGURE=()
# this variable contains all the router names that need to be configured.
# The order is important, as it will be used to assign IP addresses to the routers.
ROUTER_NAMES=()
CONFIG_FILES="conf_init.sh conf_full.sh"

if [[ ${#ASN_TO_CONFIGURE[@]} -eq 0 ]]; then
        # If ASN_TO_CONFIGURE is empty, read from AS_config.txt
        ASN_TO_CONFIGURE=($(awk '$2 == "AS" && $3 == "NoConfig" {print $1}' "$PLATFORM_DIR/config/AS_config.txt"))
        if [[ ${#ASN_TO_CONFIGURE[@]} -eq 0 ]]; then
            echo -e "error: Unable to find student AS groups in AS_config.txt\n"
            exit 1
        fi
        echo "AS numbers to configure: ${ASN_TO_CONFIGURE[@]}"
    fi

if [[ ${#ROUTER_NAMES[@]} -eq 0 ]]; then
        # If ROUTER_NAMES is empty, read from l3_routers.txt
        ROUTER_NAMES=($(awk '{print $1}' "$PLATFORM_DIR/config/l3_routers.txt"))
        if [[ ${#ROUTER_NAMES[@]} -eq 0 ]]; then
            echo -e "error: Unable to find router names in l3_routers.txt\n"
            exit 1
        fi
        echo "Router names: ${ROUTER_NAMES[@]}"
    fi

echo "Updating configs."
echo "You can ignore 'route-map' does not exist error (it will be defined)"
echo "You can ignore 'clear ip ospf process' message (the script does that)"

for group_number in "${ASN_TO_CONFIGURE[@]}"
do
    rid=1
    # This loop should iterate over the router, starting from lower ID to higher ID.
    for router_name in "${ROUTER_NAMES[@]}"
    do
        echo "$group_number $router_name: Configuring"
        config_dir="$PLATFORM_DIR/groups/g${group_number}/${router_name}/config"
        for config_file in $CONFIG_FILES ; do
            config_file_full="${config_dir}/${config_file}"
            chmod 755 "${config_file_full}"
            docker cp "${config_file_full}" "${group_number}_${router_name}router":"/home/${config_file}" > /dev/null
            docker exec -it "${group_number}_${router_name}router" "./home/${config_file}"
        done

        docker exec -it ${group_number}_${router_name}host ip address add ${group_number}.$((100+$rid)).0.1/24 dev ${router_name}router
        docker exec -it ${group_number}_${router_name}host ip route add default via ${group_number}.$((100+$rid)).0.2


        echo "$group_number $router_name: Clearing BGP and OSPF"
        docker exec -it "${group_number}_${router_name}router" vtysh -c 'clear ip bgp *' -c 'clear ip ospf process'


        rid=$(($rid+1))
    done
done
