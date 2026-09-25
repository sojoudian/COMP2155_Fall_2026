import platform
import socket
import subprocess

class Device:
    count = 0
    def __init__(self, hostname, host):
        self.hostname = hostname
        self.host = host
        self.ip = "no DNS"
        self.down = "Down"
        Device.count += 1

    @property
    def hostname(self):
        return self.__hostname
    @hostname.setter
    def hostname(self, value):
        if len(value)  < 3:
            raise ValueError("Invalid hostname")
        self.__hostname = value
    @classmethod
    def from_row(cls, row):
        return cls(row["hostname"], row["host"])
    @staticmethod
    def ping_flag():
        if platform.system() == "Windows":
            return "-n"
        return "-c"