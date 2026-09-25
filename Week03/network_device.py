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