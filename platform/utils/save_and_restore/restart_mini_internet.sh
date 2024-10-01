#!/bin/bash
# modified script from https://github.com/nsg-ethz/mini_internet_project/pull/43

#suggested cron job:
#    */10 * * * * cd /path/to/your/platform && ./restart_mini_internet.sh -b -y >> /path/to/logfile.log 2>&1

WORKDIR="$(pwd)"
students_as=()
routers=()

useIPv6=true

# Use arrays for options
declare -A options=(
  [backup]=false
  [restart]=false
  [restore]=false
  [confirm]=false
)

# save all configs first
save_configs() {
  local config_dir="$WORKDIR/../students_config"
  local timestamp=$(date +"%Y%m%d_%H%M%S")
  local backup_dir="${config_dir}/${timestamp}"
  mkdir -p "$backup_dir"
  cd "$backup_dir"

  echo "Backup directory: $backup_dir"

  for as in "${students_as[@]}"; do
    docker exec -iw /root ${as}_ssh bash -c 'rm -rfv configs*' > /dev/null
    docker exec -iw /root ${as}_ssh "./save_configs.sh" > /dev/null

    configName=$(docker exec -iw /root ${as}_ssh bash -c 'find . -maxdepth 1 -regex \./.*.tar.gz' | sed -e 's/\r$//')
    docker exec -iw /root ${as}_ssh bash -c "mv $configName configs-as-${as}.tar.gz"

    if docker cp ${as}_ssh:/root/configs-as-${as}.tar.gz ./configs-as-${as}.tar.gz; then
        echo "Config file for AS ${as} copied successfully."
    else
        echo "Error: Failed to copy config file for AS ${as}."
        exit 1
    fi
  done

  echo "Backup process completed."
  echo "Configs saved in: $backup_dir"
}

get_latest_backup() {
  local config_dir="$WORKDIR/../students_config"
  local latest_backup=$(ls -d "$config_dir"/*/ | sort -r | head -n 1)
  echo "${latest_backup%/}"
}

reset_with_startup() {
  cd $WORKDIR
  echo "Executing cleanup.sh & hard_reset.sh ..."
  ./cleanup/cleanup.sh . && ./cleanup/hard_reset.sh .

  echo "Executing startup.sh ..."
  # currently disabled the iptables filters feature
  # ./startup.sh . && ./utils/iptables/filters.sh .
  ./startup.sh .

  echo "Waiting for docker container to ready first, sleeping in 3 seconds..."
  sleep 3
  
  # Start MATRIX container
  docker unpause MATRIX
}

restore_configs() {
  local backup_dir="${1:-$(get_latest_backup)}"
  
  if [ ! -d "$backup_dir" ]; then
    echo "Error: Backup directory not found: $backup_dir"
    exit 1
  fi

  echo "Restoring configs from: $backup_dir"

  for as in "${students_as[@]}"; do
    cd "$backup_dir"

    echo "Restoring config on AS: ${as}"
    docker cp "./configs-as-${as}.tar.gz" "${as}_ssh:/root/"
    docker exec -iw /root "${as}_ssh" bash -c "./restore_configs.sh configs-as-${as}.tar.gz all" << EOF
Y
EOF
    # Extract the config file
    rm -rf configs_*
    tar -xf "configs-as-${as}.tar.gz"
    local configs_folder_name=$(ls -d */ | grep configs)

    restore_routers "$as" "$configs_folder_name"
    restore_edge_hosts "$as" "$configs_folder_name"
    restore_switches "$as" "$configs_folder_name"
    restore_network_hosts "$as" "$configs_folder_name"
  done
}

restore_routers() {
  local as="$1"
  local configs_folder_name="$2"
  
  for rc in "${routers[@]}"; do
    local container_name="${as}_${rc}router"
    echo "Restoring $container_name configuration..."
    
    docker cp "${configs_folder_name}${rc}/router.conf" "${container_name}:/root/frr.conf"
    docker exec -w /root "${container_name}" bash -c '
      sed "1,3d" /root/frr.conf > /root/frr-removed-header.conf
      /usr/lib/frr/frr-reload.py --reload /root/frr-removed-header.conf
      rm /root/{frr,frr-removed-header}.conf
    '
  done
}

restore_edge_hosts() {
  local as="$1"
  local configs_folder_name="$2"
  
  for rc in "${routers[@]}"; do
    local container_name="${as}_${rc}host"
    echo "Restoring $container_name configuration..."
    
    local ipv4=$(grep -w inet "${configs_folder_name}${rc}/host.ip" | grep "${rc}router" | awk '{print $2}')
    echo "From Backup: $container_name IPv4: ${ipv4}"
    
    if [ "$useIPv6" = true ]; then
      local ipv6=$(grep -w inet6 "${configs_folder_name}${rc}/host.ip" | grep "${rc}router" | awk '{print $2}')
      echo "From Backup: $container_name IPv6: ${ipv6}"
    fi
    
    local default_route=$(grep -w default "${configs_folder_name}${rc}/host.route" | awk '{print $3}')
    echo "From Backup: $container_name Default Route: ${default_route}"
    
    docker exec -w /root "${container_name}" ip address add "${ipv4}" dev "${rc}router" &> /dev/null
    if [ "$useIPv6" = true ]; then
      docker exec -w /root "${container_name}" ip address add "${ipv6}" dev "${rc}router" &> /dev/null
    fi
    docker exec -w /root "${container_name}" ip route add default via "${default_route}" &> /dev/null
  done
}

restore_switches() {
  local as="$1"
  local configs_folder_name="$2"
  
  while read -r network switch type mac_address id; do
    local container_name="${as}_L2_${network}_${switch}"
    container_name=$(echo "$container_name" | tr -d ' ')
    echo "Restoring AS $as L2 switch: $container_name"
    
    docker cp "${configs_folder_name}${switch}/switch.db" "${container_name}:/root/switch.db"
    docker exec -w /root "${container_name}" bash -c 'ovsdb-client restore < /root/switch.db'
    sleep 2
    docker exec -w /root "${container_name}" bash -c 'rm /root/switch.db'
  done < <(sed 's/^[[:space:]]*//' "$WORKDIR/config/l2_switches.txt" | grep -v '^$')
}

restore_network_hosts() {
  local as="$1"
  local configs_folder_name="$2"
  
  while read -r host image network switch _; do
    local container_name="${as}_L2_${network}_${host}"
    container_name=$(echo "$container_name" | tr -d ' ')
    echo "Restoring $container_name configuration..."
    
    local ipv4=$(grep -w inet "${configs_folder_name}${host}/host.ip" | grep "${as}-${switch}" | awk '{print $2}')
    echo "From Backup: $container_name IPv4: ${ipv4}"
    
    if [ "$useIPv6" = true ]; then
      local ipv6=$(grep -w inet6 "${configs_folder_name}${host}/host.ip" | grep "${as}-${switch}" | awk '{print $2}')
      echo "From Backup: $container_name IPv6: ${ipv6}"
    fi
    
    local default_route=$(grep -w default "${configs_folder_name}${host}/host.route" | awk '{print $3}')
    echo "From Backup: $container_name Default Route: ${default_route}"
    
    docker exec -w /root "${container_name}" ip address add "${ipv4}" dev "${as}-${switch}" &> /dev/null
    if [ "$useIPv6" = true ]; then
      docker exec -w /root "${container_name}" ip address add "${ipv6}" dev "${as}-${switch}" &> /dev/null
    fi
    docker exec -w /root "${container_name}" ip route add default via "${default_route}" &> /dev/null
  done < <(sed 's/^[[:space:]]*//' "$WORKDIR/config/l2_hosts.txt" | grep -v '^$')
}

show_passwords() {
  cd $WORKDIR
  echo "--- START OF ASes PASSWORDS ---"
  cat groups/passwords.txt
  echo "---  END OF ASes PASSWORDS  ---"

  echo "--- START OF krill_passwords ---"
  cat groups/krill_passwords.txt
  echo "---  END OF krill_passwords  ---"

  echo "--- START OF MEASUREMENT PASSWORDS ---"
  cat groups/ssh_measurement.txt
  echo "---  END OF MEASUREMENT PASSWORDS  ---"
}

function red_echo() {
  echo -e "\e[31m$1\e[0m"
}

show_help() {
  echo "Usage: $0 [options] [-g <AS groups>]"
  echo "Note: This must be run from the platform directory for relative paths to work."
  echo
  echo "Options:"
  echo "  -b    Backup configs to students_config directory"
  echo "        (optional: use -g to specify ASes groups)"
  echo "        Creates a new timestamped directory for each backup"
  echo
  echo "  -s    Reset the mini internet (performs startup.sh)"
  red_echo "        CAUTION: This will wipe all configs in the project."
  red_echo "                 Ensure you have a backup of the configs."
  echo
  echo "  -r    Restore ASes configs"
  echo "        (optional: use -g to specify ASes groups)"
  echo "        Restores from the latest backup by default"
  echo "        Use -d to specify a particular backup directory"
  red_echo "        CAUTION: This will override the running configs."
  echo
  echo "  -g    Specify ASes groups for backup/restore"
  echo "        Format: comma-separated without whitespace (e.g., 3,4,13,14)"
  echo
  echo "  -d    Specify a backup directory to restore from"
  echo "        If not specified, the latest backup will be used"
  echo "        Format: full path to the backup directory"
  echo
  echo "  -y    Skip confirmation prompts"
  echo "  -p    Show AS passwords"
  echo "  -h    Show this help message"
  echo
  echo "Examples:"
  echo "  $0 -b -g 3,4,13,14     # Backup configs for AS groups 3, 4, 13, and 14"
  echo "  $0 -r                  # Restore configs from the latest backup"
  echo "  $0 -r -d /path/to/backup  # Restore configs from a specific backup directory"
  echo "  $0 -b -s -r            # Backup, reset, and restore in that order"
  echo
  echo "Note: If using multiple options, the script will perform backup, reset, and restore in that order."
}

check_if_root() {
  if [[ $(id -u) -ne 0 ]]; then
    echo "You must run as root, exiting..."
    exit 1
  fi
}

check_students_as_len() {
    if [[ ${#students_as[@]} -eq 0 ]]; then
        # If students_as is empty, read from AS_config.txt
        readarray -t students_as < <(awk '$2 == "AS" && $3 == "NoConfig" {print $1}' "$WORKDIR/config/AS_config.txt")
        if [[ ${#students_as[@]} -eq 0 ]]; then
            echo -e "error: Unable to find student AS groups in AS_config.txt\n"
            show_help
            exit 1
        fi
    fi
    echo "Students AS groups: ${students_as[@]}"
    if ! ${options[confirm]}; then
        # Ask for confirmation before proceeding
        echo -n "Do you want to continue with these AS groups? (y/n): "
        read answer
        if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
            echo "Operation cancelled."
            exit 0
        fi
    fi
}

check_routers() {
    if [[ ${#routers[@]} -eq 0 ]]; then
        # If routers is empty, read from l3_routers.txt
        routers=($(awk '{print $1}' "$WORKDIR/config/l3_routers.txt"))
        if [[ ${#routers[@]} -eq 0 ]]; then
            echo -e "error: Unable to find router names in l3_routers.txt\n"
            exit 1
        fi
        echo "Router names: ${routers[@]}"
    fi
}

welcome() {
  if [[ $# -eq 0 ]]; then
    show_help
    exit 1
  fi

  local specified_backup=""

  while getopts ":bsryg:hp:d:" opt; do
    case $opt in
      b) options[backup]=true ;;
      r) options[restore]=true ;;
      s) options[restart]=true ;;
      y) options[confirm]=true ;;
      g)
        IFS=',' read -ra students_as <<< "$OPTARG"
        for i in "${students_as[@]}"; do
          if ! [[ $i =~ ^[0-9]+$ ]]; then
            echo "Error: AS group must be an integer" >&2
            show_help
            exit 1
          fi
        done
        ;;
      h) show_help; exit 0 ;;
      p) show_passwords; exit 0 ;;
      d) specified_backup="$OPTARG" ;;
      *) show_help; exit 1 ;;
    esac
  done

  run "$specified_backup"
}

run() {
  local specified_backup="$1"

  check_if_root
  check_students_as_len
  check_routers

  # Perform actions in a specific order: backup, restart, restore
  if ${options[backup]}; then
    echo "Backup configs..."
    save_configs
  fi

  if ${options[restart]}; then
    echo "Resetting the mini internet..."
    reset_with_startup
  fi

  if ${options[restore]}; then
    if [ -n "$specified_backup" ]; then
      restore_configs "$specified_backup"
    else
      echo "Restoring configs from latest backup..."
      restore_configs
    fi
    echo "Restore complete, here are all passwords..."
    show_passwords
  fi
}

welcome "$@"
