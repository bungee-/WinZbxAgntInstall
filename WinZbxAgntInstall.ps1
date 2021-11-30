﻿<#

    Script for installing zabbix agent to windows os. Intended for environments without automation to ease admin work :D

.Last change
 03 - Changed Parameters collection - doesnt work if param is not the first thing in script.
 02 - Added comments and code cleanup.
 01 - Removed Get-WmiObject commands as that is deprecated in powershell 7 / Use Get-CimInstance

.Description
Script for installing Zabbix Agent on windows machines.

.Author Tomaž Čoha & Tone Kravanja

.Version 1.03

(((((Invoke-WebRequest https://cdn.zabbix.com/zabbix/binaries/stable/5.0/).Links | Select-Object href | Where-Object {$_.href -like "5.0.*"} ).href).substring(4,1)) | Measure-Object -Maximum).maximum

Latest version identification ...
#>
<# Collect parameters from env. parameters that are passed #>
param([switch]$Elevated, [string]$ip, [switch]$force)

$url64 = "https://cdn.zabbix.com/zabbix/binaries/stable/5.0/5.0.18/zabbix_agent2-5.0.18-windows-amd64-openssl.msi"
$url32 = "https://cdn.zabbix.com/zabbix/binaries/stable/5.0/5.0.18/zabbix_agent-5.0.18-windows-amd64-openssl.msi"

<# TO DO - automatic check for newer version of agent #>



function CheckAdmin {
$currentUser = New-Object Security.Principal.WindowsPrincipal $([Security.Principal.WindowsIdentity]::GetCurrent())
$currentUser.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}


<# Test for elevation #>
if ((CheckAdmin) -eq $false)  {
if ($elevated)
{
    Write-Warning "You are not running this as local administrator. Run it again in an elevated prompt." ; break
    #   could not elevate, quit
}

else {

<# If not elevated - help with it :D :D  #>
Start-Process powershell.exe -Verb RunAs -ArgumentList ('-noprofile -noexit -file "{0}" -elevated' -f ($myinvocation.MyCommand.Definition))
}
exit
}

<# Get architecture - 32 or 64 bit system  #>
$systemArchitecture = (get-ciminstance CIM_OperatingSystem).OSArchitecture
Write-Host "Sistem je " -NoNewline
Write-host -BackgroundColor DarkGreen -ForegroundColor White $systemArchitecture


<# If IP is empty collect it from user #>
if ($ip -eq "") {
    $proxyAddress = Read-Host -Prompt 'Enter IP of local zabbix server/proxy.'
    Write-Host -BackgroundColor DarkGreen "Local zabbix server/proxy IP address is: $proxyAddress  Checking ... "-NoNewline

    if (($proxyAddress -eq "") -and -not $force) {

        Write-Host -BackgroundColor DarkRed -ForegroundColor White "`nentered IP address is empty.`nHalting script."
        exit 1
}
} else {
    $proxyAddress = $ip
    Write-Host -BackgroundColor DarkGreen "Local zabbix server/proxy IP address is: $proxyAddress  Checking ... "-NoNewline
}

<# Ping zabbix server/proxy skip if force parameter is in effect #>
if (-not $force){
    if ((Test-Connection $proxyAddress -Quiet -Count 2 -Delay 2) -eq $true -or $force) {
        $prereqSatisfied=$true
        Write-Host -BackgroundColor Black -ForegroundColor Green "[OK]"
    }
    else {
        Write-Host -BackgroundColor Black -ForegroundColor Red "[Error]"
        Write-Host -BackgroundColor DarkRed -ForegroundColor White "`nZabbix Proxy/server is unreachable.`nHalting script.`n"
        exit 1
    }
}


<# Download zabbix agent #>
$file = "$PSScriptRoot\ZabbixAgentInstaller.log"
try {
if ($systemArchitecture -eq "64-bit") {
    $url = $url64
    $output = "$PSScriptRoot\zabbix_agent2-5.0.7-windows-amd64-openssl.msi"
    }
else {
    $url = $url32
    $output = "$PSScriptRoot\zabbix_agent2-5.0.7-windows-i386-openssl.msi"
}

$start_time = Get-Date

Write-Host "`n`nDownloading Zabbix Agent installation..."

Invoke-WebRequest -Uri $url -OutFile $output

Write-Host "Download complete.`n"
Write-Output "Time taken: $((Get-Date).Subtract($start_time).Seconds) second(s)"
} catch {
    $errorOutput = $_
    $errorOutput | Out-File -FilePath $file -Append
    Write-Host -BackgroundColor DarkRed -ForegroundColor White "Error occured. Check script log at $file"
}

$hostname = (Hostname).ToString().ToLower()
Write-Host "Agent hostname is" $hostname


<# Check if zabbix agent is running and kill it #>
$zbx = Get-Process | Where-Object {$_.ProcessName -ilike "zabbix*"}
if ( $null -ne $zbx ) {
    Write-Host "Halting zabbix agent."
    $zbx.kill()
}

<# Check if zabbix agent is installed and uninstall it #>
$MyApp = Get-CimInstance -Class Win32_Product | Where-Object{$_.name -ilike "Zabbix*"}
if ($(Measure-Object -InputObject $myApp).Count -gt 0) {
    Write-Host -BackgroundColor DarkGreen -ForegroundColor white "Removing previous zabbix agent installation."
    $MyApp.uninstall()
} else {
     Write-Host -BackgroundColor DarkGreen -ForegroundColor White "Zabbiy agent is not installed, deinstallation is not necessary."
}

<# If everything so far was ok, then install the agent #>
if ($prereqSatisfied -eq $true -or $force) {
    try {
        Write-Host "installing ..."
        Start-Process msiexec.exe -Wait -ArgumentList "/I $output HOSTNAME=$hostname SERVER=$proxyAddress LPORT=10050 SERVERACTIVE=$proxyAddress RMTCMD=1 /qn"
    } catch {
        $errorOutput = $_
        $errorOutput | Out-File -FilePath $file -Append
        Write-Host -BackgroundColor DarkRed -ForegroundColor White "Error occured. Check script log at $file"
    } finally {
        write-host -BackgroundColor DarkGreen -ForegroundColor White "`n`n Installation was sucessfull. `n"
    }
} else {
    Write-Host -BackgroundColor DarkRed -ForegroundColor White "Something went wrong, skipped install."
}


