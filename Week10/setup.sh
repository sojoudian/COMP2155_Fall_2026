#!/bin/sh
# Week 10: two Cisco 7200 routers on the LAN of your computer.
#
#   curl -fsSL https://raw.githubusercontent.com/sojoudian/COMP2155_Fall_2026/master/Week10/setup.sh | bash
#
# 1. It installs tessera (https://tessera.rest/install.sh).
# 2. It writes the lab to ~/tessera-week10: wk10.yaml, R1.cfg and R2.cfg.
#    A config that is there already does not change (your "write memory").
# 3. It starts R1 and R2 with "sudo tessera lab up wk10.yaml --lan". Each
#    router gets a free address of your LAN on FastEthernet0/0.
#
# Stop the routers: sudo tessera lab down ~/tessera-week10/wk10.yaml
#
# All the work is in functions, and the last line calls them: a cut
# download does not run half a script.

set -eu

LAB_DIR="${HOME}/tessera-week10"

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
 transport input ssh
!
ntp server 34.208.249.133
ntp server pool.ntp.org
!
end
EOF
}

write_lab() {
	mkdir -p "$LAB_DIR"
	cat >"$LAB_DIR/wk10.yaml" <<'EOF'
# Week 10: two Cisco 7200 routers (NPE-400, 15.2(4)S6) on one switch.
# With --lan, the switch is on the LAN of this computer, and each router gets
# a free LAN address on FastEthernet0/0.
# User: admin / cisco123 (privilege 15).
name: week10
platform: c7200
routers:
  - name: R1
    node-id: 1
    config: R1.cfg
    ssh-port: 22610
    telnet-port: -1
  - name: R2
    node-id: 2
    config: R2.cfg
    ssh-port: 22620
    telnet-port: -1
switches:
  - name: SW1
links:
  - [R1:FastEthernet0/0, SW1]
  - [R2:FastEthernet0/0, SW1]
EOF
	# The secrets are IOS hashes: no expansion.
	# shellcheck disable=SC2016
	[ -f "$LAB_DIR/R1.cfg" ] || config R1 '$1$vwf3$VU/7dT4bv5xV09cCsY2QY.' 10.1.1.10 >"$LAB_DIR/R1.cfg"
	# shellcheck disable=SC2016
	[ -f "$LAB_DIR/R2.cfg" ] || config R2 '$1$kzaF$yOPk/X/AWa6/iH1p02OB/0' 10.1.1.20 >"$LAB_DIR/R2.cfg"
}

main() {
	case "$(uname -s)" in
	Darwin | Linux) ;;
	*) fatal "Use setup.ps1 on Windows: irm https://raw.githubusercontent.com/sojoudian/COMP2155_Fall_2026/master/Week10/setup.ps1 | iex" ;;
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
	if as_root "$TESSERA" lab status wk10.yaml >/dev/null 2>&1; then
		printf 'The lab runs. Stop it first.\n'
		as_root "$TESSERA" lab down wk10.yaml
	fi

	printf '\n== 3. Start R1 and R2 on your LAN\n'
	as_root "$TESSERA" lab up wk10.yaml --lan

	printf '\nConnect:  ssh -o KexAlgorithms=+diffie-hellman-group14-sha1 -o HostKeyAlgorithms=+ssh-rsa -o Ciphers=+aes128-cbc admin@ADDRESS\n'
	printf 'Password: cisco123. ADDRESS is in the table above.\n'
	printf 'Stop:     sudo tessera lab down %s/wk10.yaml\n\n' "$LAB_DIR"
}

main "$@"
