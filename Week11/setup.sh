#!/bin/sh
# Week 11: three Cisco routers on the LAN of your computer.
#
#   curl -fsSL https://raw.githubusercontent.com/sojoudian/COMP2155_Fall_2026/master/Week11/setup.sh | bash
#
# 1. It installs tessera (https://tessera.rest/install.sh).
# 2. It writes the lab to ~/.tessera/week11: week11.yaml, R1.cfg, R2.cfg and
#    R3.cfg.
#    A config that is there already does not change (your "write memory").
# 3. It starts R1, R2 and R3 with "sudo tessera lab up week11.yaml --lan". Each
#    router gets a free address of your LAN: FastEthernet0/0 on R1 and R2
#    (Cisco 7200), Ethernet0/0 on R3 (Cisco IOL).
#
# Stop the routers: sudo tessera lab down ~/.tessera/week11/week11.yaml
# Remove all of it: uninstall.sh in the same folder.
#
# All the work is in functions, and the last line calls them: a cut
# download does not run half a script.

set -eu

LAB_DIR="${HOME}/.tessera/week11"

fatal() {
	printf 'error: %s\n' "$1" >&2
	exit 1
}

# as_root CMD...: run CMD as root (sudo when this is not root).
as_root() {
	if [ "$(id -u)" = 0 ]; then
		"$@"
	else
		sudo "$@"
	fi
}

# config NAME SECRET IP: the startup config of a 7206VXR (15.2(4)S6). The
# lab gives FastEthernet0/0 a free LAN address after the start.
config() {
	sed -e "s|@HOST@|$1|" -e "s|@SECRET@|$2|" -e "s|@IP@|$3|" <<'EOF'
!
version 15.2
service timestamps debug datetime msec
service timestamps log datetime msec
!
hostname @HOST@
!
boot-start-marker
boot-end-marker
!
!
enable secret 5 @SECRET@
!
no aaa new-model
!
!
!
!
!
!
no ip domain lookup
ip domain name lab.local
ip cef
no ipv6 cef
!
!
multilink bundle-name authenticated
!
!
!
!
!
!
!
username admin privilege 15 secret 5 $1$RyKC$JYsD/nugZHXiYAPU/UUzH/
!
!
!
!
!
ip ssh version 2
ip scp server enable
! 
!
!
!
!
!
!
!
!
interface FastEthernet0/0
 ip address @IP@ 255.255.255.0
 duplex full
!
interface FastEthernet1/0
 no ip address
 shutdown
 duplex full
!
interface FastEthernet2/0
 no ip address
 shutdown
 duplex full
!
interface FastEthernet3/0
 no ip address
 shutdown
 duplex full
!
ip forward-protocol nd
!
!
no ip http server
no ip http secure-server
!
!
!
!
control-plane
!
!
line con 0
 logging synchronous
 stopbits 1
line aux 0
 stopbits 1
line vty 0 4
 login local
 transport input telnet ssh
!
ntp server 34.208.249.133
ntp server pool.ntp.org
!
end
EOF
}

# config_iol NAME SECRET IP: the startup config of an IOL router (15.7(3)M2).
# The lab gives Ethernet0/0 a free LAN address after the start.
config_iol() {
	sed -e "s|@HOST@|$1|" -e "s|@SECRET@|$2|" -e "s|@IP@|$3|" <<'EOF'
!
version 15.7
service timestamps debug datetime msec
service timestamps log datetime msec
no service password-encryption
!
hostname @HOST@
!
boot-start-marker
boot-end-marker
!
!
enable secret 5 @SECRET@
!
no aaa new-model
!
!
!
mmi polling-interval 60
no mmi auto-configure
no mmi pvc
mmi snmp-timeout 180
!
!
!
!
!
!
!
!
!
!
!
!
!
!
!


!
!
!
!
no ip domain lookup
ip domain name lab.local
ip cef
no ipv6 cef
!
multilink bundle-name authenticated
!
!
!
!
!
!
!
!
!
username admin privilege 15 secret 5 $1$RyKC$JYsD/nugZHXiYAPU/UUzH/
!
redundancy
!
!
! 
!
!
!
!
!
!
!
!
!
!
!
!
interface Ethernet0/0
 ip address @IP@ 255.255.255.0
 duplex auto
!
interface Ethernet0/1
 no ip address
 shutdown
 duplex auto
!
interface Ethernet0/2
 no ip address
 shutdown
 duplex auto
!
interface Ethernet0/3
 no ip address
 shutdown
 duplex auto
!
ip forward-protocol nd
!
!
no ip http server
no ip http secure-server
ip ssh version 2
ip scp server enable
!
ipv6 ioam timestamp
!
!
!
control-plane
!
!
!
!
!
!
!
!
line con 0
 logging synchronous
line aux 0
line vty 0 4
 login local
 transport input telnet ssh
!
ntp server 34.208.249.133
ntp server pool.ntp.org
!
end
EOF
}

# lan_address NAME: the LAN address of the router NAME ("": not found). It
# reads the address table of "tessera lab status".
lan_address() {
	as_root "$TESSERA" lab status week11.yaml 2>/dev/null | awk -v r="$1" '
		$1 == r { for (i = 2; i <= NF; i++) if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) { print $i; exit } }'
}

write_lab() {
	mkdir -p "$LAB_DIR"
	cat >"$LAB_DIR/week11.yaml" <<'EOF'
# Week 11: two Cisco 7200 routers (NPE-400, 15.2(4)S6) and one Cisco IOL
# router (15.7(3)M2) on one switch.
# With --lan, the switch is on the LAN of this computer, and each router gets
# a free LAN address: FastEthernet0/0 on R1 and R2, Ethernet0/0 on R3.
# User: admin / cisco123 (privilege 15). SSH and telnet are on.
name: week11
routers:
  - name: R1
    platform: c7200
    node-id: 1
    config: R1.cfg
    ssh-port: 22710
    telnet-port: 23710
  - name: R2
    platform: c7200
    node-id: 2
    config: R2.cfg
    ssh-port: 22720
    telnet-port: 23720
  - name: R3
    platform: iol
    node-id: 3
    config: R3.cfg
    ssh-port: 22730
    telnet-port: 23730
switches:
  - name: SW1
links:
  - [R1:FastEthernet0/0, SW1]
  - [R2:FastEthernet0/0, SW1]
  - [R3:Ethernet0/0, SW1]
EOF
	# The secrets are IOS hashes: no expansion.
	# shellcheck disable=SC2016
	[ -f "$LAB_DIR/R1.cfg" ] || config R1 '$1$vwf3$VU/7dT4bv5xV09cCsY2QY.' 10.1.1.10 >"$LAB_DIR/R1.cfg"
	# shellcheck disable=SC2016
	[ -f "$LAB_DIR/R2.cfg" ] || config R2 '$1$kzaF$yOPk/X/AWa6/iH1p02OB/0' 10.1.1.20 >"$LAB_DIR/R2.cfg"
	# shellcheck disable=SC2016
	[ -f "$LAB_DIR/R3.cfg" ] || config_iol R3 '$1$g8kd$I2Z8fh158yBUJAAAoL9dl/' 10.1.1.30 >"$LAB_DIR/R3.cfg"
}

main() {
	case "$(uname -s)" in
	Darwin | Linux) ;;
	*) fatal "Use setup.ps1 on Windows: irm https://raw.githubusercontent.com/sojoudian/COMP2155_Fall_2026/master/Week11/setup.ps1 | iex" ;;
	esac
	command -v curl >/dev/null 2>&1 || fatal "curl is necessary."

	printf '\n== 1. Install tessera\n'
	curl -fsSL https://tessera.rest/install.sh | bash
	TESSERA=""
	for t in "${TESSERA_INSTALL_DIR:-/nonexistent}/tessera" /usr/local/bin/tessera "$HOME/.local/bin/tessera"; do
		if [ -x "$t" ]; then
			TESSERA="$t"
			break
		fi
	done
	[ -n "$TESSERA" ] || fatal "tessera is not installed. See the error above."

	printf '\n== 2. Write the lab to %s (sudo can ask for your password)\n' "$LAB_DIR"
	write_lab
	cd "$LAB_DIR"
	if as_root "$TESSERA" lab status week11.yaml >/dev/null 2>&1; then
		printf 'The lab runs. Stop it first.\n'
		as_root "$TESSERA" lab down week11.yaml
	fi

	printf '\n== 3. Start R1, R2 and R3 on your LAN\n'
	# --quiet (only the router table) is not in tessera 0.0.6 and older.
	if "$TESSERA" lab help up 2>&1 | grep -q -- --quiet; then
		as_root "$TESSERA" lab up week11.yaml --lan --quiet
	else
		as_root "$TESSERA" lab up week11.yaml --lan
	fi

	# The addresses of R1 and R3 for the lines below.
	R1_IP="$(lan_address R1)"
	R3_IP="$(lan_address R3)"
	[ -n "$R1_IP" ] || R1_IP=ADDRESS
	[ -n "$R3_IP" ] || R3_IP=ADDRESS
	printf '\nConnect:  ssh -o KexAlgorithms=+diffie-hellman-group14-sha1 -o HostKeyAlgorithms=+ssh-rsa -o Ciphers=+aes128-cbc -o MACs=+hmac-sha1 admin@%s\n\n' "$R1_IP"
	printf 'R3 (IOL): ssh admin@%s\n' "$R3_IP"
	printf 'Telnet:   telnet %s\n' "$R1_IP"
	if [ "$R1_IP" = ADDRESS ]; then
		printf 'User: admin. Password: cisco123. ADDRESS is in the table above.\n'
	else
		printf 'User: admin. Password: cisco123.\n'
	fi
	printf 'Stop:     sudo tessera lab down %s/week11.yaml\n\n' "$LAB_DIR"
}

main "$@"
