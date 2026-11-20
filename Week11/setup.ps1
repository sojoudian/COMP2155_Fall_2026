# Week 11: three Cisco routers on the LAN of your computer (Windows).
#
#   irm https://raw.githubusercontent.com/sojoudian/COMP2155_Fall_2026/master/Week11/setup.ps1 | iex
#
# 1. It starts an Administrator PowerShell if this one is not (Npcap and
#    the host path need it).
# 2. It installs Npcap (https://npcap.com) if it is not installed: the
#    Npcap installer opens. Click "I Agree", "Install" and "Finish".
# 3. It installs tessera (https://tessera.rest/install.ps1).
# 4. It writes the lab to %USERPROFILE%\.tessera\week11: week11.yaml, R1.cfg,
#    R2.cfg and R3.cfg. A config that is there already does not change.
# 5. It starts R1, R2 and R3 with "tessera lab up week11.yaml --lan". Each router
#    gets a free address of your LAN: FastEthernet0/0 on R1 and R2 (Cisco
#    7200), Ethernet0/0 on R3 (Cisco IOL).
#
# Stop the routers (PowerShell as Administrator):
#   tessera lab down $HOME\.tessera\week11\week11.yaml
#
# Remove all of it: uninstall.ps1 in the same folder.
#
# All the work is in one function: an error stops it with "throw" (not
# "exit", which closes the window), and a cut download does not run half a
# script.

function Start-Week11 {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'
    $self = 'https://raw.githubusercontent.com/sojoudian/COMP2155_Fall_2026/master/Week11/setup.ps1'
    $npcapUrl = 'https://npcap.com/dist/npcap-1.90.exe'
    # The SHA-256 of npcap-1.90.exe and its signer (Nmap Software LLC).
    $npcapSha256 = '682B57E1C05EF375931975C9D6DED40888F4BFDF9F4B11571E654F962F1199B6'
    $npcapSigner = 'O=Nmap Software LLC'
    $labDir = Join-Path (Join-Path $HOME '.tessera') 'week11'

    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host 'Starting PowerShell as Administrator. Click "Yes".'
        Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-NoExit', '-Command', "irm $self | iex"
        return
    }

    Write-Host ''
    Write-Host '== 1. Npcap'
    $wpcap = Join-Path $env:SystemRoot 'System32\Npcap\wpcap.dll'
    if (Test-Path $wpcap) {
        Write-Host 'Npcap is installed.'
    } else {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $setup = Join-Path ([IO.Path]::GetTempPath()) ('npcap-setup-' + [Guid]::NewGuid().ToString('N') + '.exe')
        $manual = 'Install Npcap from https://npcap.com/#download (the default options), then run this script again.'
        Write-Host "Downloading $npcapUrl"
        try {
            Invoke-WebRequest -Uri $npcapUrl -OutFile $setup -UseBasicParsing
        } catch {
            Remove-Item $setup -Force -ErrorAction SilentlyContinue
            throw "Cannot download Npcap: $($_.Exception.Message). $manual"
        }
        $hash = (Get-FileHash -Path $setup -Algorithm SHA256).Hash
        if ($hash -ne $npcapSha256) {
            Remove-Item $setup -Force
            throw "The Npcap installer is not the correct file (SHA-256 $hash). $manual"
        }
        $sig = Get-AuthenticodeSignature -FilePath $setup
        $signer = if ($sig.SignerCertificate) { $sig.SignerCertificate.Subject } else { 'none' }
        if ($sig.Status -ne 'Valid' -or -not $signer.Contains($npcapSigner)) {
            Remove-Item $setup -Force
            throw "The signature of the Npcap installer is not correct (status $($sig.Status), signer $signer). $manual"
        }
        Write-Host 'The SHA-256 and the signature (Nmap Software LLC) are correct.'
        Write-Host 'The Npcap installer opens. Click "I Agree", "Install" and "Finish".'
        Start-Process -FilePath $setup -Wait
        Remove-Item $setup -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path $wpcap)) { throw 'Npcap is not installed. Run this script again.' }
        Write-Host 'Npcap is installed.'
        # uninstall.ps1 removes Npcap with no question when this file is there.
        New-Item -ItemType Directory -Path $labDir -Force | Out-Null
        Set-Content -Path (Join-Path $labDir '.npcap-by-setup') -Value $npcapUrl
    }

    Write-Host ''
    Write-Host '== 2. Install tessera'
    $dir = if ($env:TESSERA_INSTALL_DIR) { $env:TESSERA_INSTALL_DIR } else { Join-Path $env:LOCALAPPDATA 'tessera\bin' }
    $tessera = Join-Path $dir 'tessera.exe'
    # A lab that an older tessera started runs from tessera.exe.old. The
    # installer cannot replace that file, so stop those processes first.
    $oldRun = @(Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -eq "$tessera.old" })
    if ($oldRun.Count -gt 0) {
        Write-Host "Stopping the lab of an older tessera: $(($oldRun | ForEach-Object { $_.ProcessId }) -join ', ')"
        $oldRun | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        $oldRun | ForEach-Object { Wait-Process -Id $_.ProcessId -Timeout 10 -ErrorAction SilentlyContinue }
    }
    Invoke-RestMethod -Uri 'https://tessera.rest/install.ps1' -UseBasicParsing | Invoke-Expression
    if (-not (Test-Path $tessera)) { throw 'tessera is not installed. See the error above.' }

    Write-Host ''
    Write-Host "== 3. Write the lab to $labDir"
    New-Item -ItemType Directory -Path $labDir -Force | Out-Null
    $utf8 = New-Object Text.UTF8Encoding $false
    $yaml = @'
# Week 11: two Cisco 7200 routers (NPE-400, 15.2(4)S6) and one Cisco IOL
# router (15.7(3)M2) on one switch.
# With --lan, the switch is on the LAN of this computer, and each router gets
# a free LAN address: FastEthernet0/0 on R1 and R2, Ethernet0/0 on R3.
# User: admin / cisco123 (privilege 15). SSH and telnet are on.
name: week11
routers:
  - name: R1
    platform: c7200
    node-id: 1
    config: R1.cfg
    ssh-port: 22710
    telnet-port: 23710
  - name: R2
    platform: c7200
    node-id: 2
    config: R2.cfg
    ssh-port: 22720
    telnet-port: 23720
  - name: R3
    platform: iol
    node-id: 3
    config: R3.cfg
    ssh-port: 22730
    telnet-port: 23730
switches:
  - name: SW1
links:
  - [R1:FastEthernet0/0, SW1]
  - [R2:FastEthernet0/0, SW1]
  - [R3:Ethernet0/0, SW1]
'@
    # The startup config of a 7206VXR (15.2(4)S6). The lab gives
    # FastEthernet0/0 a free LAN address after the start.
    $template = @'
!
version 15.2
service timestamps debug datetime msec
service timestamps log datetime msec
!
hostname @HOST@
!
boot-start-marker
boot-end-marker
!
!
enable secret 5 @SECRET@
!
no aaa new-model
!
!
!
!
!
!
no ip domain lookup
ip domain name lab.local
ip cef
no ipv6 cef
!
!
multilink bundle-name authenticated
!
!
!
!
!
!
!
username admin privilege 15 secret 5 $1$RyKC$JYsD/nugZHXiYAPU/UUzH/
!
!
!
!
!
ip ssh version 2
ip scp server enable
! 
!
!
!
!
!
!
!
!
interface FastEthernet0/0
 ip address @IP@ 255.255.255.0
 duplex full
!
interface FastEthernet1/0
 no ip address
 shutdown
 duplex full
!
interface FastEthernet2/0
 no ip address
 shutdown
 duplex full
!
interface FastEthernet3/0
 no ip address
 shutdown
 duplex full
!
ip forward-protocol nd
!
!
no ip http server
no ip http secure-server
!
!
!
!
control-plane
!
!
line con 0
 logging synchronous
 stopbits 1
line aux 0
 stopbits 1
line vty 0 4
 login local
 transport input telnet ssh
!
ntp server 34.208.249.133
ntp server pool.ntp.org
!
end
'@
    # The startup config of an IOL router (15.7(3)M2). The lab gives
    # Ethernet0/0 a free LAN address after the start.
    $templateIOL = @'
!
version 15.7
service timestamps debug datetime msec
service timestamps log datetime msec
no service password-encryption
!
hostname @HOST@
!
boot-start-marker
boot-end-marker
!
!
enable secret 5 @SECRET@
!
no aaa new-model
!
!
!
mmi polling-interval 60
no mmi auto-configure
no mmi pvc
mmi snmp-timeout 180
!
!
!
!
!
!
!
!
!
!
!
!
!
!
!


!
!
!
!
no ip domain lookup
ip domain name lab.local
ip cef
no ipv6 cef
!
multilink bundle-name authenticated
!
!
!
!
!
!
!
!
!
username admin privilege 15 secret 5 $1$RyKC$JYsD/nugZHXiYAPU/UUzH/
!
redundancy
!
!
! 
!
!
!
!
!
!
!
!
!
!
!
!
interface Ethernet0/0
 ip address @IP@ 255.255.255.0
 duplex auto
!
interface Ethernet0/1
 no ip address
 shutdown
 duplex auto
!
interface Ethernet0/2
 no ip address
 shutdown
 duplex auto
!
interface Ethernet0/3
 no ip address
 shutdown
 duplex auto
!
ip forward-protocol nd
!
!
no ip http server
no ip http secure-server
ip ssh version 2
ip scp server enable
!
ipv6 ioam timestamp
!
!
!
control-plane
!
!
!
!
!
!
!
!
line con 0
 logging synchronous
line aux 0
line vty 0 4
 login local
 transport input telnet ssh
!
ntp server 34.208.249.133
ntp server pool.ntp.org
!
end
'@
    [IO.File]::WriteAllText((Join-Path $labDir 'week11.yaml'), ($yaml -replace "`r", '') + "`n", $utf8)
    # "lan: internet" gives the routers a default route and name servers
    # ("ping google.com"). It is not in tessera 0.0.7 and older.
    $ErrorActionPreference = 'Continue'
    $flags = (& $tessera -h 2>&1 | Out-String)
    $ErrorActionPreference = 'Stop'
    if ($flags -match '-lan-internet') {
        [IO.File]::AppendAllText((Join-Path $labDir 'week11.yaml'), "lan:`n  internet: true`n", $utf8)
    }
    foreach ($r in @(
            @{ Name = 'R1'; Secret = '$1$vwf3$VU/7dT4bv5xV09cCsY2QY.'; IP = '10.1.1.10'; Template = $template },
            @{ Name = 'R2'; Secret = '$1$kzaF$yOPk/X/AWa6/iH1p02OB/0'; IP = '10.1.1.20'; Template = $template },
            @{ Name = 'R3'; Secret = '$1$g8kd$I2Z8fh158yBUJAAAoL9dl/'; IP = '10.1.1.30'; Template = $templateIOL })) {
        $file = Join-Path $labDir ($r.Name + '.cfg')
        if (-not (Test-Path $file)) {
            $cfg = $r.Template.Replace('@HOST@', $r.Name).Replace('@SECRET@', $r.Secret).Replace('@IP@', $r.IP) -replace "`r", ''
            [IO.File]::WriteAllText($file, $cfg, $utf8)
        }
    }

    $r1 = 'ADDRESS'
    $r3 = 'ADDRESS'
    Push-Location $labDir
    try {
        # PowerShell 5.1 stops on a redirected stderr line when the
        # preference is Stop.
        $ErrorActionPreference = 'Continue'
        & $tessera lab status week11.yaml *> $null
        $running = $LASTEXITCODE -eq 0
        $ErrorActionPreference = 'Stop'
        if ($running) {
            Write-Host 'The lab runs. Stop it first.'
            & $tessera lab down week11.yaml
        }
        Write-Host ''
        Write-Host '== 4. Start R1, R2 and R3 on your LAN'
        # --quiet (only the router table) is not in tessera 0.0.6 and older.
        $ErrorActionPreference = 'Continue'
        $help = (& $tessera lab help up 2>&1 | Out-String)
        $ErrorActionPreference = 'Stop'
        if ($help -match '--quiet') {
            & $tessera lab up week11.yaml --lan --quiet
        } else {
            & $tessera lab up week11.yaml --lan
        }
        if ($LASTEXITCODE -ne 0) { throw 'tessera lab up failed. See the error above.' }
        # The addresses of R1 and R3 for the lines below: the address table
        # of "tessera lab status".
        $ErrorActionPreference = 'Continue'
        $status = @(& $tessera lab status week11.yaml 2>$null)
        $ErrorActionPreference = 'Stop'
        foreach ($line in $status) {
            $f = @("$line" -split '\s+' | Where-Object { $_ })
            if ($f.Count -lt 2) { continue }
            $ip = @($f | Select-Object -Skip 1 | Where-Object { $_ -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$' })
            if ($ip.Count -eq 0) { continue }
            if ($f[0] -eq 'R1') { $r1 = $ip[0] }
            if ($f[0] -eq 'R3') { $r3 = $ip[0] }
        }
    } finally {
        Pop-Location
    }

    Write-Host ''
    Write-Host "Connect:  ssh -o KexAlgorithms=+diffie-hellman-group14-sha1 -o HostKeyAlgorithms=+ssh-rsa -o Ciphers=+aes128-cbc -o MACs=+hmac-sha1 admin@$r1"
    Write-Host ''
    Write-Host "R3 (IOL): ssh admin@$r3"
    Write-Host "Telnet:   telnet $r1"
    if ($r1 -eq 'ADDRESS') {
        Write-Host 'User: admin. Password: cisco123. ADDRESS is in the table above.'
    } else {
        Write-Host 'User: admin. Password: cisco123.'
    }
    Write-Host "Stop:     tessera lab down $labDir\week11.yaml   (PowerShell as Administrator)"
    Write-Host ''
}

try {
    Start-Week11
} catch {
    Write-Host 'error: ' -NoNewline -ForegroundColor Red
    Write-Host $_.Exception.Message
} finally {
    Remove-Item Function:\Start-Week11 -ErrorAction SilentlyContinue
}
