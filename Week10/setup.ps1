# Week 10: two Cisco 7200 routers on the LAN of your computer (Windows).
#
#   irm https://raw.githubusercontent.com/sojoudian/COMP2155_Fall_2026/master/Week10/setup.ps1 | iex
#
# 1. It starts an Administrator PowerShell if this one is not (Npcap and
#    the host path need it).
# 2. It installs Npcap (https://npcap.com) if it is not installed: the
#    Npcap installer opens. Click "I Agree", "Install" and "Finish".
# 3. It installs tessera (https://tessera.rest/install.ps1).
# 4. It writes the lab to %USERPROFILE%\tessera-week10: wk10.yaml, R1.cfg and
#    R2.cfg. A config that is there already does not change.
# 5. It starts R1 and R2 with "tessera lab up wk10.yaml --lan". Each router
#    gets a free address of your LAN on FastEthernet0/0.
#
# Stop the routers (PowerShell as Administrator):
#   tessera lab down $HOME\tessera-week10\wk10.yaml
#
# All the work is in one function: an error stops it with "throw" (not
# "exit", which closes the window), and a cut download does not run half a
# script.

function Start-Week10 {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'
    $self = 'https://raw.githubusercontent.com/sojoudian/COMP2155_Fall_2026/master/Week10/setup.ps1'
    $npcapUrl = 'https://npcap.com/dist/npcap-1.90.exe'
    # The SHA-256 of npcap-1.90.exe and its signer (Nmap Software LLC).
    $npcapSha256 = '682B57E1C05EF375931975C9D6DED40888F4BFDF9F4B11571E654F962F1199B6'
    $npcapSigner = 'O=Nmap Software LLC'
    $labDir = Join-Path $HOME 'tessera-week10'

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
    }

    Write-Host ''
    Write-Host '== 2. Install tessera'
    Invoke-RestMethod -Uri 'https://tessera.rest/install.ps1' -UseBasicParsing | Invoke-Expression
    $dir = if ($env:TESSERA_INSTALL_DIR) { $env:TESSERA_INSTALL_DIR } else { Join-Path $env:LOCALAPPDATA 'tessera\bin' }
    $tessera = Join-Path $dir 'tessera.exe'
    if (-not (Test-Path $tessera)) { throw 'tessera is not installed. See the error above.' }

    Write-Host ''
    Write-Host "== 3. Write the lab to $labDir"
    New-Item -ItemType Directory -Path $labDir -Force | Out-Null
    $utf8 = New-Object Text.UTF8Encoding $false
    $yaml = @'
# Week 10: two Cisco 7200 routers (NPE-400, 15.2(4)S6) on one switch.
# With --lan, the switch is on the LAN of this computer, and each router gets
# a free LAN address on FastEthernet0/0.
# User: admin / cisco123 (privilege 15).
name: week10
platform: c7200
routers:
  - name: R1
    node-id: 1
    config: R1.cfg
    ssh-port: 22610
    telnet-port: -1
  - name: R2
    node-id: 2
    config: R2.cfg
    ssh-port: 22620
    telnet-port: -1
switches:
  - name: SW1
links:
  - [R1:FastEthernet0/0, SW1]
  - [R2:FastEthernet0/0, SW1]
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
 transport input ssh
!
ntp server 34.208.249.133
ntp server pool.ntp.org
!
end
'@
    [IO.File]::WriteAllText((Join-Path $labDir 'wk10.yaml'), ($yaml -replace "`r", '') + "`n", $utf8)
    foreach ($r in @(
            @{ Name = 'R1'; Secret = '$1$vwf3$VU/7dT4bv5xV09cCsY2QY.'; IP = '10.1.1.10' },
            @{ Name = 'R2'; Secret = '$1$kzaF$yOPk/X/AWa6/iH1p02OB/0'; IP = '10.1.1.20' })) {
        $file = Join-Path $labDir ($r.Name + '.cfg')
        if (-not (Test-Path $file)) {
            $cfg = $template.Replace('@HOST@', $r.Name).Replace('@SECRET@', $r.Secret).Replace('@IP@', $r.IP) -replace "`r", ''
            [IO.File]::WriteAllText($file, $cfg, $utf8)
        }
    }

    Push-Location $labDir
    try {
        # PowerShell 5.1 stops on a redirected stderr line when the
        # preference is Stop.
        $ErrorActionPreference = 'Continue'
        & $tessera lab status wk10.yaml *> $null
        $running = $LASTEXITCODE -eq 0
        $ErrorActionPreference = 'Stop'
        if ($running) {
            Write-Host 'The lab runs. Stop it first.'
            & $tessera lab down wk10.yaml
        }
        Write-Host ''
        Write-Host '== 4. Start R1 and R2 on your LAN'
        & $tessera lab up wk10.yaml --lan
        if ($LASTEXITCODE -ne 0) { throw 'tessera lab up failed. See the error above.' }
    } finally {
        Pop-Location
    }

    Write-Host ''
    Write-Host 'Connect:  ssh -o KexAlgorithms=+diffie-hellman-group14-sha1 -o HostKeyAlgorithms=+ssh-rsa -o Ciphers=+aes128-cbc admin@ADDRESS'
    Write-Host 'Password: cisco123. ADDRESS is in the table above.'
    Write-Host "Stop:     tessera lab down $labDir\wk10.yaml   (PowerShell as Administrator)"
    Write-Host ''
}

try {
    Start-Week10
} catch {
    Write-Host 'error: ' -NoNewline -ForegroundColor Red
    Write-Host $_.Exception.Message
} finally {
    Remove-Item Function:\Start-Week10 -ErrorAction SilentlyContinue
}
