#Requires -RunAsAdministrator

# Purpose: stop the Windows hypervisor on Windows 11, so that VMware Workstation
# can use the setting "Virtualize Intel VT-x/EPT or AMD-V/RVI".
#
# Run this script in PowerShell as Administrator. The computer restarts at the end.
#
# Effects:
# - Memory Integrity and Credential Guard go off. This decreases the security.
# - WSL 2, Docker Desktop, Windows Sandbox, and Hyper-V virtual machines stop.
#
# This script cannot correct these conditions:
# - VT-x or AMD-V is off in the BIOS or UEFI.
# - Credential Guard has a UEFI lock.
# - A domain, Intune, or Group Policy applies the settings again.
#
# This script was not tested on a Windows computer.

# 1. Stop the Windows hypervisor at start-up.
bcdedit /set hypervisorlaunchtype off

# 2. Disable the Windows features that use the hypervisor.
$features = 'Microsoft-Hyper-V-All', 'HypervisorPlatform', 'VirtualMachinePlatform', 'Containers-DisposableClientVM'
foreach ($name in $features) {
    try {
        Disable-WindowsOptionalFeature -Online -FeatureName $name -NoRestart -ErrorAction Stop | Out-Null
    } catch {
        Write-Host "Skipped: $name"
    }
}

# 3. Disable virtualization-based security, Memory Integrity, and Credential Guard.
reg add "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard" /v EnableVirtualizationBasedSecurity /t REG_DWORD /d 0 /f
reg add "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" /v Enabled /t REG_DWORD /d 0 /f
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" /v LsaCfgFlags /t REG_DWORD /d 0 /f
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard" /v LsaCfgFlags /t REG_DWORD /d 0 /f

# 4. Restart the computer.
# After the restart, this command must show False:
#   (Get-CimInstance Win32_ComputerSystem).HypervisorPresent
Restart-Computer
