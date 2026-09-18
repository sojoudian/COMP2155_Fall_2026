from multiprocessing.managers import rebuild_as_list

FIRST_DAY = 1
LAST_DAY = 31
MIN_HOSTNAME = 3
OCTET_COUNT = 4
MIN_OCTET= 0
MAX_OCTET= 255

def check_ipv4(address: str) -> None:
    parts = address.split(".")
    if len(parts) != OCTET_COUNT or not all(
        p.isdigit() and MIN_OCTET <= int(p) <= MAX_OCTET for p in parts):
        raise ValueError(f"Invalid IPv4 address: {address}")

def check_days(start_day: int, end_day: int) -> None:
    if not FIRST_DAY <= start_day <= end_day <= LAST_DAY:
        raise ValueError(f"The days {start_day} to {end_day} are outside of {FIRST_DAY} and {LAST_DAY}")

def check_hostname(hostname: str) -> None:
    if len(hostname) < MIN_HOSTNAME or " " in hostname:
        raise ValueError(f"The hostname {hostname} needs {MIN_HOSTNAME} characters, and no space.")


class IPAddress:
    def __init__(self, address: str, vlan: int):
        check_ipv4(address)
        self.address = address
        self.vlan = vlan
        self.hostname: str | None = None
        self.start_day: int | None = None
        self.end_day: int | None = None

    def assign(self, hostname: str, start_day: int, end_day: int) -> None:
        self.hostname = hostname
        self.start_day = start_day
        self.end_day = end_day

    def release(self) -> tuple[str, int]:
        record = (self.hostname, self.start_day, self.end_day + 1)
        self.hostname = self.start_day = self.end_day = None
        return record
    def __str__(self) -> str:
        state = "free" if self.hostname is None else f"{self.hostname} day {self.start_day} to {self.end_day}"
        return f"{self.address:<12} VLAN {self.vlan:<4} {state}"

# Registration code: K0NE
# Atklass: 6DTJ
# github.com/sojoudian/COMP2155_Fall_2026

class AddressPool:
    def __init__(self, addresses: list[IPAddress]):
        self.addresses = addresses

    def lease(self, hostname: str, start_day: int, end_day: int) -> IPAddress | None:
        check_hostname(hostname)
        check_days(start_day, end_day)
        for item in self.addresses:
            if item.hostname is None:
                item.assign(hostname, start_day, end_day)
                return item
        return None

    def release(self, address: str) -> tuple[str, int] | None:
        for item in self.addresses:
            if item.address == address and item.hostname is not None:
                return item.release()
        return None


def main():
    pool = AddressPool([IPAddress(f"10.0.0.{n}", 10) for n in range(11, 15)])
    pool.lease("router-a", 1, 5)
    pool.lease("router-b", 3, 8)
    print("released: ", pool.release("10.0.0.11"))
    for item in pool.addresses:
        for check, args in [(check_ipv4, ("10.0.0.300",)), (check_days, (20, 10)), (check_hostname, ("ab",))]:
            try:
                check(*args)
            except ValueError as error:
                print("Rejected: ", error)

if __name__ == "__main__":
    main()

