from netmiko import ConnectHandler

r1 = {
    "device_type": "cisco_ios",
    "host": "192.168.113.11",
    "username": "admin",
    "password": "cisco123",
}

commands = ["show clock", "show ip interface brief", "show version | include uptime"]

connection = ConnectHandler(**r1)
print("Connected to", connection.find_prompt())
for command in commands:
    print("=====", command, "=====")
    print(connection.send_command(command))
interfaces = connection.send_command("show ip interface brief", use_textfsm=True)
for interface in interfaces:
    print(interface["interface"], interface["ip_address"], interface["status"])
connection.disconnect()
