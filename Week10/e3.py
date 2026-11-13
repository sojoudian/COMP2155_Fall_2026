# File: example3_transfer.py
from netmiko import ConnectHandler, FileTransfer

r1 = {
    "device_type": "cisco_ios",
    "host": "10.0.0.254",
    "username": "admin",
    "password": "cisco123",
}

connection = ConnectHandler(**r1)
config = connection.send_command("show running-config")
with open("R1_backup.txt", "w") as file:
    file.write(config)
print("Saved", len(config.splitlines()), "lines to R1_backup.txt")

with FileTransfer(connection, source_file="R1_backup.txt", dest_file="R1_backup.txt") as transfer:
    print("File system:", transfer.file_system)
    if not transfer.check_file_exists():
        transfer.transfer_file()
        print("Uploaded R1_backup.txt")
    else:
        print("R1_backup.txt is already on R1")
    print("Same MD5:", transfer.verify_file())
print(connection.send_command(f"dir {transfer.file_system}"))
connection.disconnect()
