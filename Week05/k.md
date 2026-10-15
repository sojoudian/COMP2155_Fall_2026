Open **Windows PowerShell** from the Start menu. Do not use "Run as administrator". The prompt must show `PS C:\Users\COMP2155a>`.

  Then run all of these lines:

  ```powershell
  whoami
  $putty = 'C:\Program Files\PuTTY\putty.exe'
  Test-Path $putty
  $k = 'HKCU:\Software\Classes\telnet'
  New-Item -Path "$k\shell\open\command" -Force | Out-Null
  Set-ItemProperty -Path $k -Name '(default)' -Value 'URL:Telnet Protocol'
  Set-ItemProperty -Path $k -Name 'URL Protocol' -Value ''
  Set-ItemProperty -Path "$k\shell\open\command" -Name '(default)' -Value "`"$putty`" %1"
  (Get-ItemProperty "$k\shell\open\command").'(default)'
  Start-Process 'telnet://127.0.0.1:23'
  ```

  These are the correct results:

  - `whoami` shows the `COMP2155a` account.
  - `Test-Path` shows `True`.
  - The `Get-ItemProperty` line shows `"C:\Program Files\PuTTY\putty.exe" %1`.
  - PuTTY opens with "Connection refused".

  Then close all Chrome windows, open PNETLab, and click R1.
