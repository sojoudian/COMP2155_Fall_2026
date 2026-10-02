# Purpose: correct the VMware error that refers to KB article 81623:
#   "VMware Workstation does not support virtualized performance counters on this host."
#
# The script sets "Virtualize CPU performance counters" to off in the .vmx file
# of the PNETLab virtual machine. The lab does not use these counters.
#
# Before you run this script, shut down the virtual machine and close VMware.
#
# Usage:
#   .\fix-vmware-kb81623.ps1
#   .\fix-vmware-kb81623.ps1 -VmxPath "C:\path\to\PNET_4.2.10.vmx"
#   .\fix-vmware-kb81623.ps1 -ClearVtx
#
# -VmxPath  gives the .vmx file. Without it, the script looks for PNET*.vmx
#           in "Documents\Virtual Machines".
# -ClearVtx also sets "Virtualize Intel VT-x/EPT or AMD-V/RVI" to off.
#
# The script keeps the initial file as a backup with the extension .bak.
#
# This script was not tested on a Windows computer.

param(
    [string]$VmxPath,
    [switch]$ClearVtx
)

$ErrorActionPreference = 'Stop'

# 1. Make sure that VMware is closed.
$running = Get-Process -Name 'vmware', 'vmplayer', 'vmware-vmx' -ErrorAction SilentlyContinue
if ($running) {
    Write-Host 'VMware is open. Shut down the virtual machine, close VMware, and run this script again.'
    exit 1
}

# 2. Find the .vmx file of the virtual machine.
if ($VmxPath) {
    if (-not (Test-Path -LiteralPath $VmxPath -PathType Leaf)) {
        Write-Host "File not found: $VmxPath"
        exit 1
    }
    $files = @(Get-Item -LiteralPath $VmxPath)
} else {
    $folder = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Virtual Machines'
    $files = @(Get-ChildItem -Path $folder -Filter '*.vmx' -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -eq '.vmx' -and $_.Name -like 'PNET*' })
    if ($files.Count -eq 0) {
        Write-Host "No PNET virtual machine found in: $folder"
        Write-Host 'Run the script again with the path of the .vmx file:'
        Write-Host '  .\fix-vmware-kb81623.ps1 -VmxPath "C:\path\to\PNET_4.2.10.vmx"'
        exit 1
    }
}

# 3. Set the values to off in each file.
$keys = @('vpmc.enable')
if ($ClearVtx) {
    $keys += 'vhv.enable'
}

# This encoding reads and writes each byte without a change.
$encoding = [System.Text.Encoding]::GetEncoding(28591)

foreach ($file in $files) {
    $path = $file.FullName
    $text = [System.IO.File]::ReadAllText($path, $encoding)
    $changed = $false

    foreach ($key in $keys) {
        $line = $key + ' = "FALSE"'
        $pattern = '(?im)^[ \t]*' + [regex]::Escape($key) + '[ \t]*=[^\r\n]*'
        $found = [regex]::Match($text, $pattern)
        if (-not $found.Success) {
            # A key that is not in the file is off.
            Write-Host "Already off: $key"
        } elseif ($found.Value.Trim() -eq $line) {
            Write-Host "Already off: $key"
        } else {
            $text = [regex]::Replace($text, $pattern, $line)
            $changed = $true
            Write-Host "Set to off:  $key"
        }
    }

    if ($changed) {
        $backup = "$path.bak"
        if (-not (Test-Path -LiteralPath $backup)) {
            Copy-Item -LiteralPath $path -Destination $backup
        }
        [System.IO.File]::WriteAllText($path, $text, $encoding)
        Write-Host "Changed: $path"
        Write-Host "Backup:  $backup"
    } else {
        Write-Host "No change necessary: $path"
    }
}
