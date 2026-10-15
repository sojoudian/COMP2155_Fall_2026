#Requires -RunAsAdministrator
# Enables Remote Desktop on Windows 11 Pro/Enterprise/Education and creates
# (or resets) the local account comp2155a for RDP login.
# Run:  powershell.exe -ExecutionPolicy Bypass -File .\enable-rdp.ps1
# Add -Admin to also put the account in the local Administrators group.

param(
    [string]$UserName = 'comp2155a',
    [string]$Password = 'comp2155a',
    [switch]$Admin
)

$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSEdition -eq 'Core') {
    Import-Module Microsoft.PowerShell.LocalAccounts -UseWindowsPowerShell -WarningAction SilentlyContinue
}

# 1. Edition check. Windows Home ("Core") has no RDP server.
$edition = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID
if ($edition -like 'Core*') {
    throw "This is Windows Home ($edition). Home has no RDP server. Upgrade to Pro first."
}
Write-Host "[1/6] Edition: $edition" -ForegroundColor Cyan

# 2. Turn RDP on, keep Network Level Authentication on.
$ts  = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
$tcp = "$ts\WinStations\RDP-Tcp"
Set-ItemProperty -Path $ts  -Name fDenyTSConnections -Value 0 -Type DWord
Set-ItemProperty -Path $tcp -Name UserAuthentication -Value 1 -Type DWord
$port = (Get-ItemProperty -Path $tcp -Name PortNumber).PortNumber
Write-Host "[2/6] RDP enabled, NLA on, port $port" -ForegroundColor Cyan

# 3. Firewall. The group is named by its resource id, so it works in every language.
Enable-NetFirewallRule -Group '@FirewallAPI.dll,-28752'
Write-Host "[3/6] Firewall rules 'Remote Desktop' enabled (all profiles)" -ForegroundColor Cyan

# 4. Service.
Set-Service -Name TermService -StartupType Manual
Start-Service -Name TermService
Write-Host "[4/6] TermService: $((Get-Service TermService).Status)" -ForegroundColor Cyan

# 5. Local account: create, or reset the password if it exists.
$secure = ConvertTo-SecureString $Password -AsPlainText -Force
if (Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue) {
    Set-LocalUser -Name $UserName -Password $secure -PasswordNeverExpires $true
    Enable-LocalUser -Name $UserName
    Write-Host "[5/6] User $UserName existed: password reset, enabled" -ForegroundColor Cyan
} else {
    New-LocalUser -Name $UserName -Password $secure -FullName $UserName `
        -Description 'RDP login' -PasswordNeverExpires -AccountNeverExpires | Out-Null
    Write-Host "[5/6] User $UserName created" -ForegroundColor Cyan
}

# 6. Group membership by well-known SID, so it works in every language.
#    S-1-5-32-555 = Remote Desktop Users, S-1-5-32-544 = Administrators.
$groups = @('S-1-5-32-555')
if ($Admin) { $groups += 'S-1-5-32-544' }
foreach ($sid in $groups) {
    $name = (Get-LocalGroup -SID $sid).Name
    try {
        Add-LocalGroupMember -SID $sid -Member $UserName
        Write-Host "[6/6] $UserName added to '$name'" -ForegroundColor Cyan
    } catch {
        if ($_.FullyQualifiedErrorId -notlike 'MemberExists*') { throw }
        Write-Host "[6/6] $UserName already in '$name'" -ForegroundColor Cyan
    }
}

# Verify.
Start-Sleep -Seconds 2
$listen = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
if (-not $listen) {
    throw "RDP is configured, but nothing listens on port $port. Reboot and run this script again."
}
$ip = (Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' }).IPAddress -join ', '

Write-Host ''
Write-Host 'RDP is ON.' -ForegroundColor Green
Write-Host "  Listening : TCP $port"
Write-Host "  Local IP  : $ip"
Write-Host "  Username  : .\$UserName"
Write-Host "  Password  : $Password"
