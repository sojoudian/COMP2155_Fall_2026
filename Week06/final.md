⏺ 1. Open **Windows PowerShell** normally. Do not use "Run as administrator".
  2. Run these lines:

     ```powershell
     $putty = 'C:\Program Files\PuTTY\putty.exe'
     $k = 'HKCU:\Software\Classes\telnet'
     New-Item -Path "$k\shell\open\command" -Force | Out-Null
     Set-ItemProperty -Path $k -Name '(default)' -Value 'URL:Telnet Protocol'
     Set-ItemProperty -Path $k -Name 'URL Protocol' -Value ''
     Set-ItemProperty -Path "$k\shell\open\command" -Name '(default)' -Value "`"$putty`" %1"
     ```

  3. Close all Chrome windows, then open PNETLab and click the node.

  You do not need to restart Windows.
