# PNETLab: Two Cisco 7200 Routers with SSH Key Login from Windows

PNETLab VM IP: `192.168.113.128` (network `192.168.113.0/24`)

| Device | Interface | IP |
|--------|-----------|----|
| R1 | fa1/0 | 192.168.113.11 |
| R2 | fa1/0 | 192.168.113.12 |

## 1. Windows prerequisites

1. Install [PuTTY](https://www.putty.org/).
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

3. Click **Edit virtual machine settings**. Under **Processors**, check **Virtualize Intel VT-x/EPT or AMD-V/RVI**. Leave **Network Adapter** on **NAT**.

![VMware virtualization settings](https://pnetlab.com/api/uploader/public/read?file=https://pnetlab.com/Local/pages/page_content/1/image_7.png)

4. Power on the VM. The console shows the VM's IP address (`192.168.113.128` in this lab). Log in as `root` / `pnet` and complete the first-boot setup, keeping the defaults.

![PNETLab console with IP address](https://pnetlab.com/api/uploader/public/read?file=https://pnetlab.com/Local/pages/page_content/1/image_6.png)

5. Open `http://192.168.113.128` in a browser, choose **Online Mode**, click **Sign Up** to create a PNETLab account, then log in.

![Online and Offline mode selection](https://pnetlab.com/api/uploader/public/read?file=https://pnetlab.com/Local/pages/page_content/1/image_8.png)

## 4. Download the router image (on the PNETLab VM)

Log in to the PNETLab VM (`192.168.113.128`) and run:

```bash
wget -qO- https://ishare2.sh/install | sh
ishare2 search all
ishare2 search all | grep 7200
ishare2 pull dynamips 20
```

`20` is the ID of the 7200 image shown by the search; use the ID from your own search output.

## 5. Build the lab

1. Open `http://192.168.113.128` and create a new lab.
2. Add two **Cisco 7200** nodes (R1, R2). Put a `PA-FE-TX` adapter in slot 1 so each has `fa1/0`.
3. Right-click the canvas → **Network** → Type: **Management(Cloud0)**.
4. Connect `fa1/0` of each router to the network.
5. Start both routers and click each one to open its console in PuTTY.

## 6. Configure each router

**R1**

```
enable
conf t
no service config
hostname R1
ip domain-name lab.local
int fa1/0
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
int fa1/0
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

## 7. Create an SSH key on Windows (Git Bash)

```bash
ssh-keygen -t rsa -b 2048
fold -b -w 72 ~/.ssh/id_rsa.pub
```

Use `fold`, not `cat ~/.ssh/id_rsa.pub`. IOS cuts input lines at 254 characters, so the key pasted as one line fails with `%SSH: Failed to decode the Key Value`.

## 8. Add the public key to each router

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

## 9. Allow the legacy SSH algorithms on Windows

This IOS only offers SHA-1 key exchange and CBC ciphers, which OpenSSH disables by default. Add this to `~/.ssh/config`:

```
Host 192.168.113.*
  KexAlgorithms +diffie-hellman-group14-sha1
  HostKeyAlgorithms +ssh-rsa
  PubkeyAcceptedAlgorithms +ssh-rsa
  Ciphers +aes128-cbc
```

## 10. Connect

```bash
ssh admin@192.168.113.11
ssh admin@192.168.113.12
```

Answer `yes` to the host key prompt on the first connection. You land at the `R1#` prompt without a password.

## Bonus: Reach the router from the internet with Tunnels

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

## Connect the two routers to each other

The routers already reach each other through the management network, since both `fa1/0` interfaces are on `192.168.113.0/24`. From R1:

```
ping 192.168.113.12
```

For a direct link, use `fa0/0`:

1. Stop both routers.
2. Hover over R1, drag the orange plug icon onto R2, and pick `fa0/0` on both sides.
3. Start both routers.

| Device | Interface | IP |
|--------|-----------|----|
| R1 | fa0/0 | 10.0.0.1/30 |
| R2 | fa0/0 | 10.0.0.2/30 |

**R1**

```
conf t
int fa0/0
 ip address 10.0.0.1 255.255.255.252
 no shut
end
wr
```

**R2**

```
conf t
int fa0/0
 ip address 10.0.0.2 255.255.255.252
 no shut
end
wr
```

Test from R1:

```
ping 10.0.0.2
```

## Image credits

Screenshots are loaded from their original sources: the [PNETLab download page](https://pnetlab.com/pages/download) and [sk4vac/PNETLab-Setup-VMWare](https://github.com/sk4vac/PNETLab-Setup-VMWare).
