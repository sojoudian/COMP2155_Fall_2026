## 13. Install Paramiko (Windows)

In the PyCharm terminal of your project:

```
pip install paramiko==4.0.0
```

Use version 4.0.0. Newer versions no longer include the `ssh-rsa` signature type that the scripts below select.

## 14. First script: one command

`main.py`:

```python
# Example 2: run SEVERAL commands with exec_command()
# Cisco IOS normally accepts only one exec_command() per connection,
# so we connect again for each command.
import paramiko


def exec_one(command):
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(
        "192.168.113.11",
        username="admin",
        password="cisco123",
        allow_agent=False,
        look_for_keys=False,
    )
    stdin, stdout, stderr = ssh.exec_command(command)
    output = stdout.read().decode()
    ssh.close()
    return output


for command in ["show clock", "show ip interface brief", "show version | include uptime"]:
    print("=====", command, "=====")
    print(exec_one(command))
```

What each part does:

- `AutoAddPolicy()` accepts the router's host key on the first connection.
- `key_filename` is your private key; `allow_agent=False` and `look_for_keys=False` make Paramiko use only that key.
- `disabled_algorithms` turns off the two newer RSA signature types, so the login uses `ssh-rsa`.
- `exec_command()` runs one command and returns its output in `stdout`.

## 15. `exec_command()` and `run()` with `invoke_shell()`

- `invoke_shell()` opens an interactive session, like typing in PuTTY. Many commands can run in one session, including configuration mode. The `run()` helper sends a command, waits one second, and returns what the router printed.

## 16. Second script: many commands in one session

`shell.py`:

```python
# Example 3: run SEVERAL commands in ONE session with invoke_shell()
import time

import paramiko


def run(shell, command):
    shell.send(command + "\n")
    time.sleep(1)
    output = ""
    while shell.recv_ready():
        output += shell.recv(65535).decode()
    return output


ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect(
    "192.168.113.11",
    username="admin",
    password="cisco123",
    allow_agent=False,
    look_for_keys=False,
)
shell = ssh.invoke_shell()
run(shell, "terminal length 0")

for command in ["show clock", "show ip interface brief", "show users"]:
    print(run(shell, command))

ssh.close()
```

What each part does:

- `invoke_shell()` opens one session. All commands use this session, so the script connects only one time.
- `terminal length 0` stops the `--More--` prompt, so the router sends all lines of a long output.
- `recv_ready()` is `True` while the router has more output to send.

## 17. Third script: save the running-config to a file

`backup.py`:

```python
# Example 4: save the running-config of R1 to a text file
import paramiko

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect(
    "192.168.113.11",
    username="admin",
    password="cisco123",
    allow_agent=False,
    look_for_keys=False,
)
stdin, stdout, stderr = ssh.exec_command("show running-config")
config = stdout.read().decode()
ssh.close()

with open("R1_running-config.txt", "w") as file:
    file.write(config)

print("Saved", len(config.splitlines()), "lines to R1_running-config.txt")
```

What each part does:

- `exec_command("show running-config")` gets the full configuration of R1.
- `open(..., "w")` makes the file `R1_running-config.txt` in the project folder. If the file is already there, the script writes over it.
