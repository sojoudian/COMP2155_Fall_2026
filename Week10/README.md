# Week 10: Two Cisco 7200 Routers on Your LAN

One command installs `tessera` and starts two Cisco 7200 routers, R1 and R2. Each router gets a free address of your LAN (Wi-Fi or cable). Your computer and the other computers on the LAN connect to the routers at these addresses.

## Step 1: Start the routers

### macOS and Linux

Open a terminal, and run this command:

```
curl -fsSL https://raw.githubusercontent.com/sojoudian/COMP2155_Fall_2026/master/Week10/setup.sh | bash
```

`sudo` asks for your password.

### Windows

Open PowerShell, and run this command:

```
irm https://raw.githubusercontent.com/sojoudian/COMP2155_Fall_2026/master/Week10/setup.ps1 | iex
```

1. Click "Yes" to start PowerShell as Administrator.
2. If Npcap is not installed, the Npcap installer opens. Click "I Agree", then "Install", then "Finish".

You can also install Npcap before you run the command. Download it from https://npcap.com/#download, and use the default options.

## Step 2: Find the router addresses

At the end, the script shows a table with the LAN address of each router:

```
LAN en0 (Wi-Fi) 10.0.0.0/24
ROUTER  INTERFACE        LAN ADDRESS
R1      FastEthernet0/0  10.0.0.254
R2      FastEthernet0/0  10.0.0.253
This computer and the other hosts on the LAN reach the routers at these addresses.
The routers see this computer as 10.0.0.252.
```

Your addresses are different. The user is `admin`, and the password is `cisco123`.

The script uses only free addresses. If other hosts or another lab on your computer use some addresses, the script skips them and shows them on one line above the table:

```
week10: in use: 10.0.0.254 (aa:bb:cc:00:2c:00), 10.0.0.250 (this computer routes it to utun10: another lab)
```

## Step 3: Test the routers

Use the R1 address from your table. The address 10.0.0.254 is only an example:

```
ping 10.0.0.254
```

Connect to the router with SSH. The 7200 has only old SSH algorithms:

```
ssh -o KexAlgorithms=+diffie-hellman-group14-sha1 -o HostKeyAlgorithms=+ssh-rsa -o Ciphers=+aes128-cbc -o MACs=+hmac-sha1 admin@10.0.0.254
```

Do the same test with the R2 address. The other computers on your LAN can use the same commands.

For netmiko, use paramiko 3.5.0. paramiko 5 has no algorithm of the 7200:

```
python -m pip install "paramiko==3.5.0" "netmiko==4.4.0"
```

## Step 4: Stop the routers

macOS and Linux:

```
sudo tessera lab down ~/tessera-week10/wk10.yaml
```

Windows (PowerShell as Administrator):

```
tessera lab down $HOME\tessera-week10\wk10.yaml
```

To start the routers again, do Step 1 again. The script keeps your saved configs (`write memory`) in the folder `tessera-week10`.

## Remove everything

This removes all that Step 1 did: the routers, the folder `tessera-week10` (your saved configs too) and `tessera`.

macOS and Linux:

```
curl -fsSL https://raw.githubusercontent.com/sojoudian/COMP2155_Fall_2026/master/Week10/uninstall.sh | bash
```

Windows (click "Yes" for Administrator):

```
irm https://raw.githubusercontent.com/sojoudian/COMP2155_Fall_2026/master/Week10/uninstall.ps1 | iex
```

On Windows, it also removes the network adapter, the network profiles and the Wintun driver of tessera. If the script installed Npcap, it removes Npcap. If Npcap was on your computer before, the script asks first, because Wireshark and Nmap use Npcap too.

## Problems

- **Port 22610 or 22620 is in use.** Another lab on your computer uses the port. Stop that lab with `tessera lab down` and its `.yaml` file. Then do Step 1 again.
- **No table at the end.** Read the error above the table. Your computer must be on a LAN (Wi-Fi or cable).
- **"N free addresses in 10.0.0.0/24: want 3".** Your LAN has not enough free addresses. Stop your other labs with `tessera lab down`, or use another LAN. Then do Step 1 again.
- **`%IP-4-DUPADDR` in `show logging` of a router.** Another host uses the address of the router. Do Step 1 again: the script finds new free addresses.
