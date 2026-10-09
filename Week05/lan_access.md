# Week 05 (Optional): LAN Access to a CSR 1000v

In the Week 05 lab, your routers are on the VMware NAT network `192.168.113.0/24`. Only your Windows host can reach this network.

In this optional lab, you put a new router (R3) on your real network, the LAN. Then any computer on the LAN can connect to R3 with SSH.

Before you start, do steps 1–12 of the [Week 05 README](README.md).

## How PNETLab reaches the outside

Each PNETLab network type connects to a different place:

| PNETLab network type | Connects to | Reaches |
|----------------------|-------------|---------|
| bridge | Nothing outside PNETLab | Only other nodes in the lab |
| Management(Cloud0) | VMware **Network Adapter** (NAT) | Your Windows host, `192.168.113.0/24` |
| Cloud1 | VMware **Network Adapter 2** (Bridged) | Your LAN |

In this lab, you connect R3 to **Cloud1**.

## 1. Find your LAN settings

On your Windows host, open PowerShell and run:

```
ipconfig
```

Find the adapter that connects you to the network (Ethernet or Wi-Fi). Write down these three values:

- **IPv4 Address**, for example `10.0.0.25`
- **Subnet Mask**, for example `255.255.255.0`
- **Default Gateway**, for example `10.0.0.1`

Choose a free IP address for R3 in the same network, for example `10.0.0.141`. Test it:

```
ping 10.0.0.141
```

If no device replies, you can use this address.

This guide uses the values below. Replace them with your values in all steps.

| Setting | Example value |
|---------|---------------|
| R3 IP address | `10.0.0.141` |
| Subnet mask | `255.255.255.0` |
| Gateway | `10.0.0.1` |

## 2. Add a bridged adapter to the PNETLab VM

1. Shut down the PNETLab VM.
2. In VMware, select **VM → Settings**.
3. If there is no **Network Adapter 2**, click **Add**, select **Network Adapter**, and click **Finish**.
4. Select **Network Adapter 2** and set:
   - **Bridged: Connected directly to the physical network**
   - **Connect at power on**: checked
5. Click **OK** and start the PNETLab VM.

PNETLab connects Network Adapter 2 to the network type Cloud1.

Use an Ethernet cable if you can. Bridging over Wi-Fi can fail.

## 3. Add the LAN network to the lab

1. Open your Week 05 lab.
2. Right-click an empty spot on the canvas → **Network**.
3. Name/Prefix: `LAN`. Type: **Cloud1**. Click **Save**.

Do not use type **bridge**. A bridge network connects only lab nodes to each other.

## 4. Add R3

1. Right-click the canvas → **Node** → Template: **Cisco CSR 1000V (XE 16.x)**.
2. Image: `csr1000vng-universalk9.17.03.08a-serial`. Name the node `R3`.
3. Hover over R3, drag the orange plug icon onto the `LAN` cloud, select **Gi1**, and click **Save**.
4. Start R3 and open its console. The first boot takes 5 to 10 minutes.
5. Answer `no` to the initial configuration dialog.

R3 is a third CSR 1000v. If the PNETLab VM does not have enough memory, stop R2 first.

## 5. Create an SSH key

You can connect from your Windows host or from another computer on the LAN. Do this step on that computer: Git Bash on Windows, Terminal on macOS or Linux.

```bash
ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_rsa_cisco -N ""
fold -b -w 72 ~/.ssh/id_rsa_cisco.pub
```

- Use 2048 bits. The CSR stores a larger key with no error, but it closes the connection at login.
- `fold` breaks the key into lines of 72 characters. IOS cuts lines longer than 254 characters.

## 6. Configure R3

Paste this in the R3 console. Replace the `<paste ...>` line with the output of `fold`.

```
enable
conf t
no service config
hostname R3
ip domain name lab.local
int gi1
 ip address 10.0.0.141 255.255.255.0
 no shut
exit
ip route 0.0.0.0 0.0.0.0 10.0.0.1
ip name-server 8.8.8.8
crypto key generate rsa modulus 2048
ip ssh version 2
username admin privilege 15 secret cisco123
line vty 0 4
 login local
 transport input ssh
exit
ip ssh pubkey-chain
 username admin
  key-string
   <paste all lines from the fold output>
  exit
end
wr
```

What is new compared with R1:

- `ip domain name lab.local` (with a space) is the IOS XE 17 form of this command.
- `int gi1` gets an IP address from your LAN.
- `ip route 0.0.0.0 0.0.0.0 10.0.0.1` sends traffic for other networks to your LAN gateway.
- The public key is in the same paste.

Check R3:

```
show run | section pubkey-chain
ping 10.0.0.1
```

- A `key-hash ssh-rsa ...` line under `username admin` shows that R3 stored the key.
- `!!!!!` in the ping output shows that R3 reaches your LAN.

## 7. Add R3 to `~/.ssh/config`

On the computer you connect from, add:

```
Host 10.0.0.141
  IdentityFile ~/.ssh/id_rsa_cisco
  IdentitiesOnly yes
  PubkeyAcceptedAlgorithms +ssh-rsa
  HostKeyAlgorithms +ssh-rsa
```

- `IdentityFile` and `IdentitiesOnly` make SSH use only the R3 key.
- The two `+ssh-rsa` lines allow the older RSA type that the CSR uses. Without them, SSH does not send the key, and R3 asks for a password.

## 8. Connect

```bash
ssh admin@10.0.0.141
```

Answer `yes` to the host key prompt. You land at the `R3#` prompt without a password.

R3 is now on your LAN. Any computer on the LAN can connect to it, if R3 has the key of that computer (steps 5 to 7).

## Troubleshooting

| Problem | Cause and fix |
|---------|---------------|
| `% Invalid input detected` at `ip domain-name`, then `% Please define a domain-name first.` | IOS XE 17 does not accept `ip domain-name`. Use `ip domain name lab.local`, then run `crypto key generate rsa modulus 2048` again. |
| R3 does not start | On the PNETLab VM, run `/opt/unetlab/wrappers/unl_wrapper -a fixpermissions` as root. Then start R3 again. |
| R3 cannot ping the gateway | Make sure that the network type is **Cloud1** and that Network Adapter 2 is **Bridged**. Then open **Edit → Virtual Network Editor → Change Settings**, select **VMnet0**, and set **Bridged to** your Ethernet adapter, not **Automatic**. Some networks (for example, college Wi-Fi) block unknown devices. If so, use your home network. |
| SSH asks for a password | SSH does not send the key, or R3 does not have it. Check the `~/.ssh/config` block. Compare the `key-hash` on R3 with `ssh-keygen -l -E md5 -f ~/.ssh/id_rsa_cisco.pub`. R3 shows the same hex digits in uppercase, without colons. |
| `Connection closed by 10.0.0.141 port 22` | The key is larger than 2048 bits. Create a 2048-bit key (step 5) and replace the key on R3. |
| You must replace the key on R3 | Under `ip ssh pubkey-chain`, run `no username admin`. Then add `username admin` and `key-string` again with the new key. |
