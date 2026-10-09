# Week 05: Two Cisco CSR 1000v Routers in PNETLab with SSH Key Login and Paramiko

This lab sets up PNETLab in VMware on Windows and builds two Cisco CSR 1000v routers (R1, R2) with SSH key login. Then it runs commands on R1 from Python with Paramiko. It uses the same steps as Week 04, but with the Cisco CSR 1000v in place of the Cisco 7200.

PNETLab VM IP: `192.168.113.128` (network `192.168.113.0/24`)

| Device | Interface | IP |
|--------|-----------|----|
| R1 (CSR 1000v) | Gi1 | 192.168.113.11 |
| R2 (CSR 1000v) | Gi1 | 192.168.113.12 |

Each CSR 1000v uses 4 CPUs and 6144 MB of RAM. The two routers need 12 GB of RAM in the PNETLab VM.

## 1. Windows prerequisites

1. Install [PuTTY](../Week04/putty-64bit-0.85-installer.msi).
2. Install [Git Bash](https://git-scm.com/downloads).
3. Register PuTTY as the handler for `telnet://` links so PNETLab can open node consoles. Run in **PowerShell**:

```powershell
reg add "HKCU\Software\Classes\telnet\shell\open\command" /ve /d '\"C:\Program Files\PuTTY\putty.exe\" %1' /f
```

## 2. Download PNETLab

1. Install VMware Workstation on Windows.
2. Download the PNETLab **4.2.10** `.ova` file (about 2 GB) from the official [download page](https://pnetlab.com/pages/download), or directly: [Google Drive](https://drive.google.com/file/d/1BbOL7JEQbChymPeux9JGrHZpLsQyCpPQ/view?usp=sharing) / [Mega (backup)](https://mega.nz/file/K6pBUSaI#pcrcGeXu-Xsade833N79jXz6Jy9tWFcs5PyEgfPUM98).

## 3. Import PNETLab into VMware

1. Open VMware Workstation and select **Open a Virtual Machine**.

![Open a Virtual Machine](https://github.com/user-attachments/assets/8fb062eb-5343-447c-baad-40ecdf63d6c5)

2. Select the downloaded `.ova` file, keep the default storage path, and click **Import**.

![Import dialog](https://github.com/user-attachments/assets/3b390792-05ae-4f7b-95df-46b8bf31baaf)

3. Click **Edit virtual machine settings**:
   - Under **Processors**, check **Virtualize Intel VT-x/EPT or AMD-V/RVI**.
   - Under **Memory**, give the VM at least 14 GB. The two CSR 1000v routers use 6 GB each.
   - Leave **Network Adapter** on **NAT**.

![Edit virtual machine settings](https://github.com/user-attachments/assets/6f6fa7fb-ae4f-411d-9b26-1df87c7cd3cb)

4. Close VMware. Do not start the VM yet. Step 4 must run first.

## 4. Turn on nested virtualization with `fix-vmware.ps1`

Do this step after you import PNETLab (step 3) and before you start the PNETLab VM. It uses the script [`fix-vmware.ps1`](../Week04/fix-vmware.ps1) from the Week 04 folder.

### Why nested virtualization is necessary

- PNETLab is a virtual machine in VMware. Each CSR 1000v router is a QEMU node that runs inside the PNETLab VM. This is a virtual machine inside a virtual machine: nested virtualization.
- QEMU uses KVM, and KVM needs the processor functions VT-x (Intel) or AMD-V (AMD) inside the PNETLab VM.
- VMware gives these functions to the VM only when two conditions are true:
  - The VM setting **Virtualize Intel VT-x/EPT or AMD-V/RVI** is on.
  - The Windows hypervisor is off.
- Without nested virtualization, the CSR 1000v routers do not start.
- The Cisco 7200 routers of Week 04 use Dynamips, which does not need these functions. That is why Week 04 works without this step.

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

Step 5 shows how to check nested virtualization inside the PNETLab VM.

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

## 5. Start PNETLab

1. Open VMware and power on the PNETLab VM. The console shows the VM's IP address (`192.168.113.128` in this lab). Log in as `root` / `pnet` and complete the first-boot setup, keeping the defaults.

![PNETLab console with IP address](https://github.com/user-attachments/assets/ef5705e6-2552-4686-ae7b-e14ff812365a)

2. Check nested virtualization. On the PNETLab VM, run:

```bash
egrep -c '(vmx|svm)' /proc/cpuinfo
```

A number larger than `0` means that nested virtualization operates. If it prints `0`, do step 4 again.

3. Open `http://192.168.113.128` in a browser, choose **Online Mode**, click **Sign Up** to create a PNETLab account, then log in.

![Online and Offline mode selection](https://github.com/user-attachments/assets/0f70a17c-8e46-4127-99de-7424920da2e8)

## 6. Download the CSR 1000v image (on the PNETLab VM)

Log in to the PNETLab VM (`192.168.113.128`) and install ishare2:

```bash
wget -qO- https://ishare2.sh/install | sh
```

Then find and download the CSR 1000v image:

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

## 7. Build the lab

1. Open `http://192.168.113.128` and create a new lab.
2. Right-click the canvas → **Node** → Template: **Cisco CSR 1000V (XE 16.x)**. This is the template for `csr1000vng-...` images, including 17.x. The plain **Cisco CSR 1000V** template does not list this image.
3. Image: `csr1000vng-universalk9.17.03.08a-serial`. Name the node `R1` and keep the default CPU and RAM (4 CPUs, 6144 MB).
4. Do steps 2 and 3 again for a second node named `R2`.
5. Right-click the canvas → **Network** → Type: **Management(Cloud0)**.
6. Connect `Gi1` of each router to the network.
7. Start both routers and click each one to open its console in PuTTY.

The console stays blank for the first few minutes, and the first boot takes 5 to 10 minutes. Lines such as `partition ... has an invalid filesystem` and `This will cause a complete loss of data` are normal on the first boot. When you see:

```
Would you like to enter the initial configuration dialog? [yes/no]:
```

answer `no`.

## 8. Configure each router

**R1**

```
enable
conf t
no service config
hostname R1
ip domain-name lab.local
int gi1
 ip address 192.168.113.11 255.255.255.0
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

**R2**

```
enable
conf t
no service config
hostname R2
ip domain-name lab.local
int gi1
 ip address 192.168.113.12 255.255.255.0
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

Check the interfaces with `show ip int br`.

`no service config` stops the `%Error opening tftp://...` messages that appear when a router boots without a saved config.

## 9. Create an SSH key on Windows (Git Bash)

```bash
ssh-keygen -t rsa -b 2048
fold -b -w 72 ~/.ssh/id_rsa.pub
```

Use `fold`, not `cat ~/.ssh/id_rsa.pub`. IOS cuts input lines at 254 characters, so the key pasted as one line fails with `%SSH: Failed to decode the Key Value`.

If you already made a key in Week 04, do not make a new one. Run only the `fold` command.

## 10. Add the public key to each router

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

A `key-hash ssh-rsa ...` line under `username admin` means the key was accepted.

## 11. Allow the legacy SSH algorithms on Windows

Add this to `~/.ssh/config`. If you added it in Week 04, it is already there:

```
Host 192.168.113.*
  KexAlgorithms +diffie-hellman-group14-sha1
  HostKeyAlgorithms +ssh-rsa
  PubkeyAcceptedAlgorithms +ssh-rsa
  Ciphers +aes128-cbc
```

## 12. Connect

```bash
ssh admin@192.168.113.11
ssh admin@192.168.113.12
```

Answer `yes` to the host key prompt on the first connection. You land at the `R1#` (or `R2#`) prompt without a password. Do not continue to the Python part until this works.

## 13. Give the routers internet access

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

## 14. Connect the two routers to each other

The routers already reach each other through the management network, since both `Gi1` interfaces are on `192.168.113.0/24`. From R1:

```
ping 192.168.113.12
```

For a direct link, use `Gi2`:

1. Stop both routers.
2. Hover over R1, drag the orange plug icon onto R2, and pick `Gi2` on both sides.
3. Start both routers.

| Device | Interface | IP |
|--------|-----------|----|
| R1 | Gi2 | 10.0.0.1/30 |
| R2 | Gi2 | 10.0.0.2/30 |

**R1**

```
conf t
int gi2
 ip address 10.0.0.1 255.255.255.252
 no shut
end
wr
```

**R2**

```
conf t
int gi2
 ip address 10.0.0.2 255.255.255.252
 no shut
end
wr
```

Test from R1:

```
ping 10.0.0.2
```

## 15. Addressing note: why `10.0.0.4 255.255.255.252` is rejected

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
int gi2
 ip address 10.0.0.1 255.255.255.0
end
wr
```

(R2 gets `10.0.0.2 255.255.255.0`.)

Each cable between two routers is its own subnet. A router cannot have two interfaces in the same subnet, so a second link needs a different network, for example `10.0.1.1` and `10.0.1.2` with `255.255.255.0`.

## 16. Install Paramiko (Windows)

In the PyCharm terminal of your project:

```
pip install paramiko==4.0.0
```

Use version 4.0.0. Newer versions no longer include the `ssh-rsa` signature type that the scripts below select.

## 17. First script: one command

`main.py`:

```python
import os

import paramiko

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect(
    "192.168.113.11",
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

## 18. `exec_command()` and `run()` with `invoke_shell()`

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
        "192.168.113.11",
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

After Example 4, `Loopback100` with `1.1.1.1` appears in the `show ip interface brief` output of R1.

## Bonus: Reach R1 from the internet with Tunnels

Expose R1's SSH port through a [tunnels.io](https://tunnels.io) TCP tunnel, so it is reachable from outside the lab network.

1. On the Windows machine, start a TCP tunnel to `192.168.113.11:22`. The client shows the public address:

```
Active Tunnels:
  ▸ tcp://tunnels.host:33017 → 192.168.113.11:22  [tcp]
```

2. The `Host 192.168.113.*` block does not match the tunnel hostname, so add a second block to `~/.ssh/config`:

```
Host tunnels.host
  KexAlgorithms +diffie-hellman-group14-sha1
  HostKeyAlgorithms +ssh-rsa
  PubkeyAcceptedAlgorithms +ssh-rsa
  Ciphers +aes128-cbc
```

Without it, SSH fails with `no matching key exchange method found`.

3. Connect using the port from the tunnel output:

```bash
ssh -p 33017 admin@tunnels.host
```

You land at the `R1#` prompt. The port (`33017` here) is whatever your own tunnel shows.

## Troubleshooting

| Problem | Cause and fix |
|---------|---------------|
| `ishare2 pull` ends with `The image file size is too small` | That entry is a CML package (only a `.yaml` is downloaded). Pull the `csr1000vng-...` entry instead. |
| CSR console is blank | Normal for the first minutes. Confirm it is running with `ps aux \| grep [q]emu` on the PNETLab VM, wait, then press Enter. |
| CSR never boots | Run `egrep -c '(vmx\|svm)' /proc/cpuinfo` on the PNETLab VM. If it prints `0`, power off the VM and do step 4 again. |
| `Authentication failed: transport shut down or saw EOF` | The router closed the connection during key login. Make sure the `disabled_algorithms` line is in `ssh.connect(...)` and that `ssh admin@192.168.113.11` works from Git Bash. |
| `An RSA key was specified, but no RSA pubkey algorithms are configured!` | The installed Paramiko has no `ssh-rsa`. Run `pip install paramiko==4.0.0`. |

## Image credits

Screenshots are loaded from their original source: [sk4vac/PNETLab-Setup-VMWare](https://github.com/sk4vac/PNETLab-Setup-VMWare).
