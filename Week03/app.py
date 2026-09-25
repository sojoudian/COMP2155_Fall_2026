import csv
from network_devices import Device, Server


def main():
    file = open("devices.csv")
    devices = []
    for row in csv.DictReader(file):
        if row["active"] == "yes":
            if row["type"] == "Server":
                devices.append(Server.from_row(row))
            else:
                devices.append(Device.from_row(row))
    file.close()
    for device in devices:
        print(device)

if __name__ == "__main__":
    main()