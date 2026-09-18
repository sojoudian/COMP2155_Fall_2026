FIRST_DAY=1
LAST_DAY=31
MIN_HOSTNAME=3
OCTET_COUNT=4
MIN_OCTET=0
MAX_OCTET=255

def check_ipv4(address: str):
    parts = address.split(".")
    if len(parts) != OCTET_COUNT:
        raise ValueError(f"{address} needs {OCTET_COUNT} parts with a dot between them.")
    for part in parts:
        if not part.isdigit():
            raise ValueError(f"{address} needs only digits.")
        value = int(part)
        if value < MIN_OCTET or value > MAX_OCTET:
            raise ValueError(f"{address!r} holds the part {value}, which is outside of 0 to 255 > {MAX_OCTET}.")



def check_days(start_day: int, end_day: int) -> None:
    if start_day < FIRST_DAY or start_day > LAST_DAY:
        raise ValueError(f"The start day {start_day} is out of range 1 to 31.")
    if end_day < FIRST_DAY or end_day > LAST_DAY:
        raise ValueError(f"The end day {end_day} is out of range 1 to 31.")
    if end_day < start_day:
        raise ValueError(f"The end day {end_day} is before the start day. {start_day}.")

def check_hostname(hostname: str) -> None:
    if len(hostname) < MIN_HOSTNAME:
        raise ValueError(f"The hostname {hostname} needs {MIN_HOSTNAME} characters or more")
    if " " in hostname:
        raise ValueError(f"The hostname {hostname} holds a space. There should be no whitespace.")


class IPAddress:
    """One static IP addr, and the lease on it"""
    def __init__(self, address: str, vlan: int):
        check_ipv4(address)
        self.address = address
        self.vlan = vlan
        # A free address holds None in these 3 attributes
        self.hostname = str | None = None
        self.start_day = int | None = None
        self.end_day = int | None = None

    def is_free(self) -> bool:
        return self.hostname is None

    def lease_days(self) -> int:
        if self.is_free():
            return 0
        return self.end_day - self.start_day + 1

    def assign(self, hostname: str, start_day: int, end_day: int) -> None:
        if not self.is_free():
            raise ValueError(f"{self.address} already belongs to {self.hostname}")

        self.hostname = hostname
        self.start_day = start_day
        self.end_day = end_day

    def release(self) -> tuple[str, int]:
        if self.is_free():
            raise ValueError(f"{self.address} holds no lease")
        record = (self.hostname, self.lease_days())
        self.hostname = None
        self.start_day = None
        self.end_day = None
        return record

    def __str__(self) -> str:
        head = f"{self.address: < 12} VLAN {self.vlan:<4}"
        if self.is_free():
            return f"{head} free"
        return f"{head} {self.hostname} holds day {self.start_day} to {self.end_day}"

class AddressPool:
    def __init__(self, addresses: list[IPAddress]):
        self.addresses = addresses
    def lease(self, hostname: str, start_day: int, end_day: int) -> IPAddress:
        check_hostname(hostname)
        check_days(start_day, end_day)
        for item in self.addresses:
            if item.is_free():
                item.assign(hostname, start_day, end_day)
                return item

    def release(self, address: str) -> tuple[str, int]:
        for item in self.addresses:
            if item.address == address:
                return item.release()

    def show(self, title: str) -> None:
        print(title)
        for item in self.addresses:
            print("", item)
















