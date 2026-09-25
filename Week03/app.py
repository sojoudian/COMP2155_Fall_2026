import csv
from network_device import Device, Server

def log(message):
    file = open("activities.log", "a")
    file.write(message + "\n")
    file.close()

def main():
    file = open("devices.csv")
    devices = []
    for row in csv.DictReader(file):
        if row["active"] == "yes":
            if row["type"] == "Server":
                devices.append(Server.from_row(row))
            else:
                devices.append((Device.from_row(row)))
    file.close()
    for device in devices:
        device.check()
        print(device)
        log(str(device))

if __name__ == "__main__":
    main()
