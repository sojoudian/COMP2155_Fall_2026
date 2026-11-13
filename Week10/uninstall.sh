#!/bin/sh
# Week 10: remove all that setup.sh did (macOS and Linux).
#
#   curl -fsSL https://raw.githubusercontent.com/sojoudian/COMP2155_Fall_2026/master/Week10/uninstall.sh | bash
#
# 1. It stops R1 and R2 ("sudo tessera lab down"). It also stops the
#    tessera processes of the lab that still run (for example after the lab
#    folder was deleted). Their utun or tun device and routes go with them.
# 2. It removes the lab folder ~/tessera-week10, with your saved configs.
# 3. On macOS, it removes tessera from the application firewall list.
# 4. It removes tessera (https://tessera.rest/install.sh --uninstall).
#
# All the work is in functions, and the last line calls them: a cut
# download does not run half a script.

set -eu

LAB_DIR="${HOME}/tessera-week10"
FIREWALL=/usr/libexec/ApplicationFirewall/socketfilterfw

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

# binaries: the tessera files that install.sh can install.
binaries() {
	for t in ${TESSERA_INSTALL_DIR:+"$TESSERA_INSTALL_DIR/tessera"} /usr/local/bin/tessera "$HOME/.local/bin/tessera"; do
		[ -x "$t" ] && printf '%s\n' "$t"
	done
	return 0
}

# lab_pids: the processes that use a file in the lab folder.
lab_pids() {
	# The folder is in the environment, not in the argv of awk: awk does
	# not find itself.
	ps -A -ww -o pid= -o args= | D="$LAB_DIR/" awk 'index($0, ENVIRON["D"]) { print $1 }'
}

stop_lab() {
	tessera="$(binaries | head -n 1)"
	if [ -n "$tessera" ] && [ -f "$LAB_DIR/wk10.yaml" ]; then
		if (cd "$LAB_DIR" && as_root "$tessera" lab status wk10.yaml >/dev/null 2>&1); then
			(cd "$LAB_DIR" && as_root "$tessera" lab down wk10.yaml)
		else
			printf 'The lab does not run.\n'
		fi
	fi
	pids="$(lab_pids)"
	[ -n "$pids" ] || return 0
	printf 'Stopping the lab processes that still run:\n%s\n' "$pids"
	# shellcheck disable=SC2086 # one argument for each PID
	as_root kill $pids 2>/dev/null || true
	for _ in 1 2 3 4 5; do
		[ -n "$(lab_pids)" ] || return 0
		sleep 1
	done
	pids="$(lab_pids)"
	# shellcheck disable=SC2086
	[ -z "$pids" ] || as_root kill -9 $pids 2>/dev/null || true
}

remove_lab_dir() {
	case "$HOME" in
	"" | /) fatal "HOME is \"$HOME\": the lab folder is not clear." ;;
	esac
	if [ ! -e "$LAB_DIR" ]; then
		printf 'There is no %s.\n' "$LAB_DIR"
		return 0
	fi
	# The lab state (.crouter) belongs to root: lab up ran with sudo.
	rm -rf "$LAB_DIR" 2>/dev/null || as_root rm -rf "$LAB_DIR"
	printf 'Removed %s.\n' "$LAB_DIR"
}

remove_firewall_entries() {
	[ "$(uname -s)" = Darwin ] && [ -x "$FIREWALL" ] || return 0
	apps="$("$FIREWALL" --listapps 2>/dev/null || true)"
	for t in $(binaries); do
		case "$apps" in
		*"$t"*)
			as_root "$FIREWALL" --remove "$t" >/dev/null
			printf 'Removed %s from the application firewall.\n' "$t"
			;;
		esac
	done
}

main() {
	case "$(uname -s)" in
	Darwin | Linux) ;;
	*) fatal "Use uninstall.ps1 on Windows: irm https://raw.githubusercontent.com/sojoudian/COMP2155_Fall_2026/master/Week10/uninstall.ps1 | iex" ;;
	esac
	command -v curl >/dev/null 2>&1 || fatal "curl is necessary."

	printf '\n== 1. Stop R1 and R2 (sudo can ask for your password)\n'
	stop_lab

	printf '\n== 2. Remove the lab folder\n'
	remove_lab_dir

	printf '\n== 3. Remove tessera\n'
	remove_firewall_entries
	curl -fsSL https://tessera.rest/install.sh | bash -s -- --uninstall

	printf 'Week 10 is removed from this computer.\n\n'
}

main "$@"
