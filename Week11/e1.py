# e1
from napalm import get_network_driver

driver = get_network_driver("ios")
r1 = driver(
    hostname="10.0.0.254",
    username="admin",
    password="cisco123",
    optional_args={"secret": "cisco123"},
)

r1.open()
facts = r1.get_facts()
print("Hostname:", facts["hostname"])
print("Model:", facts["model"])
print("OS Version:", facts["os_version"])
print("Serial Number:", facts["serial_number"])
print("Uptime (seconds):", facts["uptime"])
r1.close()
