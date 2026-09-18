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
    if FIRST_DAY <= start_day <= end_day <= LAST_DAY:
        raise ValueError(f"The days {start_day} to {end_day} are outside of {FIRST_DAY} and {LAST_DAY}")

def check_hostname(hostname: str) -> None:
    if len(hostname) < MIN_HOSTNAME or " " in hostname:
        raise ValueError(f"The hostname {hostname} needs {MIN_HOSTNAME} characters, and no space.")




