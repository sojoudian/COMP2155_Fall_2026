import csv

from netmiko import ConnectHandler

r1 = {
    "device_type": "cisco_ios",
    "host": "192.168.113.11",
    "username": "admin",
    "password": "cisco123",
}

commands = []
file = open("loopbacks.csv")
for row in csv.DictReader(file):
    commands.append(f"interface {row['interface']}")
    commands.append(f"description {row['description']}")
    commands.append(f"ip address {row['ip']} 255.255.255.255")
file.close()

connection = ConnectHandler(**r1)
print(connection.send_config_set(commands))
print(connection.send_command("show ip interface brief"))
print(connection.save_config())
connection.disconnect()
