# fix-vmware.ps1
#
# Purpose: make the PNETLab virtual machine start in VMware Workstation on Windows,
# and set nested virtualization to on when the computer permits it.
#
# This one script corrects these VMware errors:
#   "VMware Workstation does not support virtualized performance counters on this host."
#   "Module 'VPMC' power on failed."                      (KB article 81623)
#   "VMware Workstation does not support nested virtualization on this host."
#   "Module 'HV' power on failed."
#   "Virtualized Intel VT-x/EPT is not supported on this platform."
#
# How to use it:
#   1. Run:  powershell -ExecutionPolicy Bypass -File .\fix-vmware.ps1
#   2. Start the virtual machine. It starts immediately, without nested virtualization.
#   3. Restart the computer when the script tells you.
#   4. Run the script again after the restart. It then sets nested virtualization to on.
#
# What the script does:
#   A. Virtual machine (.vmx file):
#      - "Virtualize CPU performance counters" goes off at all times.
#      - "Virtualize Intel VT-x/EPT or AMD-V/RVI" goes on only when the Windows
#        hypervisor is off. If not, it goes off, so that the virtual machine starts.
#      - The script keeps the initial file as a backup with the extension .bak.
#   B. Windows (needs Administrator rights and one restart):
#      - The script sets the Windows hypervisor, Hyper-V, Virtual Machine Platform,
#        Windows Hypervisor Platform, Windows Sandbox, Memory Integrity,
#        and Credential Guard to off.
#
# Effects of part B:
#   - The security of the computer decreases.
#   - WSL 2, Docker Desktop, Windows Sandbox, and Hyper-V virtual machines stop.
#
# The script cannot correct these conditions. The virtual machine then operates
# without nested virtualization:
#   - VT-x or AMD-V is off in the BIOS or UEFI.
#   - Credential Guard or Memory Integrity has a UEFI lock.
#   - A domain, Intune, or Group Policy applies the settings again.
#
# Parameters:
#   -VmxPath "C:\path\to\PNET_4.2.10.vmx"   gives the .vmx file.
#   -VmOnly                                  does only part A.
#   -HostOnly                                does only part B.

param(
    [string]$VmxPath,
    [switch]$VmOnly,
    [switch]$HostOnly
)

$ErrorActionPreference = 'Stop'

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-WindowsHypervisor {
    # If the check fails, the script uses the safe result: the hypervisor is on.
    try {
        return [bool](Get-CimInstance -ClassName Win32_ComputerSystem).HypervisorPresent
    } catch {
        return $true
    }
}

function Test-FirmwareVirtualization {
    try {
        $cpu = Get-CimInstance -ClassName Win32_Processor | Select-Object -First 1
        return [bool]$cpu.VirtualizationFirmwareEnabled
    } catch {
        return $false
    }
}

function Wait-VMwareClosed {
    $names = @('vmware', 'vmplayer', 'vmware-vmx')
    $first = $true
    while (Get-Process -Name $names -ErrorAction SilentlyContinue) {
        if ($first) {
            Write-Host ''
            Write-Host 'VMware is open.'
            Write-Host 'Shut down the virtual machine and close VMware. The script then continues.'
            $first = $false
        }
        Start-Sleep -Seconds 2
    }
}

function Find-VmxFiles {
    $paths = @{}

    # VMware keeps the list of its virtual machines in these two files.
    $lists = @()
    if ($env:APPDATA) {
        $lists += Join-Path $env:APPDATA 'VMware\inventory.vmls'
        $lists += Join-Path $env:APPDATA 'VMware\preferences.ini'
    }
    foreach ($list in $lists) {
        try {
            if (-not (Test-Path -LiteralPath $list -PathType Leaf)) { continue }
            $content = [System.IO.File]::ReadAllText($list)
            foreach ($match in [regex]::Matches($content, '"([^"\r\n]+\.vmx)"')) {
                $path = $match.Groups[1].Value
                try {
                    if (Test-Path -LiteralPath $path -PathType Leaf) {
                        $paths[$path.ToLowerInvariant()] = $path
                    }
                } catch { }
            }
        } catch { }
    }

    # The default folder for virtual machines.
    $folders = @()
    $documents = [Environment]::GetFolderPath('MyDocuments')
    if ($documents) { $folders += Join-Path $documents 'Virtual Machines' }
    if ($env:USERPROFILE) { $folders += Join-Path $env:USERPROFILE 'Documents\Virtual Machines' }
    foreach ($folder in $folders) {
        try {
            if (-not (Test-Path -LiteralPath $folder -PathType Container)) { continue }
            $items = Get-ChildItem -LiteralPath $folder -Filter '*.vmx' -Recurse -File -ErrorAction SilentlyContinue
            foreach ($item in $items) {
                if ($item.Extension -eq '.vmx') {
                    $paths[$item.FullName.ToLowerInvariant()] = $item.FullName
                }
            }
        } catch { }
    }

    return @($paths.Values)
}

function Set-VmxValue {
    param([string]$Text, [string]$Key, [string]$Value)

    $line = $Key + ' = "' + $Value + '"'
    $pattern = '(?im)^[ \t]*' + [regex]::Escape($Key) + '[ \t]*=[^\r\n]*'
    if ([regex]::IsMatch($Text, $pattern)) {
        return [regex]::Replace($Text, $pattern, $line.Replace('$', '$$'))
    }

    $newline = "`r`n"
    if (-not $Text.Contains("`r`n")) { $newline = "`n" }
    if ($Text.Length -gt 0 -and -not $Text.EndsWith("`n")) { $Text += $newline }
    return $Text + $line + $newline
}

function Get-VmxValue {
    param([string]$Text, [string]$Key)

    $pattern = '(?im)^[ \t]*' + [regex]::Escape($Key) + '[ \t]*=[ \t]*"?([^"\r\n]*)"?'
    $match = [regex]::Match($Text, $pattern)
    if ($match.Success) { return $match.Groups[1].Value.Trim() }
    return '(not set)'
}

function Update-VmxFile {
    param([string]$Path, [string]$Nested)

    Write-Host ''
    Write-Host "Virtual machine: $Path"
    try {
        # This encoding reads and writes each byte without a change.
        $encoding = [System.Text.Encoding]::GetEncoding(28591)
        $before = [System.IO.File]::ReadAllText($Path, $encoding)

        $after = Set-VmxValue -Text $before -Key 'vpmc.enable' -Value 'FALSE'
        $after = Set-VmxValue -Text $after -Key 'vhv.enable' -Value $Nested
        if ($Nested -eq 'FALSE' -and (Get-VmxValue -Text $after -Key 'vvtd.enable') -ne '(not set)') {
            $after = Set-VmxValue -Text $after -Key 'vvtd.enable' -Value 'FALSE'
        }

        if ($after -cne $before) {
            $backup = "$Path.bak"
            if (-not (Test-Path -LiteralPath $backup)) {
                Copy-Item -LiteralPath $Path -Destination $backup
            }
            [System.IO.File]::WriteAllText($Path, $after, $encoding)
        }

        # Read the file again to make sure that the values are correct.
        $check = [System.IO.File]::ReadAllText($Path, $encoding)
        $counters = Get-VmxValue -Text $check -Key 'vpmc.enable'
        $vtx = Get-VmxValue -Text $check -Key 'vhv.enable'
        Write-Host "  Virtualize CPU performance counters (vpmc.enable): $counters"
        Write-Host "  Virtualize Intel VT-x/EPT or AMD-V/RVI (vhv.enable): $vtx"
        if ($counters -eq 'FALSE' -and $vtx -eq $Nested) {
            Write-Host '  Result: OK'
            return $true
        }
        Write-Host '  Result: NOT OK. The file does not have the correct values.'
        return $false
    } catch {
        Write-Host "  Result: NOT OK. $($_.Exception.Message)"
        Write-Host '  Close VMware and run the script again.'
        return $false
    }
}

function Show-VbsStatus {
    try {
        $guard = Get-CimInstance -Namespace 'root\Microsoft\Windows\DeviceGuard' -ClassName Win32_DeviceGuard
        Write-Host "  Virtualization-based security status: $($guard.VirtualizationBasedSecurityStatus) (0 = off, 1 = on but not active, 2 = active)"
        Write-Host "  Security services that run: $($guard.SecurityServicesRunning -join ', ') (1 = Credential Guard, 2 = Memory Integrity)"
    } catch {
        Write-Host '  The status of virtualization-based security is not available.'
    }
}

function Disable-WindowsHypervisor {
    Write-Host ''
    Write-Host 'Windows: the script now sets the Windows hypervisor to off.'

    & bcdedit.exe /set hypervisorlaunchtype off | Out-Null
    Write-Host '  Hypervisor start: off'

    $features = @('Microsoft-Hyper-V-All', 'HypervisorPlatform', 'VirtualMachinePlatform', 'Containers-DisposableClientVM')
    foreach ($name in $features) {
        try {
            $feature = Get-WindowsOptionalFeature -Online -FeatureName $name -ErrorAction Stop
            if ("$($feature.State)" -eq 'Enabled') {
                Disable-WindowsOptionalFeature -Online -FeatureName $name -NoRestart -ErrorAction Stop | Out-Null
                Write-Host "  Windows feature set to off: $name"
            }
        } catch { }
    }

    $values = @(
        @('HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard', 'EnableVirtualizationBasedSecurity'),
        @('HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity', 'Enabled'),
        @('HKLM\SYSTEM\CurrentControlSet\Control\Lsa', 'LsaCfgFlags'),
        @('HKLM\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard', 'LsaCfgFlags'),
        @('HKLM\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard', 'EnableVirtualizationBasedSecurity')
    )
    foreach ($value in $values) {
        & reg.exe add $value[0] /v $value[1] /t REG_DWORD /d 0 /f | Out-Null
    }
    Write-Host '  Virtualization-based security, Memory Integrity, Credential Guard: off'
}

function Invoke-HostPart {
    $marker = $null
    if ($env:ProgramData) { $marker = Join-Path $env:ProgramData 'fix-vmware-host.txt' }

    Write-Host ''
    if (-not (Test-WindowsHypervisor)) {
        Write-Host 'Windows: the Windows hypervisor is off. No change is necessary.'
        return
    }

    # If the changes are already applied, find out if a restart occurred after them.
    if ($marker -and (Test-Path -LiteralPath $marker)) {
        $applied = (Get-Item -LiteralPath $marker).LastWriteTime
        $boot = $null
        try { $boot = (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime } catch { }
        if ($boot -and $boot -gt $applied) {
            Write-Host 'Windows: the Windows hypervisor stays on after the changes and a restart.'
            Write-Host '  This computer does not permit nested virtualization at this time.'
            Write-Host '  The virtual machine operates without nested virtualization.'
            Write-Host '  Possible causes: a UEFI lock, a policy of an organization, or Shut down used as an alternative to Restart.'
            Show-VbsStatus
            return
        }
        Write-Host 'Windows: the changes are applied, but the computer did not restart.'
        Request-Restart
        return
    }

    if (-not (Test-Admin)) {
        Write-Host 'Windows: the Windows hypervisor is on. Administrator rights are necessary to set it to off.'
        Write-Host '  A second window opens. Select Yes in the User Account Control window.'
        $arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '" -HostOnly'
        try {
            Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $arguments -Wait
        } catch {
            Write-Host '  Administrator rights were not given. Windows has no change.'
            Write-Host '  The virtual machine operates without nested virtualization.'
        }
        return
    }

    Disable-WindowsHypervisor
    if ($marker) {
        try { Set-Content -LiteralPath $marker -Value (Get-Date).ToString('o') } catch { }
    }
    Request-Restart
}

function Request-Restart {
    Write-Host ''
    Write-Host 'A restart is necessary before nested virtualization is available.'
    Write-Host 'After the restart, run this script again. It then sets nested virtualization to on.'
    Write-Host 'You can do the lab before the restart. The virtual machine starts now.'
    $answer = Read-Host 'Save your work. Restart the computer now? Type Y for yes, N for no'
    if ($answer -match '^\s*(y|yes)\s*$') {
        try {
            Restart-Computer
        } catch {
            Write-Host 'The restart did not start. Restart the computer from the Start menu (Restart, not Shut down).'
        }
    } else {
        Write-Host 'No restart. Restart the computer later (Restart, not Shut down).'
    }
}

# ---------------------------------------------------------------------------
# Main part
# ---------------------------------------------------------------------------

Write-Host 'fix-vmware.ps1'

# Part A: the virtual machine.
if (-not $HostOnly) {
    $hypervisor = Test-WindowsHypervisor
    $nested = 'FALSE'
    if ($hypervisor) {
        Write-Host 'The Windows hypervisor is on. The virtual machine gets nested virtualization: off.'
    } elseif (Test-FirmwareVirtualization) {
        $nested = 'TRUE'
        Write-Host 'The Windows hypervisor is off. The virtual machine gets nested virtualization: on.'
    } else {
        Write-Host 'VT-x or AMD-V is off in the BIOS or UEFI. Set it to on in the BIOS or UEFI.'
        Write-Host 'The virtual machine gets nested virtualization: off.'
    }

    Wait-VMwareClosed

    if ($VmxPath) {
        $targets = @($VmxPath)
        if (-not (Test-Path -LiteralPath $VmxPath -PathType Leaf)) {
            Write-Host "File not found: $VmxPath"
            $targets = @()
        }
    } else {
        $all = @(Find-VmxFiles)
        $targets = @($all | Where-Object { [System.IO.Path]::GetFileName($_) -like '*PNET*' })
        if ($targets.Count -eq 0) { $targets = $all }
    }

    if ($targets.Count -eq 0) {
        Write-Host ''
        Write-Host 'No virtual machine found.'
        Write-Host 'Run the script again with the path of the .vmx file:'
        Write-Host '  powershell -ExecutionPolicy Bypass -File .\fix-vmware.ps1 -VmxPath "C:\path\to\PNET_4.2.10.vmx"'
    } else {
        $good = 0
        foreach ($target in $targets) {
            if (Update-VmxFile -Path $target -Nested $nested) { $good++ }
        }
        Write-Host ''
        Write-Host "Virtual machines corrected: $good of $($targets.Count)"
    }
}

# Part B: Windows.
if (-not $VmOnly) {
    Invoke-HostPart
}

Write-Host ''
Write-Host 'The script is complete.'
if ($HostOnly) {
    [void](Read-Host 'Press Enter to close this window')
}
