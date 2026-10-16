# Week 05: Build lab05 with `pnetlab_rebuild.sh`

The script `pnetlab_rebuild.sh` builds the Week 05 IOL lab on a new PNETLab VM. It does these steps:

1. It removes the `i-share.top` apt source, because its signature is not valid.
2. It installs `jq`, `tree`, `wget`, `unzip`, and `curl`.
3. It installs the `ishare2` tool.
4. It downloads the IOL image `i86bi_Linux-L3-AdvEnterpriseK9-M2_157_3_May_2018.bin` with `ishare2`.
5. It writes the lab file `/opt/unetlab/labs/Labs/lab05.unl` with the router R1 and two cloud networks.
6. It fixes the file permissions.

The script reads the IP address of `pnet0` and gives R1 the same network with host number `.11`.

| PNETLab VM IP (`pnet0`) | R1 `e0/1` IP |
|---|---|
| `192.168.113.139` | `192.168.113.11/24` |
| `192.168.64.2` | `192.168.64.11/24` |

## 1. Before you start

- Start the PNETLab VM.
- Make sure that the VM has internet access.
- Write down the VM IP address. The VM console shows it after the boot.

## 2. Run the script

1. Log in to the PNETLab VM as `root` (password `pnet`). Use the VM console or SSH:

```bash
ssh root@<PNETLab VM IP>
```

2. Run these commands on the PNETLab VM:

```bash
curl -LO https://raw.githubusercontent.com/sojoudian/COMP2155_Fall_2026/refs/heads/master/Week05/pnetlab_rebuild.sh
chmod +x pnetlab_rebuild.sh
./pnetlab_rebuild.sh
```

3. Wait for the line `[+] Done.`. The image download is approximately 176 MiB.

Lines with `[!]` are warnings. A warning from `apt-get update` is normal, and the script continues.

## 3. Start R1

1. Open `http://<PNETLab VM IP>/` in a browser.
2. Select **Offline Mode**.
3. Log in as `admin` with the password `pnet`, and type the captcha text.
4. Open `Labs/lab05.unl`.
5. Right-click R1 and select **Start**.

R1 boots with its startup-config:

| Item | Value |
|---|---|
| `e0/1` | `<first 3 numbers of the VM IP>.11/24`, on `pnet0` (the NAT network) |
| `e0/0` | No IP address, on `pnet1` |
| SSH | Version 2 |
| User | `admin` |
| Password | `cisco123` |

R1 makes a 2048-bit RSA key at boot, before SSH starts. On an Apple Silicon Mac, PNETLab runs under emulation, and this step takes 6 to 10 minutes.

## 4. Connect to R1

From your computer, run:

```bash
ssh -o KexAlgorithms=+diffie-hellman-group14-sha1 -o HostKeyAlgorithms=+ssh-rsa admin@<R1 IP>
```

Type `cisco123` at the password prompt. Then run `show ip interface brief` to see the interfaces.

## 5. Install Paramiko (Windows)

In the PyCharm terminal of your project:

```
pip install paramiko==4.0.0
```

Use version 4.0.0. Newer versions no longer include the `ssh-rsa` signature type that the scripts below select.

## 6. First script: one command

`main.py`:

```python
# Example 2: run SEVERAL commands with exec_command()
# Cisco IOS normally accepts only one exec_command() per connection,
# so we connect again for each command.
import paramiko


def exec_one(command):
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(
        "192.168.113.11",
        username="admin",
        password="cisco123",
        allow_agent=False,
        look_for_keys=False,
    )
    stdin, stdout, stderr = ssh.exec_command(command)
    output = stdout.read().decode()
    ssh.close()
    return output


for command in ["show clock", "show ip interface brief", "show version | include uptime"]:
    print("=====", command, "=====")
    print(exec_one(command))
```

## Options

| Option | Function |
|---|---|
| `--image /path/<file>.bin` | Copy your own IOL image. The script does not download the image. |
| `--iourc /path/iourc` | Copy your own IOL license file. |
| `--skip-ishare2` | Do not install `ishare2`. |
| `--force` | Write a new `lab05.unl` over the old file. The script keeps a backup copy with a date in its name. |
| `-h`, `--help` | Show the help text. |

## Troubleshooting

| Message | Cause and fix |
|---|---|
| `Run as root.` | Log in as `root`, and run the script again. |
| `No IPv4 address on pnet0` | The VM has no IP address. Make sure that the VM network adapter is on NAT, and restart the VM. |
| `lab05.unl exists - use --force to overwrite` | The lab file is already there. Run `./pnetlab_rebuild.sh --force`. |
| `IOL image missing` | The download failed. Run the script again, or give the image with `--image`. |
| `No iourc line for hostname ...` | The license file has no line for the VM hostname. R1 does not boot. Give a license file with `--iourc`. |
| SSH to R1 gives `Connection refused` | R1 did not complete its RSA key. Wait, and try again. |
