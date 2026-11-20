from napalm import get_network_driver

file = open("devices.txt")
hosts = file.read().split()
file.close()

driver = get_network_driver("ios")
for host in hosts:
    router = driver(
        hostname=host,
        username="admin",
        password="cisco123",
        optional_args={"transport": "telnet", "secret": "cisco123"},
    )
    router.open()
    facts = router.get_facts()
    print("=====", facts["hostname"], "=====")
    print("Model:", facts["model"])
    print("Interfaces:", facts["interface_list"])
    print(router.get_interfaces_ip())
    router.close()
