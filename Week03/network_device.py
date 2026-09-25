import platform
import socket
import subprocess



class Device:
    count = 0
    def __init__(self, hostname, host):
        self.hostname = hostname
        self.host = host
        self.ip = "no DNS"
        self.status = "DOWN"
        Device.count += 1

    @property
    def hostname(self):
        return self.__hostname
    @hostname.setter
    def hostname(self, value):
        if len(value) < 3:
            raise ValueError("invalid hostname")
        self.__hostname = value
    @classmethod
    def from_row(cls, row):
        return cls(row["hostname"], row["host"])
    @staticmethod
    def ping_flag():
        if platform.system() == "Windows":
            return "-n"
        return "-c"

    def check(self):
        try:
            self.ip = socket.gethostbyname(self.host)
            self.prob()
            self.status = "UP"
        except Exception:
            self.status = "DOWN"
    def probe(self):
        command = ["ping", Device.ping_flag(), "1", self.ip]
        subprocess.run(command, capture_output=True, timeout=3, check=True)