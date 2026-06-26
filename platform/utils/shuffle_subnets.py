
import os


GROUPS = [31]
NEW_SUBNETS = [13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24]


class Router:
	def __init__(self, name):
		self.name = name

	def get_name(self):
		return self.name

		
class Interface:
	def __init__(self, name, ip):
		self.name = name
		self.ip = ip

	def get_name(self):
		return self.name

	def get_ip(self):
		return self.ip
	
	def set_ip(self, new_ip):
		self.ip = new_ip


class Link:
	def __init__(self, router_pair, interface_pair):
		self.routers = router_pair
		self.interfaces = interface_pair

	def __repr__(self):
		return f"Link(router={self.routers}, interface={self.interfaces})"
	
	def get_routers(self):
		return self.routers
	
	def get_interfaces(self):
		return self.interfaces
	
	def get_interface_ip(self, src_router_str, dst_router_str):
		if self.routers[0].get_name() == src_router_str and self.routers[1].get_name() == dst_router_str:
			return self.interfaces[0].get_ip()
		elif self.routers[1].get_name() == src_router_str and self.routers[0].get_name() == dst_router_str:
			return self.interfaces[1].get_ip()
		else:
			return None
		
	def set_interface_ip(self, src_router_str, dst_router_str, new_ip):
		if self.routers[0].get_name() == src_router_str and self.routers[1].get_name() == dst_router_str:
			self.interfaces[0].set_ip(new_ip)
		elif self.routers[1].get_name() == src_router_str and self.routers[0].get_name() == dst_router_str:
			self.interfaces[1].set_ip(new_ip)


NETWORK = [Link((Router("FRA"), Router("HAM")), (Interface("port_HAM", "X.0.1.1/24"), Interface("port_FRA", "X.0.1.2/24"))),
		   Link((Router("FRA"), Router("BER")), (Interface("port_BER", "X.0.2.1/24"), Interface("port_FRA", "X.0.2.2/24"))),
		   Link((Router("FRA"), Router("DRS")), (Interface("port_DRS", "X.0.3.1/24"), Interface("port_FRA", "X.0.3.2/24"))),
		   Link((Router("FRA"), Router("MUC")), (Interface("port_MUC", "X.0.4.1/24"), Interface("port_FRA", "X.0.4.2/24"))),
		   Link((Router("FRA"), Router("ZRH")), (Interface("port_ZRH", "X.0.5.1/24"), Interface("port_FRA", "X.0.5.2/24"))),
		   Link((Router("FRA"), Router("AMS")), (Interface("port_AMS", "X.0.6.1/24"), Interface("port_FRA", "X.0.6.2/24"))),
		   Link((Router("AMS"), Router("HAM")), (Interface("port_HAM", "X.0.7.1/24"), Interface("port_AMS", "X.0.7.2/24"))),
		   Link((Router("HAM"), Router("BER")), (Interface("port_BER", "X.0.8.1/24"), Interface("port_HAM", "X.0.8.2/24"))),
		   Link((Router("BER"), Router("DRS")), (Interface("port_DRS", "X.0.9.1/24"), Interface("port_BER", "X.0.9.2/24"))),
		   Link((Router("DRS"), Router("PRG")), (Interface("port_PRG", "X.0.10.1/24"), Interface("port_DRS", "X.0.10.2/24"))),
		   Link((Router("PRG"), Router("MUC")), (Interface("port_MUC", "X.0.11.1/24"), Interface("port_PRG", "X.0.11.2/24"))),
		   Link((Router("MUC"), Router("ZRH")), (Interface("port_ZRH", "X.0.12.1/24"), Interface("port_MUC", "X.0.12.2/24")))]


def get_interface_ip(src_router_str, dst_router_str):
	for link in NETWORK:
		ip = link.get_interface_ip(src_router_str, dst_router_str)
		if ip is not None:
			return ip
	return None


def set_interface_ip(src_router_str, dst_router_str, new_ip):
	for link in NETWORK:
		link.set_interface_ip(src_router_str, dst_router_str, new_ip)


def take_random_subnet(subnet_list):
	import random
	if not subnet_list:
		raise Exception("No more new subnets available.")
	new_subnet = random.choice(subnet_list)
	subnet_list.remove(new_subnet)
	return new_subnet

def get_network_ascii(network):
	ascii_art = "\nNetwork Configuration:\n\n"
	ascii_art += f"[AMS]-({get_interface_ip("AMS", "HAM")})--------({get_interface_ip("HAM", "AMS")})-[HAM]-({get_interface_ip("HAM", "BER")})--------({get_interface_ip("BER", "HAM")})-[BER]\n"
	ascii_art += f"  \\                                          /               __________({get_interface_ip("BER", "FRA")})_/ |\n"
	ascii_art += f"({get_interface_ip("AMS", "FRA")})                           ({get_interface_ip("HAM", "FRA")})     /                        ({get_interface_ip("BER", "DRS")})\n"
	ascii_art += f"    \\                                      /               /                            |\n"
	ascii_art += f"     \\                                    /               /                             |\n"
	ascii_art += f"      \\                                  /               /                              |\n"
	ascii_art += f"       --({get_interface_ip("FRA", "AMS")})  ({get_interface_ip("FRA", "HAM")})--               /                               |\n"
	ascii_art += f"                     \\   / _({get_interface_ip("FRA", "BER")})--------------                             ({get_interface_ip("DRS", "BER")})\n"
	ascii_art += f"                      \\ / /                                                             |\n"
	ascii_art += f"                     [FRA]-({get_interface_ip("FRA", "DRS")})------------------------------({get_interface_ip("DRS", "FRA")})-[DRS]\n"
	ascii_art += f"                      / \\                                                               |\n"
	ascii_art += f"                     /   \\                                                           ({get_interface_ip("DRS", "PRG")})\n"
	ascii_art += f"        _({get_interface_ip("FRA", "ZRH")})  ({get_interface_ip("FRA", "MUC")})_                                                |\n"
	ascii_art += f"       /                                \\                                               |\n"
	ascii_art += f"      /                                  \\                                              |\n"
	ascii_art += f"     /                                    \\                                             |\n"
	ascii_art += f" ({get_interface_ip("ZRH", "FRA")})                         ({get_interface_ip("MUC", "FRA")})                               ({get_interface_ip("PRG", "DRS")})\n"
	ascii_art += f"   /                                        \\                                           |\n"
	ascii_art += f"[ZRH]-({get_interface_ip("ZRH", "MUC")})--------({get_interface_ip("MUC", "ZRH")})-[MUC]-({get_interface_ip("MUC", "PRG")})--------({get_interface_ip("PRG", "MUC")})-[PRG]\n\n"
	return ascii_art


def generate_frr_script(path, container, interface, new_ip, new_network, ospf_area="0"):
    """
    Generiert ein ausführbares Bash-Skript für FRR-IP- und OSPF-Änderungen.
    """
    # Die doppelten geschweiften Klammern {{ }} bei awk verhindern, 
    # dass Python sie als f-String-Variablen interpretiert.
    bash_template = f"""#!/bin/bash

# Auto-generated FRR configuration script for {container}
# Target Interface: {interface}

CONTAINER="{container}"
INTERFACE="{interface}"
NEW_IP="{new_ip}"
NEW_NETWORK="{new_network}"
OSPF_AREA="{ospf_area}"

echo "Checking current IP on $INTERFACE inside $CONTAINER..."

# Fetch the current IP address dynamically from FRR
OLD_IP=$(docker exec $CONTAINER vtysh -c "show interface $INTERFACE" | grep -w "inet" | awk '{{print $2}}')

if [ -z "$OLD_IP" ]; then
    echo "No IPv4 address found on $INTERFACE. Exiting."
    exit 1
fi

echo "Found existing IP: $OLD_IP. Replacing with $NEW_IP..."

# Apply the configuration
docker exec $CONTAINER vtysh \\
  -c "configure terminal" \\
  -c "interface $INTERFACE" \\
  -c "no ip address $OLD_IP" \\
  -c "ip address $NEW_IP" \\
  -c "exit" \\
  -c "router ospf" \\
  -c "network $NEW_NETWORK area $OSPF_AREA" \\
  -c "exit"

echo "Configuration applied and saved successfully to $CONTAINER."
"""
    
    # Dateinamen basierend auf Container und Interface generieren
    filename = f"update_{container}_{interface}.sh"
    
    # Skript schreiben
    with open(f"{path}/{filename}", "w") as f:
        f.write(bash_template)
    
    print(f"Erfolg: Skript erstellt -> {filename}")


# main
if __name__ == "__main__":
	for group in GROUPS:
		# create group folder if not exists
		path = f"shuffle_subnets/group_{group}"
		if not os.path.exists(path):
			os.makedirs(path)
		subnet_list = NEW_SUBNETS.copy()
		for link in NETWORK:
			new_subnet = take_random_subnet(subnet_list)
			set_interface_ip(link.get_routers()[0].get_name(), link.get_routers()[1].get_name(), f"{group}.0.{new_subnet}.1/24")
			set_interface_ip(link.get_routers()[1].get_name(), link.get_routers()[0].get_name(), f"{group}.0.{new_subnet}.2/24")
			container0_name = f"{group}_{link.get_routers()[0].get_name()}router"
			interface0_name = link.get_interfaces()[0].get_name()
			container1_name = f"{group}_{link.get_routers()[1].get_name()}router"
			interface1_name = link.get_interfaces()[1].get_name()
			generate_frr_script(path, container0_name, interface0_name, f"{group}.0.{new_subnet}.1/24", f"{group}.0.{new_subnet}.0/24")
			generate_frr_script(path, container1_name, interface1_name, f"{group}.0.{new_subnet}.2/24", f"{group}.0.{new_subnet}.0/24")
		print(get_network_ascii(NETWORK))
		# create script to run each generated script in the group folder one line per script
		with open(f"{path}/run_all_group{group}.sh", "w") as f:
			f.write("#!/bin/bash\n\n")
			f.write(f": <<'COMMENT'\n")
			f.write(get_network_ascii(NETWORK))
			f.write(f"COMMENT\n\n")
			for link in NETWORK:
				container0_name = f"{group}_{link.get_routers()[0].get_name()}router"
				interface0_name = link.get_interfaces()[0].get_name()
				container1_name = f"{group}_{link.get_routers()[1].get_name()}router"
				interface1_name = link.get_interfaces()[1].get_name()
				f.write(f"bash update_{container0_name}_{interface0_name}.sh\n")
				f.write(f"bash update_{container1_name}_{interface1_name}.sh\n")
		# create script to run each group script
		with open(f"shuffle_subnets/run_all_groups.sh", "w") as f:
			f.write("#!/bin/bash\n")
			for group in GROUPS:
				f.write(f"bash group_{group}/run_all_group{group}.sh\n")
