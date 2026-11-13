from netmiko import ConnectHandler

file = open("devices.txt")
hosts = file.read().split()
file.close()

for host in hosts:
    router = {
        "device_type": "cisco_ios",
        "host": host,
        "username": "admin",
        "password": "cisco123",
    }
    connection = ConnectHandler(**router)
    hostname = connection.find_prompt()[:-1]
    print("=====", hostname, "=====")
    print(connection.send_config_from_file(f"{hostname}.txt"))
    print(connection.send_command("show ip ospf interface brief"))
    print(connection.save_config())
    print(connection.send_command("show ip ospf neighbor"))
    connection.disconnect()
