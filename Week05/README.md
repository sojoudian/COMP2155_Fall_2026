# Week 05: Cisco CSR 1000v in PNETLab and Paramiko

This continues the Week 04 lab (two Cisco 7200 routers with SSH key login). It adds a Cisco CSR 1000v router (R4) and runs commands on it from Python with Paramiko.

| Device | Interface | IP |
|--------|-----------|----|
| R1 | fa1/0 | 192.168.113.11 |
| R2 | fa1/0 | 192.168.113.12 |
| R4 (CSR 1000v) | Gi1 | 192.168.113.14 |

## 0. Turn on nested virtualization with `fix-vmware.ps1`

Do this step first. It uses the script [`fix-vmware.ps1`](../Week04/fix-vmware.ps1) from the Week 04 folder.

### Why nested virtualization is necessary

- PNETLab is a virtual machine in VMware. The CSR 1000v (R4) is a QEMU node that runs inside the PNETLab VM. This is a virtual machine inside a virtual machine: nested virtualization.
- QEMU uses KVM, and KVM needs the processor functions VT-x (Intel) or AMD-V (AMD) inside the PNETLab VM.
- VMware gives these functions to the VM only when two conditions are true:
  - The VM setting **Virtualize Intel VT-x/EPT or AMD-V/RVI** is on.
  - The Windows hypervisor is off.
- Without nested virtualization, R4 does not start.
- The Cisco 7200 routers (R1, R2) from Week 04 use Dynamips, which does not need these functions. That is why Week 04 works without this step.

### What the script does

- **Part A** changes the `.vmx` file of the PNETLab VM:
  - It sets **Virtualize Intel VT-x/EPT or AMD-V/RVI** to on, when this is possible.
  - It sets **Virtualize CPU performance counters** to off.
  - It keeps a backup copy with the extension `.bak`.
- **Part B** sets the Windows hypervisor to off, and the functions that use it: Hyper-V, virtualization-based security, Memory Integrity, and Credential Guard. This part needs administrator rights and one restart.
- **Part C** finds antivirus programs (Avast, AVG, Kaspersky) that can use VT-x or AMD-V. It shows the setting to change.

### How to run it

1. Download `fix-vmware.ps1` from the Week04 folder on GitHub: open the file and select **Download raw file**. Keep it in your `Downloads` folder.
2. Shut down the PNETLab VM and close VMware. If VMware is open, the script waits until you close it.
3. Open **PowerShell**. You do not need administrator rights for this window. Run:

```powershell
cd $HOME\Downloads
powershell -ExecutionPolicy Bypass -File .\fix-vmware.ps1
```

`-ExecutionPolicy Bypass` lets Windows run the downloaded script for this one time. It does not change the execution policy of the computer.

4. If the Windows hypervisor is on, a second window opens. Select **Yes** in the User Account Control window.
5. When the script asks for a restart, save your work and type `Y`. Use **Restart**, not **Shut down**.
6. During the start, a black screen asks about Credential Guard and virtualization-based security. Press **F3** for each question.
7. After the restart, run the same two commands again. The script now sets nested virtualization to on.
8. Make sure that the output shows these lines:

```
  Virtualize Intel VT-x/EPT or AMD-V/RVI (vhv.enable): TRUE
  Virtualize CPU performance counters (vpmc.enable): FALSE
  Result: OK
```

9. Start the PNETLab VM, log in as `root`, and run:

```bash
egrep -c '(vmx|svm)' /proc/cpuinfo
```

A number larger than `0` means that nested virtualization operates.

Do not use the option `-NoNested` for Week 05. This option sets nested virtualization to off.

### Options

| Option | Use |
|--------|-----|
| `-VmxPath "C:\path\to\PNET.vmx"` | Give the path of the `.vmx` file if the script does not find the VM. |
| `-Force` | Apply the Windows changes again, for example after a Windows update sets the hypervisor to on again. |
| `-VmOnly` | Do only part A (the `.vmx` file). |
| `-HostOnly` | Do only part B (Windows). |
| `-NoNested` | Set nested virtualization to off. Not for Week 05. |

### Important

- Part B decreases the security of your computer. WSL 2, Docker Desktop, Windows Sandbox, and Hyper-V virtual machines stop.
- BitLocker stops for one restart only, so that Windows does not ask for the recovery key.
- The script writes a log file for each run in `C:\ProgramData\fix-vmware`.
- The script cannot correct these conditions:
  - VT-x or AMD-V is off in the BIOS or UEFI.
  - A domain Group Policy or Intune sets the Windows settings again.
  - An antivirus program uses VT-x or AMD-V. Set its hardware virtualization setting to off.

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
