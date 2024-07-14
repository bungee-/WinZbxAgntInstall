<#

    Script for installing Zabbix agent to Windows OS. Intended for environments without automation to ease admin work :D

.Last change
 07 - Fixed uninstallation process for Zabbix agent and ensured compatibility with PowerShell versions from Server 2016 onwards.
 06 - Updated script for Zabbix agent version 7 and ensured compatibility with PowerShell versions from Server 2016 onwards.
 05 - Updated script for Zabbix agent version 7.
 04 - Added automatic latest version check and if version is present at the script ask to use that.
 03 - Changed Parameters collection - doesn't work if param is not the first thing in script.
 02 - Added comments and code cleanup.
 01 - Removed Get-WmiObject commands as that is deprecated in PowerShell 7 / Use Get-CimInstance

.Description
Script for installing Zabbix Agent on Windows machines.

.Author Tomaž Čoha & Tone Kravanja

.Version 1.07

#>

<# Collect parameters from env. parameters that are passed #>
param([switch]$Elevated, [string]$ip, [switch]$force)

$urlBase = "https://cdn.zabbix.com/zabbix/binaries/stable/7.0"

$tttt = @()

Write-Host "Preverjam zadnjo verzijo agenta ...  " -NoNewline

<# Get list of available versions on server #>
$ttt1 = (Invoke-WebRequest -Uri $urlBase).Links.Href | Select-String -Pattern "7.0"
<# Trim leading \ from end of all strings #>
$ttt1 | ForEach-Object { $tttt += $_.ToString().TrimEnd('/') }
<# Look for highest available version with conversion to Version variable (nifty trick) #>
$LatestVersion = $($tttt | ForEach-Object {[System.Version]$_} | Measure-Object -Maximum).Maximum.ToString()

Write-Host -BackgroundColor DarkGreen -ForegroundColor White $LatestVersion

$url64 = "https://cdn.zabbix.com/zabbix/binaries/stable/7.0/$LatestVersion/zabbix_agent2-$LatestVersion-windows-amd64-openssl.msi"
$url32 = "https://cdn.zabbix.com/zabbix/binaries/stable/7.0/$LatestVersion/zabbix_agent2-$LatestVersion-windows-i386-openssl.msi"

function CheckAdmin {
    $currentUser = New-Object Security.Principal.WindowsPrincipal $([Security.Principal.WindowsIdentity]::GetCurrent())
    $currentUser.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

<# Test for elevation #>
if ((CheckAdmin) -eq $false)  {
    if ($Elevated) {
        Write-Warning "You are not running this as local administrator. Run it again in an elevated prompt."
        break
    }
    else {
        <# If not elevated - help with it :D :D  #>
        Start-Process powershell.exe -Verb RunAs -ArgumentList ('-noprofile -noexit -file "{0}" -Elevated' -f ($myinvocation.MyCommand.Definition))
    }
    exit
}

<# Get architecture - 32 or 64 bit system  #>
$systemArchitecture = (Get-CimInstance CIM_OperatingSystem).OSArchitecture
Write-Host "Sistem je " -NoNewline
Write-Host -BackgroundColor DarkGreen -ForegroundColor White $systemArchitecture

<# If IP is empty collect it from user #>
if ($ip -eq "") {
    $proxyAddress = Read-Host -Prompt 'Enter IP of local Zabbix server/proxy.'
    Write-Host -BackgroundColor DarkGreen "Local Zabbix server/proxy IP address is: $proxyAddress  Checking ... " -NoNewline

    if (($proxyAddress -eq "") -and -not $force) {
        Write-Host -BackgroundColor DarkRed -ForegroundColor White "`nEntered IP address is empty.`nHalting script."
        exit 1
    }
}
else {
    $proxyAddress = $ip
    Write-Host -BackgroundColor DarkGreen "Local Zabbix server/proxy IP address is: $proxyAddress  Checking ... " -NoNewline
}

<# Ping Zabbix server/proxy skip if force parameter is in effect #>
if (-not $force) {
    if ((Test-Connection $proxyAddress -Quiet -Count 2 -Delay 2) -eq $true -or $force) {
        $prereqSatisfied = $true
        Write-Host -BackgroundColor Black -ForegroundColor Green "[OK]"
    }
    else {
        Write-Host -BackgroundColor Black -ForegroundColor Red "[Error]"
        Write-Host -BackgroundColor DarkRed -ForegroundColor White "`nZabbix Proxy/server is unreachable.`nHalting script.`n"
        exit 1
    }
}

<# Download Zabbix agent #>
$file = "$PSScriptRoot\ZabbixAgentInstaller.log"
try {
    if ($systemArchitecture -eq "64-bit") {
        $url = $url64
        $output = "$PSScriptRoot\zabbix-amd64-openssl.msi"
    }
    else {
        $url = $url32
        $output = "$PSScriptRoot\zabbix-i386-openssl.msi"
    }

    $start_time = Get-Date

    if (Test-Path -Path $output -PathType Leaf) {
        $choices = '&Yes', '&No'
        $decision = $Host.UI.PromptForChoice("File already exists.", "Do you want to use downloaded file?", $choices, 0)
        if ($decision -eq 0) {
            Write-Host "`n`nUsing existing file ...."
        }
        else {
            Write-Host "`n`nRemoving file and Downloading Zabbix Agent installation..."
            Remove-Item $output -Force
            Invoke-WebRequest -Uri $url -OutFile $output
        }
    }
    else {
        Write-Host "`n`nDownloading Zabbix Agent installation..."
        Invoke-WebRequest -Uri $url -OutFile $output
    }

    Write-Host "Prenos zaključen.`n"
    Write-Output "Time taken: $((Get-Date).Subtract($start_time).Seconds) second(s)"
}
catch {
    $errorOutput = $_
    $errorOutput | Out-File -FilePath $file -Append
    Write-Host -BackgroundColor DarkRed -ForegroundColor White "Error occurred. Check script log at $file"
}

$hostname = (Hostname).ToString().ToLower()
Write-Host "Agent hostname is" $hostname

<# Check if Zabbix agent is running and kill it #>
$zbx = Get-Process | Where-Object {$_.ProcessName -ilike "zabbix*"}
if ($null -ne $zbx) {
    Write-Host "Halting Zabbix agent."
    $zbx.Kill()
}

<# Check if Zabbix agent is installed and uninstall it #>
$MyApp = Get-CimInstance -Class Win32_Product | Where-Object {$_.name -ilike "Zabbix*"}
if ($MyApp) {
    Write-Host -BackgroundColor DarkGreen -ForegroundColor White "Removing previous Zabbix agent installation."
    foreach ($app in $MyApp) {
        Start-Process msiexec.exe -Wait -ArgumentList "/x $($app.IdentifyingNumber) /qn"
    }
}
else {
    Write-Host -BackgroundColor DarkGreen -ForegroundColor White "Zabbix agent is not installed, deinstallation is not necessary."
}

<# If everything so far was ok, then install the agent #>
if ($prereqSatisfied -eq $true -or $force) {
    try {
        Write-Host "Installing ..."
        Start-Process msiexec.exe -Wait -ArgumentList "/I $output HOSTNAME=$hostname SERVER=$proxyAddress LPORT=10050 SERVERACTIVE=$proxyAddress RMTCMD=1 /qn"
    }
    catch {
        $errorOutput = $_
        $errorOutput | Out-File -FilePath $file -Append
        Write-Host -BackgroundColor DarkRed -ForegroundColor White "Error occurred. Check script log at $file"
    }
    finally {
        Write-Host -BackgroundColor DarkGreen -ForegroundColor White "`n`n Installation was successful. `n"
    }
}
else {
    Write-Host -BackgroundColor DarkRed -ForegroundColor White "Something went wrong, skipped install."
}
