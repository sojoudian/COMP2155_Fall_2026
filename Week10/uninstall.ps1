# Week 10: remove all that setup.ps1 did (Windows).
#
#   irm https://raw.githubusercontent.com/sojoudian/COMP2155_Fall_2026/master/Week10/uninstall.ps1 | iex
#
# 1. It starts an Administrator PowerShell if this one is not.
# 2. It stops R1 and R2 ("tessera lab down"). It also stops the tessera
#    processes of the lab that still run (for example after the lab folder
#    was deleted).
# 3. It removes the lab folder %USERPROFILE%\tessera-week10, with your saved
#    configs.
# 4. It removes what the path from this computer to the routers added: the
#    "Tessera Tunnel" adapter devices, the "Tessera <address>" network profiles,
#    %ProgramFiles%\Tessera (wintun.dll) and the Wintun driver (only when no
#    adapter uses it).
# 5. It removes the Windows Firewall rules of tessera.exe, and tessera
#    (https://tessera.rest/install.ps1 with TESSERA_UNINSTALL=1).
# 6. It removes Npcap if setup.ps1 installed it. If Npcap was on this
#    computer before, it asks first: Wireshark and Nmap use Npcap too.
#    $env:TESSERA_NPCAP = 'remove' or 'keep' gives the answer before.
#
# All the work is in one function: an error stops it with "throw" (not
# "exit", which closes the window), and a cut download does not run half a
# script.

function Remove-Week10 {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'
    $self = 'https://raw.githubusercontent.com/sojoudian/COMP2155_Fall_2026/master/Week10/uninstall.ps1'
    $labDir = Join-Path $HOME 'tessera-week10'
    $tunName = '^Tessera \d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$'  # the network profile names of the host path

    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host 'Starting PowerShell as Administrator. Click "Yes".'
        Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-NoExit', '-Command', "irm $self | iex"
        return
    }
    if (-not $HOME -or -not (Split-Path $labDir -Parent)) { throw "HOME is ""$HOME"": the lab folder is not clear." }

    $dir = if ($env:TESSERA_INSTALL_DIR) { $env:TESSERA_INSTALL_DIR } else { Join-Path $env:LOCALAPPDATA 'tessera\bin' }
    $tessera = Join-Path $dir 'tessera.exe'
    $npcapBySetup = Test-Path (Join-Path $labDir '.npcap-by-setup')

    Write-Host ''
    Write-Host '== 1. Stop R1 and R2'
    if ((Test-Path $tessera) -and (Test-Path (Join-Path $labDir 'wk10.yaml'))) {
        Push-Location $labDir
        try {
            # PowerShell 5.1 stops on a redirected stderr line when the
            # preference is Stop.
            $ErrorActionPreference = 'Continue'
            & $tessera lab status wk10.yaml *> $null
            $running = $LASTEXITCODE -eq 0
            if ($running) { & $tessera lab down wk10.yaml } else { Write-Host 'The lab does not run.' }
            $ErrorActionPreference = 'Stop'
        } finally {
            Pop-Location
        }
    }
    $left = @(Get-CimInstance Win32_Process | Where-Object {
            $_.Name -like 'tessera*.exe' -and $_.CommandLine -and
            $_.CommandLine.IndexOf("$labDir\", [StringComparison]::OrdinalIgnoreCase) -ge 0 })
    if ($left.Count -gt 0) {
        Write-Host "Stopping the lab processes that still run: $(($left | ForEach-Object { $_.ProcessId }) -join ', ')"
        $left | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        $left | ForEach-Object { Wait-Process -Id $_.ProcessId -Timeout 10 -ErrorAction SilentlyContinue }
    }

    Write-Host ''
    Write-Host '== 2. Remove the lab folder'
    if (Test-Path $labDir) {
        Remove-Item $labDir -Recurse -Force
        Write-Host "Removed $labDir."
    } else {
        Write-Host "There is no $labDir."
    }

    Write-Host ''
    Write-Host '== 3. Remove the host path (Wintun)'
    # An adapter goes when its process stops. A process that is killed (a
    # crash, Stop-Process) leaves a device "Tessera Tunnel" that is not
    # present, and that device holds the Wintun driver.
    Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -like 'SWD\WINTUN\*' -and $_.FriendlyName -eq 'Tessera Tunnel' } | ForEach-Object {
        $ErrorActionPreference = 'Continue'
        & pnputil.exe /remove-device $_.InstanceId *> $null
        $ok = $LASTEXITCODE -eq 0
        $ErrorActionPreference = 'Stop'
        if ($ok) { Write-Host "Removed the adapter device $($_.InstanceId)." } else { Write-Host "Cannot remove the adapter device $($_.InstanceId)." }
    }
    $list = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\NetworkList'
    Get-ChildItem "$list\Signatures\Unmanaged", "$list\Signatures\Managed" -ErrorAction SilentlyContinue | Where-Object {
        (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).Description -match $tunName } | Remove-Item -Recurse -Force
    Get-ChildItem "$list\Profiles" -ErrorAction SilentlyContinue | ForEach-Object {
        $name = (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).ProfileName
        if ($name -match $tunName) {
            Remove-Item $_.PSPath -Recurse -Force
            Write-Host "Removed the network profile $name."
        }
    }
    $pf = Join-Path $env:ProgramFiles 'Tessera'
    if (Test-Path $pf) {
        Remove-Item $pf -Recurse -Force
        Write-Host "Removed $pf."
    }
    # The Wintun driver: pnputil does not delete it while an adapter uses it
    # (another VPN program). That program installs it again when it needs it.
    foreach ($inf in @(Select-String -Path (Join-Path $env:SystemRoot 'INF\oem*.inf') -Pattern 'wintun\.sys' -List -ErrorAction SilentlyContinue)) {
        $ErrorActionPreference = 'Continue'
        $out = & pnputil.exe /delete-driver $inf.Filename 2>&1
        $ok = $LASTEXITCODE -eq 0
        $ErrorActionPreference = 'Stop'
        if ($ok) { Write-Host "Removed the Wintun driver ($($inf.Filename))." } else { Write-Host "The Wintun driver stays: another adapter uses it ($($inf.Filename))." }
    }

    Write-Host ''
    Write-Host '== 4. Remove tessera'
    $exes = @($tessera, "$tessera.old")
    Get-NetFirewallApplicationFilter -ErrorAction SilentlyContinue | Where-Object { $exes -contains $_.Program } | ForEach-Object {
        $rule = $_ | Get-NetFirewallRule
        $rule | Remove-NetFirewallRule
        Write-Host "Removed the firewall rule ""$($rule.DisplayName)""."
    }
    $env:TESSERA_UNINSTALL = '1'
    try {
        Invoke-RestMethod -Uri 'https://tessera.rest/install.ps1' -UseBasicParsing | Invoke-Expression
    } finally {
        Remove-Item Env:\TESSERA_UNINSTALL -ErrorAction SilentlyContinue
    }
    $top = Split-Path $dir -Parent
    if (-not $env:TESSERA_INSTALL_DIR -and (Test-Path $top) -and -not (Get-ChildItem $top -Force)) { Remove-Item $top -Force }

    Write-Host ''
    Write-Host '== 5. Npcap'
    $wpcap = Join-Path $env:SystemRoot 'System32\Npcap\wpcap.dll'
    $uninstaller = Join-Path $env:ProgramFiles 'Npcap\Uninstall.exe'
    if (-not (Test-Path $wpcap)) {
        Write-Host 'Npcap is not installed.'
    } else {
        $remove = $npcapBySetup
        if ($env:TESSERA_NPCAP -eq 'remove') { $remove = $true }
        if ($env:TESSERA_NPCAP -eq 'keep') { $remove = $false }
        if (-not $npcapBySetup -and -not $env:TESSERA_NPCAP) {
            Write-Host 'Npcap was on this computer before setup.ps1, or setup.ps1 has no record of it.'
            Write-Host 'Wireshark and Nmap use Npcap too.'
            $remove = (Read-Host 'Remove Npcap? [y/N]') -match '^(y|yes)$'
        }
        if (-not $remove) {
            Write-Host 'Npcap stays.'
        } elseif (-not (Test-Path $uninstaller)) {
            Write-Host "There is no $uninstaller. Remove Npcap in Settings > Apps."
        } else {
            Write-Host 'Removing Npcap (close Wireshark first).'
            # /S: silent (all Npcap editions). /no_kill=yes: stop with an error
            # if a program uses Npcap; do not stop that program.
            Start-Process -FilePath $uninstaller -ArgumentList '/S', '/no_kill=yes' -Wait
            # The uninstaller runs a copy of itself: wait for the files to go.
            for ($i = 0; $i -lt 60 -and (Test-Path $wpcap); $i++) { Start-Sleep -Seconds 1 }
            if (Test-Path $wpcap) {
                Write-Host 'Npcap is still installed: a program uses it. Close it, and remove Npcap in Settings > Apps.'
            } else {
                Write-Host 'Removed Npcap.'
            }
        }
    }

    Write-Host ''
    Write-Host 'Week 10 is removed from this computer.'
    Write-Host ''
}

try {
    Remove-Week10
} catch {
    Write-Host 'error: ' -NoNewline -ForegroundColor Red
    Write-Host $_.Exception.Message
} finally {
    Remove-Item Function:\Remove-Week10 -ErrorAction SilentlyContinue
}
