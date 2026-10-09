# Week 05: Cisco CSR 1000v in PNETLab and Paramiko

This continues the Week 04 lab (two Cisco 7200 routers with SSH key login). It adds a Cisco CSR 1000v router (R4) and runs commands on it from Python with Paramiko.

| Device | Interface | IP |
|--------|-----------|----|
| R1 | fa1/0 | 192.168.113.11 |
| R2 | fa1/0 | 192.168.113.12 |
| R4 (CSR 1000v) | Gi1 | 192.168.113.14 |

## 1. Download the CSR 1000v image (on the PNETLab VM)

```bash
ishare2 search csr
ishare2 pull qemu 102
```

`102` is the ID of `csr1000vng-universalk9.17.03.08a-serial` (IOS XE 17.03.08a, 1.1 GiB). Use the ID from your own search output.

Do not use `csr1000v-17-03-08a` (ID 88). It is the same IOS XE version packaged for Cisco CML, and ishare2 only downloads its 277-byte `.yaml` file, so the pull ends with `The image file size is too small`.

Check what is installed:

```bash
ishare2 installed all
```

### Optional: remove images you do not need

ishare2 has no delete command. Images are plain files, so remove them with `rm`:

| Type | Location | Remove with |
|------|----------|-------------|
| QEMU | `/opt/unetlab/addons/qemu/<image folder>/` | `rm -rf "<folder>"` |
| Dynamips | `/opt/unetlab/addons/dynamips/<file>.image` | `rm -f <file>` |
| IOL | `/opt/unetlab/addons/iol/bin/<file>.bin` | `rm -f <file>` |

Keep `iourc`, `CiscoIOUKeygen.py` and `keepalive.pl` in the IOL folder. A lab node that still points to a deleted image will not start until you select another image for it.

## 2. Add the CSR to the lab

1. Open the lab from Week 04.
2. Right-click the canvas → **Node** → Template: **Cisco CSR 1000V (XE 16.x)**. This is the template for `csr1000vng-...` images, including 17.x. The plain **Cisco CSR 1000V** template does not list this image.
3. Image: `csr1000vng-universalk9.17.03.08a-serial`. Name the node `R4` and keep the default CPU and RAM (4 CPUs, 6144 MB).
4. Connect `Gi1` of R4 to the existing **Management(Cloud0)** network.
5. Start R4 and click it to open the console.

The console stays blank for the first few minutes, and the first boot takes 5 to 10 minutes. Lines such as `partition ... has an invalid filesystem` and `This will cause a complete loss of data` are normal on the first boot. When you see:

```
Would you like to enter the initial configuration dialog? [yes/no]:
```

answer `no`.

## 3. Configure R4

```
enable
conf t
no service config
hostname R4
ip domain-name lab.local
int gi1
 ip address 192.168.113.14 255.255.255.0
 no shut
exit
crypto key generate rsa modulus 2048
ip ssh version 2
username admin privilege 15 secret cisco123
line vty 0 4
 login local
 transport input ssh
end
```

Check the interface with `show ip int br`.

## 4. Add your public key to R4

On Windows (Git Bash), print the key from Week 04 in 72-character lines:

```bash
fold -b -w 72 ~/.ssh/id_rsa.pub
```

On R4:

```
conf t
ip ssh pubkey-chain
 username admin
  key-string
   <paste all lines from the fold output>
  exit
end
wr
```

Verify with:

```
show run | section pubkey-chain
```

Then test from Git Bash. The `Host 192.168.113.*` block added to `~/.ssh/config` in Week 04 already covers this address:

```bash
ssh admin@192.168.113.14
```

You should land at the `R4#` prompt without a password. Do not continue to the Python part until this works.

## 5. Give the routers internet access

On each router:

```
conf t
ip route 0.0.0.0 0.0.0.0 192.168.113.2
ip name-server 8.8.8.8
ip domain-lookup
end
wr
```

Test:

```
ping 8.8.8.8
ping google.com
```

`192.168.113.2` is the default gateway of the VMware NAT network. To confirm yours, run this on the PNETLab VM and use the address after `via`:

```bash
ip route | grep default
```

## 6. Addressing note: why `10.0.0.4 255.255.255.252` is rejected

A `/30` mask splits addresses into blocks of 4. In each block the first address is the network ID and the last is the broadcast, so only the middle two can go on an interface:

| Block | Network | Usable hosts | Broadcast |
|-------|---------|--------------|-----------|
| 10.0.0.0/30 | 10.0.0.0 | 10.0.0.1, 10.0.0.2 | 10.0.0.3 |
| 10.0.0.4/30 | 10.0.0.4 | 10.0.0.5, 10.0.0.6 | 10.0.0.7 |

IOS answers `Bad mask /30 for address 10.0.0.4`. Two ways to fix it:

- Use the next block for a new link: `10.0.0.5` and `10.0.0.6` with `255.255.255.252`.
- Or widen the existing link to `/24` on both ends, which makes `10.0.0.4` a valid host on that link:

```
conf t
int fa0/0
 ip address 10.0.0.1 255.255.255.0
end
wr
```

(R2 gets `10.0.0.2 255.255.255.0`.)

Each cable between two routers is its own subnet. A router cannot have two interfaces in the same subnet, so a second link needs a different network, for example `10.0.1.1` and `10.0.1.2` with `255.255.255.0`.

## 7. Install Paramiko (Windows)

In the PyCharm terminal of your project:

```
pip install paramiko==4.0.0
```

Use version 4.0.0. Newer versions no longer include the `ssh-rsa` signature type that the scripts below select.

## 8. First script: one command

`main.py`:

```python
import os

import paramiko

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect(
    "192.168.113.14",
    username="admin",
    key_filename=os.path.expanduser("~/.ssh/id_rsa"),
    allow_agent=False,
    look_for_keys=False,
    disabled_algorithms={"pubkeys": ["rsa-sha2-256", "rsa-sha2-512"]},
)

stdin, stdout, stderr = ssh.exec_command("show version")
print(stdout.read().decode())

ssh.close()
```

What each part does:

- `AutoAddPolicy()` accepts the router's host key on the first connection.
- `key_filename` is your private key; `allow_agent=False` and `look_for_keys=False` make Paramiko use only that key.
- `disabled_algorithms` turns off the two newer RSA signature types, so the login uses `ssh-rsa`.
- `exec_command()` runs one command and returns its output in `stdout`.

## 9. `exec_command()` and `run()` with `invoke_shell()`

- `exec_command()` runs **one** command. Cisco IOS normally accepts only one per connection, so several commands mean several connections.
- `invoke_shell()` opens an interactive session, like typing in PuTTY. Many commands can run in one session, including configuration mode. The `run()` helper sends a command, waits one second, and returns what the router printed.

`paramiko_examples.py`:

```python
import os
import time

import paramiko


def connect():
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(
        "192.168.113.14",
        username="admin",
        key_filename=os.path.expanduser("~/.ssh/id_rsa"),
        allow_agent=False,
        look_for_keys=False,
        disabled_algorithms={"pubkeys": ["rsa-sha2-256", "rsa-sha2-512"]},
    )
    return ssh


def run(shell, command):
    shell.send(command + "\n")
    time.sleep(1)
    return shell.recv(65535).decode()


# Example 1: ONE command with exec_command()
print("===== Example 1: exec_command() =====")
ssh = connect()
stdin, stdout, stderr = ssh.exec_command("show ip interface brief")
print(stdout.read().decode())
ssh.close()

# Example 2: SEVERAL commands with exec_command()
# Cisco IOS normally accepts only one exec_command() per connection,
# so we connect again for each command.
print("===== Example 2: exec_command() in a loop =====")
for command in ["show clock", "show ip route"]:
    ssh = connect()
    stdin, stdout, stderr = ssh.exec_command(command)
    print(stdout.read().decode())
    ssh.close()

# Example 3: several commands in ONE session with invoke_shell() and run()
print("===== Example 3: invoke_shell() and run() =====")
ssh = connect()
shell = ssh.invoke_shell()
run(shell, "terminal length 0")  # show full output without --More--
print(run(shell, "show clock"))
print(run(shell, "show ip interface brief"))
ssh.close()

# Example 4: change the config with invoke_shell() and run()
# Creates Loopback100 with IP 1.1.1.1, then shows the result.
print("===== Example 4: config change with run() =====")
ssh = connect()
shell = ssh.invoke_shell()
run(shell, "terminal length 0")
run(shell, "configure terminal")
run(shell, "interface loopback 100")
run(shell, "ip address 1.1.1.1 255.255.255.255")
run(shell, "end")
print(run(shell, "show ip interface brief"))
ssh.close()
```

Run it:

```
python paramiko_examples.py
```

After Example 4, `Loopback100` with `1.1.1.1` appears in the `show ip interface brief` output.

## Troubleshooting

| Problem | Cause and fix |
|---------|---------------|
| `ishare2 pull` ends with `The image file size is too small` | That entry is a CML package (only a `.yaml` is downloaded). Pull the `csr1000vng-...` entry instead. |
| CSR console is blank | Normal for the first minutes. Confirm it is running with `ps aux \| grep [q]emu` on the PNETLab VM, wait, then press Enter. |
| CSR never boots | Run `egrep -c '(vmx\|svm)' /proc/cpuinfo` on the PNETLab VM. If it prints `0`, power off the VM and enable **Virtualize Intel VT-x/EPT or AMD-V/RVI** in VMware. |
| `Authentication failed: transport shut down or saw EOF` | The router closed the connection during key login. Make sure the `disabled_algorithms` line is in `ssh.connect(...)` and that `ssh admin@192.168.113.14` works from Git Bash. |
| `An RSA key was specified, but no RSA pubkey algorithms are configured!` | The installed Paramiko has no `ssh-rsa`. Run `pip install paramiko==4.0.0`. |
