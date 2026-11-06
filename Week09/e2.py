from datetime import date

from netmiko import ConnectHandler

r1 = {
    "device_type": "cisco_ios",
    "host": "192.168.113.11",
    "username": "admin",
    "password": "cisco123",
}

connection = ConnectHandler(**r1)
hostname = connection.find_prompt()[:-1]
config = connection.send_command("show running-config")
connection.disconnect()

filename = f"{hostname}_{date.today()}.txt"
with open(filename, "w") as file:
    file.write(config)
print("Saved", len(config.splitlines()), "lines to", filename)

with open("backup.log", "a") as log:
    log.write(f"{date.today()} {hostname} {filename}\n")
