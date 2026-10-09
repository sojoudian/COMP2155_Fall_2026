# Week 05: Cisco CSR 1000v in PNETLab and Paramiko

This lab sets up PNETLab in VMware on Windows and builds two Cisco CSR 1000v routers (R1, R2) with SSH key login. Then it runs commands on R1 from Python with Paramiko.

PNETLab VM IP: `192.168.113.128` (network `192.168.113.0/24`)

| Device | Interface | IP |
|--------|-----------|----|
| R1 (CSR 1000v) | Gi1 | 192.168.113.11 |
| R2 (CSR 1000v) | Gi1 | 192.168.113.12 |

If your PNETLab VM is on a different network, for example `192.168.50.0/24`, use `192.168.50` in place of `192.168.113` in all steps.

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
   - Under **Memory**, give the VM at least 14 GB. Each CSR 1000v uses 6 GB.
   - Leave **Network Adapter** on **NAT**.

![Edit virtual machine settings](https://github.com/user-attachments/assets/6f6fa7fb-ae4f-411d-9b26-1df87c7cd3cb)

Do not start the VM yet.

## 4. Turn on nested virtualization with `fix-vmware.ps1`

Do this step before you start the PNETLab VM. It uses the script [`fix-vmware.ps1`](../Week04/fix-vmware.ps1) from the Week 04 folder.

### Why nested virtualization is necessary

- PNETLab is a VM in VMware. Each CSR 1000v is a QEMU VM inside the PNETLab VM. This is nested virtualization.
- QEMU needs VT-x (Intel) or AMD-V (AMD) inside the PNETLab VM. VMware gives it only when the VM setting is on and the Windows hypervisor is off.
- Without nested virtualization, the CSR 1000v routers do not start.

### What the script does

- It turns on nested virtualization in the `.vmx` file of the PNETLab VM, and turns off the CPU performance counters. It keeps a `.bak` copy of the file.
- It turns off the Windows hypervisor (Hyper-V, Memory Integrity, Credential Guard). This needs one restart.
- It shows a warning if an antivirus program (Avast, AVG, Kaspersky) uses VT-x or AMD-V.

After this change, WSL 2, Docker Desktop, Windows Sandbox, and Hyper-V VMs do not operate.

### How to run it

1. Download `fix-vmware.ps1` from the Week04 folder on GitHub: open the file and select **Download raw file**. Keep it in your `Downloads` folder.
2. Close VMware.
3. Open **PowerShell** (not as administrator) and run:

```powershell
cd $HOME\Downloads
powershell -ExecutionPolicy Bypass -File .\fix-vmware.ps1
```

`-ExecutionPolicy Bypass` lets Windows run the downloaded script for this one time. It does not change the execution policy of the computer.

4. If a User Account Control window opens, select **Yes**.
5. If the script asks for a restart, type `Y`.
6. If a black screen asks about Credential Guard or virtualization-based security during the restart, press **F3** for each question.
7. After the restart, run the two commands again.
8. Make sure that the output shows these lines:

```
  Virtualize Intel VT-x/EPT or AMD-V/RVI (vhv.enable): TRUE
  Virtualize CPU performance counters (vpmc.enable): FALSE
  Result: OK
```

## 5. Start PNETLab

1. Open VMware and power on the PNETLab VM. The console shows the VM's IP address (`192.168.113.128` in this lab). Log in as `root` / `pnet` and complete the first-boot setup, keeping the defaults.

![PNETLab console with IP address](https://github.com/user-attachments/assets/ef5705e6-2552-4686-ae7b-e14ff812365a)

2. Check nested virtualization. On the PNETLab VM, run:

```bash
egrep -c '(vmx|svm)' /proc/cpuinfo
```

The result must be larger than `0`. If it is `0`, do step 4 again.

3. Open `http://192.168.113.128` in a browser, choose **Online Mode**, click **Sign Up** to create a PNETLab account, then log in.

![Online and Offline mode selection](https://github.com/user-attachments/assets/0f70a17c-8e46-4127-99de-7424920da2e8)

## 6. Download the CSR 1000v image (on the PNETLab VM)

```bash
wget -qO- https://ishare2.sh/install | sh
ishare2 search csr
ishare2 pull qemu 102
```

`102` is the ID of `csr1000vng-universalk9.17.03.08a-serial` (IOS XE 17.03.08a, 1.1 GiB). Use the ID from your own search output.

Do not use `csr1000v-17-03-08a` (ID 88). ishare2 downloads only its 277-byte `.yaml` file, and the pull ends with `The image file size is too small`.

## 7. Build the lab

1. Open `http://192.168.113.128` and create a new lab.
2. Right-click the canvas → **Node** → Template: **Cisco CSR 1000V (XE 16.x)**. The plain **Cisco CSR 1000V** template does not list this image.
3. Image: `csr1000vng-universalk9.17.03.08a-serial`. Name the node `R1` and keep the default CPU and RAM (4 CPUs, 6144 MB).
4. Do steps 2 and 3 again for a second node named `R2`.
5. Right-click the canvas → **Network** → Type: **Management(Cloud0)**.
6. Connect `Gi1` of each router to the network.
7. Start both routers and click each one to open its console in PuTTY.

The first boot takes 5 to 10 minutes, and the console stays blank at the start. Lines such as `partition ... has an invalid filesystem` are normal on the first boot. When you see:

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
wr
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
wr
```

Check the interfaces with `show ip int br`.

## 9. Create an SSH key on Windows (Git Bash)

If you made a key in Week 04, skip `ssh-keygen` and run only `fold`.

```bash
ssh-keygen -t rsa -b 2048
fold -b -w 72 ~/.ssh/id_rsa.pub
```

Press Enter at each `ssh-keygen` prompt. Do not set a passphrase, because the Python scripts cannot use a key with a passphrase.

Use `fold`, not `cat`. IOS cuts lines longer than 254 characters, and a one-line key fails with `%SSH: Failed to decode the Key Value`.

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

Check with `show run | section pubkey-chain`. A `key-hash ssh-rsa ...` line under `username admin` means that the router accepted the key.

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

## 13. Install Paramiko (Windows)

In the PyCharm terminal of your project:

```
pip install paramiko==4.0.0
```

Use version 4.0.0. Newer versions no longer include the `ssh-rsa` signature type that the scripts below select.

## 14. First script: one command

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

## 15. `exec_command()` and `run()` with `invoke_shell()`

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

## Troubleshooting

| Problem | Cause and fix |
|---------|---------------|
| The CSR does not start | Run `egrep -c '(vmx\|svm)' /proc/cpuinfo` on the PNETLab VM. If it prints `0`, do step 4 again. If it still prints `0`, turn on VT-x or AMD-V in the BIOS or UEFI of your computer. |
| `Authentication failed: transport shut down or saw EOF` | The router closed the connection during key login. Make sure the `disabled_algorithms` line is in `ssh.connect(...)` and that `ssh admin@192.168.113.11` works from Git Bash. |
| `An RSA key was specified, but no RSA pubkey algorithms are configured!` | The installed Paramiko has no `ssh-rsa`. Run `pip install paramiko==4.0.0`. |

## Image credits

Screenshots are loaded from their original source: [sk4vac/PNETLab-Setup-VMWare](https://github.com/sk4vac/PNETLab-Setup-VMWare).
