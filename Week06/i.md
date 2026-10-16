  1. **Windows PowerShell 5.1 is the only shell that reads the quotes correctly.**
     - In `cmd.exe`, single quotes are not quotes, so `reg` gives `ERROR: Invalid syntax`.
     - In PowerShell 7, `reg` writes the value with extra backslashes (`\"C:\...`). It says "The operation completed successfully", but the command in the value does not run.
  2. **The key has no `URL Protocol` value.** On your PC, the Telnet Client feature can register `telnet:` for you. If the college computer does not have it, Windows does not know that `telnet:` is a URL
  protocol.
  3. **PuTTY can be in a different folder** on the college computer.

  Run these lines in PowerShell (5.1 or 7). They do not use `reg.exe`, so the quotes are always correct, and they need no admin rights:

  ```powershell
  $putty = 'C:\Program Files\PuTTY\putty.exe'
  Test-Path $putty
  $k = 'HKCU:\Software\Classes\telnet'
  New-Item -Path "$k\shell\open\command" -Force | Out-Null
  Set-ItemProperty -Path $k -Name '(default)' -Value 'URL:Telnet Protocol'
  Set-ItemProperty -Path $k -Name 'URL Protocol' -Value ''
  Set-ItemProperty -Path "$k\shell\open\command" -Name '(default)' -Value "`"$putty`" %1"
  ```

  If `Test-Path` gives `False`, set `$putty` to the correct path and run the lines again.

  The change applies at once, so you do not restart Windows. To test it without the browser, run `Start-Process 'telnet://<IP>:<port>'`. PuTTY must open.

  If PuTTY still does not open, run this line:

  ```powershell
  Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\telnet\UserChoice' -ErrorAction SilentlyContinue
  ```

  If it shows a `ProgId`, a Windows default-app setting is used instead of your key. The college IT department can set this, and you cannot change it with these commands.
