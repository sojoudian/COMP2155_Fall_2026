from napalm import get_network_driver

driver = get_network_driver("ios")
r1 = driver(
    hostname="10.0.0.254",
    username="admin",
    password="cisco123",
    optional_args={"transport": "telnet", "secret": "cisco123"},
)

r1.open()
print(r1.get_interfaces())
print(r1.get_interfaces_ip())
r1.close()
