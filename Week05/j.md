  $putty = 'C:\Program Files\PuTTY\putty.exe'
  $k = 'HKCU:\Software\Classes\telnet'
  New-Item -Path "$k\shell\open\command" -Force | Out-Null
  Set-ItemProperty -Path $k -Name '(default)' -Value 'URL:Telnet Protocol'
  Set-ItemProperty -Path $k -Name 'URL Protocol' -Value ''
  Set-ItemProperty -Path "$k\shell\open\command" -Name '(default)' -Value "`"$putty`" %1"
  (Get-ItemProperty "$k\shell\open\command").'(default)'
