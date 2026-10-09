# fix-vmware.ps1
#
# Purpose: make nested virtualization available to VMware Workstation on Windows,
# and make the PNETLab virtual machine start.
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
#   2. Select Yes in the User Account Control window.
#   3. Restart the computer when the script asks (Restart, not Shut down).
#   4. During the start, a black screen asks about Credential Guard and
#      virtualization-based security. Press F3 for each question.
#   5. Run the script again after the restart. It then sets nested virtualization to on.
#
# What the script does:
#   A. Virtual machine (.vmx file):
#      - "Virtualize Intel VT-x/EPT or AMD-V/RVI" goes on when the Windows hypervisor is off.
#        While the Windows hypervisor is on, it goes off, so that the virtual machine starts.
#        With -NoNested, it always goes off.
#      - "Virtualize CPU performance counters" goes off. Nested virtualization does not use it.
#      - The script keeps the initial file as a backup with the extension .bak.
#   B. Windows (needs Administrator rights and one restart). The script sets these items to off:
#      - The Windows hypervisor and the virtual secure mode (boot settings).
#      - Hyper-V, Windows Hypervisor Platform, Virtual Machine Platform, Windows Sandbox,
#        Application Guard.
#      - Virtualization-based security, Memory Integrity, Credential Guard,
#        System Guard Secure Launch (Firmware protection), Kernel-mode Stack Protection,
#        Windows Hello Enhanced Sign-in Security.
#      - The local Group Policy settings for virtualization-based security go to "Not configured".
#        The script keeps the initial Registry.pol file as a backup with the extension .bak.
#      - The UEFI lock of virtualization-based security and Credential Guard
#        (the Microsoft procedure with SecConfig.efi, which needs the F3 key at the start).
#      - BitLocker protection stops for one restart only, to prevent a recovery key question.
#   C. Antivirus programs: the script finds Avast, AVG, and Kaspersky. These programs can use
#      VT-x or AMD-V, and then VMware cannot use it. The script shows the setting to set to off.
#
# Effects of part B:
#   - The security of the computer decreases.
#   - WSL 2, Docker Desktop, Windows Sandbox, and Hyper-V virtual machines stop.
#
# The script cannot correct these conditions:
#   - VT-x or AMD-V is off in the BIOS or UEFI.
#   - A domain Group Policy or Intune applies the settings again.
#   - An antivirus program uses VT-x or AMD-V. You must set its setting to off.
#
# Parameters:
#   -VmxPath "C:\path\to\PNET.vmx"   gives the .vmx file.
#   -VmOnly                          does only part A.
#   -HostOnly                        does only part B.
#   -Force                           does part B again, although it was done before.
#   -NoNested                        sets nested virtualization to off in the virtual machine
#                                    and does not do part B. The Week04 lab does not need
#                                    nested virtualization. -ClearVtx is the same option.

param(
    [string]$VmxPath,
    [switch]$VmOnly,
    [switch]$HostOnly,
    [switch]$Force,
    [Alias('ClearVtx')]
    [switch]$NoNested
)

$ErrorActionPreference = 'Stop'

# The number of the Windows changes. A higher number has more changes.
$HostLevel = 3
$UefiToolId = '{0cb3b571-2f2e-4343-a879-d86a476d7215}'

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
        Write-Host "  Virtualize Intel VT-x/EPT or AMD-V/RVI (vhv.enable): $vtx"
        Write-Host "  Virtualize CPU performance counters (vpmc.enable): $counters"
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
    $names = @{
        1 = 'Credential Guard'
        2 = 'Memory Integrity'
        3 = 'System Guard Secure Launch'
        4 = 'SMM Firmware Measurement'
        5 = 'Kernel-mode Stack Protection'
        6 = 'Kernel-mode Stack Protection (audit)'
        7 = 'Hypervisor-Enforced Paging Translation'
    }
    try {
        $guard = Get-CimInstance -Namespace 'root\Microsoft\Windows\DeviceGuard' -ClassName Win32_DeviceGuard
        Write-Host "  Virtualization-based security status: $($guard.VirtualizationBasedSecurityStatus) (0 = off, 1 = on but not active, 2 = active)"
        $running = @()
        foreach ($number in @($guard.SecurityServicesRunning)) {
            if ($number -eq 0) { continue }
            $name = $names[[int]$number]
            if (-not $name) { $name = 'unknown' }
            $running += "$number = $name"
        }
        if ($running.Count -eq 0) { $running = @('none') }
        Write-Host "  Security services that run: $($running -join ', ')"
    } catch {
        Write-Host '  The status of virtualization-based security is not available.'
    }
}

function Invoke-Native {
    # Runs a Windows program and shows the result. The result is also in $script:NativeOk.
    param([string]$Label, [string]$File, [string[]]$Arguments, [switch]$Optional)

    $ErrorActionPreference = 'Continue'
    $output = ''
    $code = 1
    try {
        $output = (& $File @Arguments 2>&1 | Out-String).Trim()
        $code = $LASTEXITCODE
    } catch {
        $output = $_.Exception.Message
    }
    $script:NativeOk = ($code -eq 0)
    $script:NativeOutput = $output
    if ($script:NativeOk) {
        Write-Host "  OK       $Label"
    } elseif ($Optional) {
        Write-Host "  SKIPPED  $Label"
    } else {
        Write-Host "  FAILED   $Label"
        if ($output) { Write-Host "           $output" }
    }
}

function Get-FreeDriveLetter {
    $used = @()
    try {
        $used = @([System.IO.DriveInfo]::GetDrives() | ForEach-Object { $_.Name.Substring(0, 1).ToUpperInvariant() })
    } catch { }
    foreach ($letter in @('S', 'T', 'U', 'V', 'W', 'Y', 'Z', 'R', 'Q', 'P')) {
        if ($used -notcontains $letter) { return ($letter + ':') }
    }
    return $null
}

function Test-PolChar {
    param([byte[]]$Bytes, [int]$Position, [char]$Char)

    if ($Position + 1 -ge $Bytes.Length -or $Bytes[$Position] -ne [int]$Char -or $Bytes[$Position + 1] -ne 0) {
        throw "Registry.pol: the character '$Char' is not at byte $Position."
    }
}

function Find-PolEnd {
    # Finds the UTF-16 null character at the end of a string.
    param([byte[]]$Bytes, [int]$Position)

    for ($i = $Position; $i + 1 -lt $Bytes.Length; $i += 2) {
        if ($Bytes[$i] -eq 0 -and $Bytes[$i + 1] -eq 0) { return $i }
    }
    throw "Registry.pol: the string at byte $Position has no end."
}

function Remove-PolEntries {
    # The format of Registry.pol: "PReg", the version (4 bytes), and then the entries.
    # Each entry is [key;value;type;size;data] in UTF-16LE. The type and the size have 4 bytes each.
    # The function removes the entries of $Key, but not the values in $KeepValues.
    # A "**del." entry removes a value. The function uses the value name after "**del.".
    param([byte[]]$Bytes, [string]$Key, [string[]]$KeepValues)

    if ($Bytes.Length -lt 8 -or [System.Text.Encoding]::ASCII.GetString($Bytes, 0, 4) -ne 'PReg') {
        throw 'Registry.pol: the file does not start with PReg.'
    }
    $unicode = [System.Text.Encoding]::Unicode
    $output = New-Object System.IO.MemoryStream
    $output.Write($Bytes, 0, 8)
    $removed = 0
    $position = 8
    while ($position -lt $Bytes.Length) {
        $start = $position
        Test-PolChar $Bytes $position '['
        $end = Find-PolEnd $Bytes ($position + 2)
        $entryKey = $unicode.GetString($Bytes, $position + 2, $end - $position - 2)
        $position = $end + 2
        Test-PolChar $Bytes $position ';'
        $end = Find-PolEnd $Bytes ($position + 2)
        $entryValue = $unicode.GetString($Bytes, $position + 2, $end - $position - 2)
        $position = $end + 2
        Test-PolChar $Bytes $position ';'
        $position += 6
        Test-PolChar $Bytes $position ';'
        if ($position + 6 -gt $Bytes.Length) { throw 'Registry.pol: the file stops in an entry.' }
        $size = [BitConverter]::ToInt32($Bytes, $position + 2)
        $position += 6
        Test-PolChar $Bytes $position ';'
        $position += 2
        if ($size -lt 0 -or $position + $size + 2 -gt $Bytes.Length) {
            throw 'Registry.pol: the size of the data is not correct.'
        }
        $position += $size
        Test-PolChar $Bytes $position ']'
        $position += 2

        $name = $entryValue -replace '^\*\*del\.', ''
        if ($entryKey.TrimEnd('\') -eq $Key -and $KeepValues -notcontains $name) {
            $removed++
        } else {
            $output.Write($Bytes, $start, $position - $start)
        }
    }
    return [pscustomobject]@{ Bytes = $output.ToArray(); Removed = $removed }
}

function Update-GptVersion {
    # gpt.ini has the line "Version=N". The low 16 bits of N are the version of the computer settings.
    # A higher version makes Windows read the local Group Policy again.
    param([string]$Text)

    $match = [regex]::Match($Text, '(?im)^[ \t]*Version[ \t]*=[ \t]*(\d+)')
    if (-not $match.Success) { return $null }
    $version = [long]$match.Groups[1].Value
    $computer = ($version -band 0xFFFF) + 1
    if ($computer -gt 0xFFFF) { $computer = 1 }
    $new = (($version -shr 16) -shl 16) + $computer
    $group = $match.Groups[1]
    return $Text.Substring(0, $group.Index) + $new + $Text.Substring($group.Index + $group.Length)
}

function Remove-LocalVbsPolicy {
    # The local Group Policy "Turn On Virtualization Based Security" keeps its values in Registry.pol.
    # Windows writes these values to the registry again when it reads the Group Policy.
    # The script removes them, so the settings go to "Not configured".
    # DeployConfigCIPolicy and ConfigCIPolicyFilePath are for Application Control. The script keeps them.
    $windowsFolder = $env:WINDIR
    if (-not $windowsFolder) { $windowsFolder = 'C:\Windows' }
    $polFile = Join-Path $windowsFolder 'System32\GroupPolicy\Machine\Registry.pol'
    $gptFile = Join-Path $windowsFolder 'System32\GroupPolicy\gpt.ini'

    try {
        $removed = 0
        if (Test-Path -LiteralPath $polFile -PathType Leaf) {
            $result = Remove-PolEntries -Bytes ([System.IO.File]::ReadAllBytes($polFile)) `
                -Key 'Software\Policies\Microsoft\Windows\DeviceGuard' `
                -KeepValues @('DeployConfigCIPolicy', 'ConfigCIPolicyFilePath')
            $removed = $result.Removed
        }
        if ($removed -eq 0) {
            Write-Host '  OK       Local Group Policy: it has no settings for virtualization-based security'
            return
        }

        $backup = "$polFile.bak"
        if (-not (Test-Path -LiteralPath $backup)) {
            Copy-Item -LiteralPath $polFile -Destination $backup
        }
        [System.IO.File]::WriteAllBytes($polFile, $result.Bytes)
        Write-Host "  OK       Local Group Policy: $removed settings for virtualization-based security removed"

        # This encoding reads and writes each byte without a change.
        $encoding = [System.Text.Encoding]::GetEncoding(28591)
        $updated = $null
        if (Test-Path -LiteralPath $gptFile -PathType Leaf) {
            $updated = Update-GptVersion -Text ([System.IO.File]::ReadAllText($gptFile, $encoding))
        }
        if ($updated) {
            [System.IO.File]::WriteAllText($gptFile, $updated, $encoding)
            Write-Host '  OK       Local Group Policy: new version in gpt.ini'
        } else {
            Write-Host '  SKIPPED  Local Group Policy: gpt.ini has no version'
        }
    } catch {
        Write-Host "  FAILED   Local Group Policy: $($_.Exception.Message)"
    }
}

function Show-VtxPrograms {
    # Some antivirus programs use VT-x or AMD-V for their own protection.
    # Then VMware cannot use it, and nested virtualization does not operate.
    $found = @()
    try {
        $found += @(Get-CimInstance -Namespace 'root\SecurityCenter2' -ClassName AntiVirusProduct -ErrorAction Stop |
            ForEach-Object { "$($_.displayName)" })
    } catch { }
    $processes = @{ 'AvastSvc' = 'Avast'; 'AVGSvc' = 'AVG'; 'avp' = 'Kaspersky' }
    foreach ($process in $processes.Keys) {
        $name = $processes[$process]
        if (-not ($found -match $name) -and (Get-Process -Name $process -ErrorAction SilentlyContinue)) {
            $found += $name
        }
    }
    $found = @($found | Where-Object { $_ } | Sort-Object -Unique)

    $avast = @($found | Where-Object { $_ -match 'Avast|AVG' })
    $kaspersky = @($found | Where-Object { $_ -match 'Kaspersky' })
    $other = @($found | Where-Object { $_ -notmatch 'Avast|AVG|Kaspersky|Defender' })

    Write-Host ''
    if ($avast.Count + $kaspersky.Count + $other.Count -eq 0) {
        Write-Host 'Antivirus: no program found that can use VT-x or AMD-V.'
        return
    }
    Write-Host 'Antivirus: these programs can use VT-x or AMD-V. Then VMware cannot use it.'
    if ($avast.Count -gt 0) {
        Write-Host "  $($avast -join ', '):"
        Write-Host '    Open the settings, then Troubleshooting. Clear "Enable hardware-assisted virtualization".'
    }
    if ($kaspersky.Count -gt 0) {
        Write-Host "  $($kaspersky -join ', '):"
        Write-Host '    Open the settings. Clear "Use hardware virtualization if available".'
    }
    if ($other.Count -gt 0) {
        Write-Host "  $($other -join ', '):"
        Write-Host '    If the program has a setting for hardware virtualization, set it to off.'
    }
    Write-Host '  Then restart the computer (Restart, not Shut down).'
}

function Disable-WindowsHypervisor {
    Write-Host ''
    Write-Host 'Windows: the script now sets the Windows hypervisor to off.'

    # 1. BitLocker stops for one restart, so that the boot changes cause no recovery key question.
    $systemDrive = $env:SystemDrive
    if (-not $systemDrive) { $systemDrive = 'C:' }
    Invoke-Native -Optional -Label 'BitLocker protection stops for one restart (only if BitLocker is on)' `
        -File 'manage-bde.exe' -Arguments @('-protectors', '-disable', $systemDrive, '-RebootCount', '1')

    # 2. Boot settings.
    Invoke-Native -Label 'Boot setting: hypervisorlaunchtype off' `
        -File 'bcdedit.exe' -Arguments @('/set', 'hypervisorlaunchtype', 'off')
    Invoke-Native -Label 'Boot setting: vsmlaunchtype off' `
        -File 'bcdedit.exe' -Arguments @('/set', 'vsmlaunchtype', 'off')

    # 3. Windows features that use the hypervisor.
    #    A feature that is not on this edition of Windows causes an error from Get. The script ignores it.
    $features = @('Microsoft-Hyper-V-All', 'HypervisorPlatform', 'VirtualMachinePlatform',
        'Containers-DisposableClientVM', 'Windows-Defender-ApplicationGuard')
    foreach ($name in $features) {
        $feature = $null
        try { $feature = Get-WindowsOptionalFeature -Online -FeatureName $name -ErrorAction Stop } catch { }
        if ($feature -and "$($feature.State)" -eq 'Enabled') {
            try {
                Disable-WindowsOptionalFeature -Online -FeatureName $name -NoRestart -ErrorAction Stop | Out-Null
                Write-Host "  OK       Windows feature off: $name"
            } catch {
                Write-Host "  FAILED   Windows feature off: $name"
                Write-Host "           $($_.Exception.Message)"
            }
        }
    }

    # 4. Local Group Policy. If it is not removed, it can set virtualization-based security to on again.
    Remove-LocalVbsPolicy

    # 5. Registry values for virtualization-based security and the services that use it.
    $deviceGuard = 'HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard'
    $policy = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard'
    $values = @(
        @($deviceGuard, 'EnableVirtualizationBasedSecurity', '0'),
        @($deviceGuard, 'RequirePlatformSecurityFeatures', '0'),
        @($deviceGuard, 'Locked', '0'),
        @($deviceGuard, 'Mandatory', '0'),
        @("$deviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity", 'Enabled', '0'),
        @("$deviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity", 'Locked', '0'),
        @("$deviceGuard\Scenarios\CredentialGuard", 'Enabled', '0'),
        @("$deviceGuard\Scenarios\SystemGuard", 'Enabled', '0'),
        @("$deviceGuard\Scenarios\KernelShadowStacks", 'Enabled', '0'),
        @("$deviceGuard\Scenarios\SecureBiometrics", 'Enabled', '0'),
        @('HKLM\SYSTEM\CurrentControlSet\Control\Lsa', 'LsaCfgFlags', '0'),
        @($policy, 'EnableVirtualizationBasedSecurity', '0'),
        @($policy, 'LsaCfgFlags', '0'),
        @($policy, 'HypervisorEnforcedCodeIntegrity', '0'),
        @($policy, 'ConfigureSystemGuardLaunch', '2')
    )
    $failed = 0
    foreach ($value in $values) {
        $ErrorActionPreference = 'Continue'
        & reg.exe add $value[0] /v $value[1] /t REG_DWORD /d $value[2] /f 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            $failed++
            Write-Host "  FAILED   Registry: $($value[0]) $($value[1])"
        }
        $ErrorActionPreference = 'Stop'
    }
    if ($failed -eq 0) {
        Write-Host '  OK       Registry: virtualization-based security, Memory Integrity, Credential Guard,'
        Write-Host '           System Guard Secure Launch, Kernel-mode Stack Protection,'
        Write-Host '           Windows Hello Enhanced Sign-in Security: off'
    }

    # 6. UEFI lock. This is the Microsoft procedure with SecConfig.efi.
    #    At the subsequent start, the tool asks to set the functions to off. The F3 key accepts.
    $windowsFolder = $env:WINDIR
    if (-not $windowsFolder) { $windowsFolder = 'C:\Windows' }
    $tool = Join-Path $windowsFolder 'System32\SecConfig.efi'
    $letter = Get-FreeDriveLetter
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) {
        Write-Host '  SKIPPED  UEFI lock: SecConfig.efi is not on this computer.'
    } elseif (-not $letter) {
        Write-Host '  SKIPPED  UEFI lock: no free drive letter.'
    } else {
        Invoke-Native -Label "UEFI lock: connect the EFI system partition as $letter" `
            -File 'mountvol.exe' -Arguments @($letter, '/s')
        if ($script:NativeOk) {
            Invoke-Native -Label 'UEFI lock: copy SecConfig.efi to the EFI system partition' `
                -File 'cmd.exe' -Arguments @('/c', 'copy', '/y', $tool, "$letter\EFI\Microsoft\Boot\SecConfig.efi")
            if ($script:NativeOk) {
                # The entry can be there from an earlier run. Thus this step is optional.
                Invoke-Native -Optional -Label 'UEFI lock: make the boot entry (not necessary if it is there)' `
                    -File 'bcdedit.exe' -Arguments @('/create', $UefiToolId, '/d', 'DebugTool', '/application', 'osloader')
                Invoke-Native -Label 'UEFI lock: set the path of the tool' `
                    -File 'bcdedit.exe' -Arguments @('/set', $UefiToolId, 'path', '\EFI\Microsoft\Boot\SecConfig.efi')
                $pathOk = $script:NativeOk
                Invoke-Native -Label 'UEFI lock: set the options DISABLE-LSA-ISO,DISABLE-VBS' `
                    -File 'bcdedit.exe' -Arguments @('/set', $UefiToolId, 'loadoptions', 'DISABLE-LSA-ISO,DISABLE-VBS')
                $optionsOk = $script:NativeOk
                Invoke-Native -Label 'UEFI lock: set the partition of the tool' `
                    -File 'bcdedit.exe' -Arguments @('/set', $UefiToolId, 'device', "partition=$letter")
                $deviceOk = $script:NativeOk
                if ($pathOk -and $optionsOk -and $deviceOk) {
                    # The tool runs one time only, at the subsequent start.
                    Invoke-Native -Label 'UEFI lock: run the tool one time at the subsequent start' `
                        -File 'bcdedit.exe' -Arguments @('/set', '{bootmgr}', 'bootsequence', $UefiToolId)
                    $script:UefiToolReady = $script:NativeOk
                } else {
                    Write-Host '  SKIPPED  UEFI lock: the tool does not run, because a step before it failed.'
                }
            }
            Invoke-Native -Label "UEFI lock: disconnect $letter" -File 'mountvol.exe' -Arguments @($letter, '/d')
        }
    }

    # 7. Show the boot settings.
    Invoke-Native -Optional -Label 'Read the boot settings' -File 'bcdedit.exe' -Arguments @('/enum', '{current}')
    foreach ($line in ($script:NativeOutput -split "`r?`n")) {
        if ($line -match 'hypervisorlaunchtype|vsmlaunchtype') { Write-Host "           $($line.Trim())" }
    }
}

function Get-MarkerPath {
    if ($env:ProgramData) { return (Join-Path $env:ProgramData 'fix-vmware-host.txt') }
    return $null
}

function Get-MarkerLevel {
    # 0 = no Windows changes were made. 1 and 2 = older versions of the changes. 3 = this version.
    $marker = Get-MarkerPath
    if (-not $marker -or -not (Test-Path -LiteralPath $marker)) { return 0 }
    try {
        $text = [System.IO.File]::ReadAllText($marker)
        $match = [regex]::Match($text, '^level=(\d+)')
        if ($match.Success) { return [int]$match.Groups[1].Value }
    } catch { }
    return 1
}

function Request-Restart {
    Write-Host ''
    Write-Host 'A restart is necessary. Use Restart, not Shut down.'
    if ($script:UefiToolReady) {
        Write-Host 'IMPORTANT: during the start, a black screen asks about Credential Guard and'
        Write-Host 'virtualization-based security. Press F3 for each question.'
    }
    Write-Host 'After the restart, run this script again. It then sets nested virtualization to on.'
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

function Invoke-HostPart {
    $marker = Get-MarkerPath
    $level = Get-MarkerLevel

    Write-Host ''
    if (-not (Test-WindowsHypervisor)) {
        Write-Host 'Windows: the Windows hypervisor is off. No change is necessary.'
        return
    }

    # If this version of the changes is already applied, find out if a restart occurred after them.
    if ($level -ge $HostLevel -and -not $Force) {
        $applied = (Get-Item -LiteralPath $marker).LastWriteTime
        $boot = $null
        try { $boot = (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime } catch { }
        if ($boot -and $boot -gt $applied) {
            Write-Host 'Windows: the Windows hypervisor stays on after all the changes and a restart.'
            Show-VbsStatus
            Write-Host '  Possible causes:'
            Write-Host '  - You did not press F3 on the black screen during the start.'
            Write-Host '  - You used Shut down and not Restart.'
            Write-Host '  - A policy of an organization applies the settings again.'
            Write-Host '  - A security setting in the BIOS or UEFI keeps the hypervisor on.'
            Write-Host '  To apply the Windows changes again, run:'
            Write-Host '    powershell -ExecutionPolicy Bypass -File .\fix-vmware.ps1 -Force'
            return
        }
        Write-Host 'Windows: the changes are applied, but the computer did not restart.'
        $script:UefiToolReady = $true
        Request-Restart
        return
    }

    if (-not (Test-Admin)) {
        Write-Host 'Windows: the Windows hypervisor is on. Administrator rights are necessary to set it to off.'
        Write-Host '  A second window opens. Select Yes in the User Account Control window.'
        $arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '" -HostOnly'
        if ($Force) { $arguments += ' -Force' }
        try {
            Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $arguments -Wait
        } catch {
            Write-Host '  Administrator rights were not given. Windows has no change.'
            Write-Host '  Nested virtualization stays off.'
        }
        return
    }

    if ($level -gt 0 -and $level -lt $HostLevel) {
        Write-Host 'Windows: an older version of this script made a smaller set of changes.'
        Write-Host '  The script now makes the full set of changes.'
    }
    Show-VbsStatus
    Disable-WindowsHypervisor
    if ($marker) {
        try {
            Set-Content -LiteralPath $marker -Value ("level=$HostLevel date=" + (Get-Date).ToString('o'))
        } catch { }
    }
    Request-Restart
}

# ---------------------------------------------------------------------------
# Main part
# ---------------------------------------------------------------------------

$script:NativeOk = $false
$script:NativeOutput = ''
$script:UefiToolReady = $false

# A 32-bit PowerShell on a 64-bit Windows cannot use bcdedit.exe and cannot change the Windows features.
# The script then starts again in the 64-bit PowerShell.
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
    if ($VmxPath) { $arguments += @('-VmxPath', $VmxPath) }
    if ($VmOnly) { $arguments += '-VmOnly' }
    if ($HostOnly) { $arguments += '-HostOnly' }
    if ($Force) { $arguments += '-Force' }
    if ($NoNested) { $arguments += '-NoNested' }
    & (Join-Path $env:WINDIR 'Sysnative\WindowsPowerShell\v1.0\powershell.exe') @arguments
    exit $LASTEXITCODE
}

Write-Host 'fix-vmware.ps1'

# Part A: the virtual machine.
if (-not $HostOnly) {
    $hypervisor = Test-WindowsHypervisor
    $nested = 'FALSE'
    if ($NoNested) {
        Write-Host 'Option -NoNested: the virtual machine gets nested virtualization: off. Windows has no change.'
    } elseif ($hypervisor) {
        Write-Host 'The Windows hypervisor is on. Nested virtualization is not available at this time.'
        Write-Host 'The virtual machine gets nested virtualization: off, so that it can start.'
    } elseif (Test-FirmwareVirtualization) {
        $nested = 'TRUE'
        Write-Host 'The Windows hypervisor is off. Nested virtualization is available.'
        Write-Host 'The virtual machine gets nested virtualization: on.'
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
        Write-Host '  powershell -ExecutionPolicy Bypass -File .\fix-vmware.ps1 -VmxPath "C:\path\to\PNET.vmx"'
    } else {
        $good = 0
        foreach ($target in $targets) {
            if (Update-VmxFile -Path $target -Nested $nested) { $good++ }
        }
        Write-Host ''
        Write-Host "Virtual machines corrected: $good of $($targets.Count)"
    }
}

# Part C: antivirus programs. This part comes before part B, because part B can restart the computer.
if (-not $HostOnly) {
    Show-VtxPrograms
}

# Part B: Windows.
if (-not $VmOnly -and -not $NoNested) {
    Invoke-HostPart
}

Write-Host ''
Write-Host 'The script is complete.'
if ($HostOnly) {
    [void](Read-Host 'Press Enter to close this window')
}
