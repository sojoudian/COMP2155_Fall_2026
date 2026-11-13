from netmiko import ConnectHandler
r1 = {
    "device_type": "cisco_ios",
    "host": "10.255.255.254",
    "username": "admin",
    "password": "cisco123",
}
connection = ConnectHandler(**r1)
print("Prompt: ", connection.find_prompt())
print("Enable mode: ", connection.check_enable_mode())

connection.config_mode()
print("Prompt: ", connection.find_prompt())
print("Config mode: ", connection.check_config_mode())

connection.exit_config_mode()
print("Prompt: ", connection.find_prompt())
print("Config mode: ", connection.check_config_mode())

commands = "access-list 1 permit any; ip domain name lab.local"
print(connection.send_config_set(commands.split(";")))
print("Config mode: ", connection.check_config_mode())
connection.disconnect()