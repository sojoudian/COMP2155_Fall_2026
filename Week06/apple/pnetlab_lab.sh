#!/bin/bash
# pnetlab_lab.sh - start or stop the PNETLab VM in UTM and the lab /Labs/lab05.unl (R1) on an Apple Silicon Mac.
#
# Usage:
#   ./pnetlab_lab.sh start   # start the VM, start all nodes of lab05, wait until R1 accepts SSH
#   ./pnetlab_lab.sh stop    # stop all nodes of lab05, then shut down the VM
#
# The script connects to the VM as root with SSH and asks for the root password one time.
# PNET_PASSWORD (env) : the VM root password. With it, the script does not ask.
# VM_NAME (env)       : the UTM VM name (default: PNETLab).
# PNET_IP (env)       : the VM IP. Without it, the script finds the IP in the macOS DHCP leases.
#
# Before the first start: create the VM (README.md) and run pnetlab_rebuild.sh on it (creates lab05).
set -euo pipefail

VM_NAME=${VM_NAME:-PNETLab}
PNET_IP=${PNET_IP:-}
PNET_PASSWORD=${PNET_PASSWORD:-}
UTMCTL=/Applications/UTM.app/Contents/MacOS/utmctl
BOOT_TIMEOUT=600   # seconds. Under emulation, PNETLab starts in 1 to 3 minutes.
R1_TIMEOUT=900     # The first start of R1 makes a 2048-bit RSA key. Under emulation, this takes 6 to 10 minutes.
STOP_TIMEOUT=180

log() { echo -e "\033[1;32m[+]\033[0m $*" >&2; }
warn() { echo -e "\033[1;33m[!]\033[0m $*" >&2; }
die() { echo -e "\033[1;31m[-]\033[0m $*" >&2; exit 1; }

usage() { sed -n '2,13p' "$0"; exit 1; }

# This part runs on the VM as root. It finds the admin lab session of lab05, or creates it
# (the same as when admin opens the lab in the web UI), then starts or stops all nodes of the lab.
# On start, it writes "<R1 Ethernet0/1 IP> <1 if the R1 NVRAM has a saved RSA key, else 0>" to stdout.
# R1 boots from its NVRAM when the NVRAM has a saved config. Else, it boots from the lab startup-config.
# "save" does "write memory" on R1 through its console port.
read -r -d '' REMOTE <<'REMOTE_EOF' || true
set -euo pipefail
ACTION=$1
LAB_FILE=/opt/unetlab/labs/Labs/lab05.unl
LAB_PATH=/Labs/lab05.unl
[ -f "$LAB_FILE" ] || { echo "Missing $LAB_FILE. Run pnetlab_rebuild.sh on the VM first." >&2; exit 2; }

SESSION=$(php -- "$LAB_FILE" "$LAB_PATH" "$ACTION" <<'PHP'
<?php
require "/opt/unetlab/html/includes/init.php";
list(, $file, $path, $action) = $argv;
$pod = null;
foreach (getAllUser() as $u) {
    if ($u["username"] === "admin") $pod = (int) $u["pod"];
}
if ($pod === null) { fwrite(STDERR, "The PNETLab user admin does not exist.\n"); exit(1); }
$lab = new Lab($file, $pod, null);
$sid = (int) getUserByPod($pod)["lab_session"];
$s = $sid > 0 ? getLabFromSession($sid) : null;
if (!$s || $s["lab_session_lid"] !== $lab->getId()) {
    $sid = 0;
    if ($action === "start") {
        $r = addLabSession($lab->getId(), $pod, $path);
        if (empty($r["result"])) { fwrite(STDERR, "addLabSession failed: " . $r["message"] . "\n"); exit(1); }
        $sid = (int) getUserByPod($pod)["lab_session"];
    }
}
echo "$pod $sid\n";
PHP
)
read -r POD SID <<< "$SESSION"

# The iol_wrapper process of R1 (node 1). Its working directory holds the R1 NVRAM file.
r1_pid() { pgrep -f "^/opt/unetlab/wrappers/iol_wrapper -D 1 -S $SID " | head -n1; }

# Print the Ethernet0/1 IP from a config on stdin.
e01_ip() { awk '/^interface Ethernet0\/1/ {f = 1} f && /^ ip address/ {print $3; exit}'; }

case $ACTION in
    start)
        [ "$SID" -gt 0 ] || { echo "No lab session for lab05." >&2; exit 1; }
        # unl_wrapper does not start a node that already runs.
        # stdin from /dev/null: the node processes must not keep the SSH channel open.
        if ! out=$(/opt/unetlab/wrappers/unl_wrapper -a start -T "$POD" -S "$SID" -F "$LAB_FILE" </dev/null 2>&1); then
            echo "$out" >&2; exit 1
        fi
        PID=$(r1_pid) || true
        [ -n "$PID" ] || { echo "R1 does not run after the start." >&2; exit 1; }
        NVRAM=$(ls "$(readlink "/proc/$PID/cwd")"/nvram_* 2>/dev/null | head -n1) || true
        if [ -n "$NVRAM" ] && grep -aq 'RSA-key-pair' "$NVRAM"; then
            echo "$(strings "$NVRAM" | e01_ip) 1"
        else
            echo "$(grep -o 'config_data="[^"]*"' "$LAB_FILE" | head -n1 | cut -d'"' -f2 | base64 -d | e01_ip) 0"
        fi
        ;;
    save)
        PID=$(r1_pid) || true
        [ -n "$PID" ] || { echo "R1 does not run." >&2; exit 1; }
        PORT=$(tr '\0' ' ' < "/proc/$PID/cmdline" | grep -o -- '-P [0-9]*' | cut -d' ' -f2)
        python3 - "$PORT" <<'PY'
import socket, sys, time
s = socket.create_connection(("127.0.0.1", int(sys.argv[1])), timeout=10)
s.settimeout(0.5)

def read(seconds):
    out, end = b"", time.time() + seconds
    while time.time() < end:
        try:
            data = s.recv(4096)
        except socket.timeout:
            continue
        if not data:
            break
        out += data
    return out.decode("latin-1")

def cmd(line, seconds):
    s.sendall(line.encode() + b"\r")
    return read(seconds)

s.sendall(bytes([255, 253, 1, 255, 253, 3, 255, 253, 0, 255, 251, 0]))  # telnet: DO echo, DO SGA, DO/WILL binary
read(1)
cmd("", 2)
cmd("\x1a", 2)  # Ctrl+Z: leave config mode
if "Password" in cmd("enable", 3):
    sys.exit("R1 enable needs a password")
out, end = cmd("write memory", 5), time.time() + 120
while "[OK]" not in out and time.time() < end:
    out += read(2)
cmd("disable", 1)
sys.exit(0 if "[OK]" in out else "R1 write memory did not show [OK]")
PY
        ;;
    stop)
        if [ "$SID" -gt 0 ]; then
            if ! out=$(/opt/unetlab/wrappers/unl_wrapper -a stop -T "$POD" -S "$SID" -F "$LAB_FILE" </dev/null 2>&1); then
                echo "$out" >&2; exit 1
            fi
        fi
        ;;
esac
REMOTE_EOF

vm_status() { "$UTMCTL" status "$VM_NAME" 2>/dev/null || echo unknown; }

vm_started() { [ "$(vm_status)" = started ]; }

port_open() { nc -z -G 2 "$1" "$2" >/dev/null 2>&1; }

web_up() { [[ $(curl -s -o /dev/null -m 5 -w '%{http_code}' "http://$1/") =~ ^[23] ]]; }

# Wait until a command succeeds: wait_for <seconds> <description> <command...>
wait_for() {
    local timeout=$1 what=$2 end
    shift 2
    end=$((SECONDS + timeout))
    until "$@"; do
        [ "$SECONDS" -lt "$end" ] || die "Timeout after $timeout s: $what"
        sleep 3
    done
}

# The VM IP from the macOS DHCP leases of the UTM Shared Network, found by the VM MAC address.
vm_ip() {
    local mac
    if [ -n "$PNET_IP" ]; then echo "$PNET_IP"; return 0; fi
    mac=$(osascript -e "tell application \"UTM\" to get address of item 1 of network interfaces of (get configuration of virtual machine named \"$VM_NAME\")" 2>/dev/null) || return 1
    # The lease file uses lowercase hex digits without leading zeros (for example 0a -> a).
    mac=$(echo "$mac" | tr 'A-F' 'a-f' | awk -F: -v OFS=: '{for (i = 1; i <= NF; i++) sub(/^0/, "", $i); print}')
    awk -v mac="$mac" '
        /ip_address=/ {ip = substr($0, index($0, "=") + 1)}
        /hw_address=/ {hw = substr($0, index($0, ",") + 1)}
        /^}/ {if (hw == mac && found == "") found = ip; ip = hw = ""}
        END {if (found == "") exit 1; print found}' /var/db/dhcpd_leases 2>/dev/null
}

wait_for_ip() {
    local end=$((SECONDS + BOOT_TIMEOUT))
    until IP=$(vm_ip); do
        [ "$SECONDS" -lt "$end" ] || die "Timeout: no IP address for VM $VM_NAME (set PNET_IP)"
        sleep 3
    done
}

# One SSH login (one password prompt) for all commands: a master connection that the other commands share.
SSH_DIR=$(mktemp -d)
IP=""
SSH_OPTS=(-o ControlPath="$SSH_DIR/ctl" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
          -o LogLevel=ERROR -o ConnectTimeout=10)
cleanup() {
    [ -n "$IP" ] && ssh "${SSH_OPTS[@]}" -O exit root@"$IP" >/dev/null 2>&1 || true
    rm -rf "$SSH_DIR"
}
trap cleanup EXIT
if [ -n "$PNET_PASSWORD" ]; then
    printf '#!/bin/sh\nprintf "%%s\\n" "$PNET_PASSWORD"\n' > "$SSH_DIR/askpass"
    chmod 700 "$SSH_DIR/askpass"
    export PNET_PASSWORD SSH_ASKPASS="$SSH_DIR/askpass" SSH_ASKPASS_REQUIRE=force
fi

ssh_login() {
    log "Logging in to the VM as root ($IP)"
    ssh "${SSH_OPTS[@]}" -M -f -N root@"$IP" || die "SSH login to root@$IP failed"
}

vm_ssh() { ssh "${SSH_OPTS[@]}" -o ControlMaster=no root@"$IP" "$@"; }

cmd_start() {
    local status out r1_ip saved
    status=$(vm_status)
    case $status in
        started) log "VM $VM_NAME already runs" ;;
        stopped|paused|suspended)
            log "Starting VM $VM_NAME"
            "$UTMCTL" start "$VM_NAME" || die "utmctl could not start VM $VM_NAME"
            ;;
        unknown) die "UTM has no VM with the name $VM_NAME (set VM_NAME)" ;;
        *) log "VM $VM_NAME is $status" ;;
    esac
    wait_for "$BOOT_TIMEOUT" "VM $VM_NAME state started" vm_started

    wait_for_ip
    log "Waiting for PNETLab at $IP"
    wait_for "$BOOT_TIMEOUT" "SSH on $IP" port_open "$IP" 22
    wait_for "$BOOT_TIMEOUT" "web UI on http://$IP/" web_up "$IP"

    ssh_login
    log "Starting the nodes of lab05"
    out=$(vm_ssh bash -s -- start <<< "$REMOTE") || die "The nodes of lab05 did not start"
    read -r r1_ip saved <<< "$out"
    [[ $r1_ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || die "No Ethernet0/1 IP in the R1 config"

    if [ "$saved" = 1 ]; then
        log "Waiting for SSH on R1 ($r1_ip)"
    else
        log "Waiting for SSH on R1 ($r1_ip). R1 makes its RSA key now. Under emulation, this takes 6 to 10 minutes."
    fi
    wait_for "$R1_TIMEOUT" "SSH on R1 $r1_ip" port_open "$r1_ip" 22

    if [ "$saved" != 1 ]; then
        # With the config and the RSA key in NVRAM, the next start of R1 takes about 1 minute.
        log "Saving the R1 config and RSA key to NVRAM (write memory)"
        vm_ssh bash -s -- save <<< "$REMOTE" || warn "write memory on R1 failed. The next start makes a new RSA key again."
    fi

    log "The lab runs."
    cat <<EOF

  PNETLab web UI : http://$IP/   (Offline Mode, user admin)
  R1 SSH         : ssh -o KexAlgorithms=+diffie-hellman-group14-sha1 -o HostKeyAlgorithms=+ssh-rsa admin@$r1_ip
  Stop the lab   : $0 stop

EOF
}

cmd_stop() {
    local status
    status=$(vm_status)
    case $status in
        stopped) log "VM $VM_NAME is already stopped"; return 0 ;;
        unknown) die "UTM has no VM with the name $VM_NAME (set VM_NAME)" ;;
        started) ;;
        *) warn "VM $VM_NAME is $status. Stopping it with utmctl"; "$UTMCTL" stop "$VM_NAME" --force; return 0 ;;
    esac

    if IP=$(vm_ip) && port_open "$IP" 22; then
        ssh_login
        log "Stopping the nodes of lab05"
        vm_ssh bash -s -- stop <<< "$REMOTE" || warn "The nodes of lab05 did not stop. The VM shutdown stops them."
        log "Shutting down VM $VM_NAME"
        vm_ssh systemctl poweroff >/dev/null 2>&1 || true
    else
        IP=""
        warn "No SSH to the VM. Sending a power-down request to VM $VM_NAME"
        "$UTMCTL" stop "$VM_NAME" --request || true
    fi

    local end=$((SECONDS + STOP_TIMEOUT))
    until [ "$(vm_status)" = stopped ]; do
        if [ "$SECONDS" -ge "$end" ]; then
            warn "VM $VM_NAME did not shut down in $STOP_TIMEOUT s. Forcing it off"
            "$UTMCTL" stop "$VM_NAME" --force
            break
        fi
        sleep 3
    done
    log "VM $VM_NAME is stopped."
}

[ -x "$UTMCTL" ] || die "UTM is not installed ($UTMCTL not found)"
case ${1:-} in
    start) cmd_start ;;
    stop) cmd_stop ;;
    *) usage ;;
esac
