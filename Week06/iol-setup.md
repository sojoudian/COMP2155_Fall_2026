# PNETLab: Download and Use Cisco IOL

Image: `i86bi_Linux-L3-AdvEnterpriseK9-M2_157_3_May_2018.bin` (IOS 15.7(3)M2), ishare2 IOL ID `10`.

## On the PNETLab VM (as root)

```bash
ishare2 pull bin 10
/opt/unetlab/wrappers/unl_wrapper -a fixpermissions
chmod 1777 /tmp
rm -rf /tmp/netio*
grep -q -F '127.0.0.1 xml.cisco.com' /etc/hosts || echo '127.0.0.1 xml.cisco.com' >> /etc/hosts
```

## License check

```bash
cd /opt/unetlab/addons/iol/bin
python2 CiscoIOUKeygen.py
cat iourc
```

The `[license]` block printed by the keygen must match `iourc`.

## In PNETLab

1. Reload the topology page with **Ctrl+F5**.
2. **Add an Object**, then **Node**, then **Cisco IOL**.
3. In **Image**, select `i86bi_Linux-L3-AdvEnterpriseK9-M2_157_3_May_2018.bin`.
4. Click **Save**, then start the node.

## First boot: stop AutoInstall (TFTP errors, DHCP IPs, DNS lookups)

```
configure terminal
no service config
no ip domain-lookup
interface e0/0
 no ip address
interface e0/1
 no ip address
end
write memory
```

## Base config with SSH

```
enable
conf t
no service config
hostname R1
ip domain-name lab.local
int e0/0
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
