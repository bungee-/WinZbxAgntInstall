<#
    Script for installing Zabbix agent to Windows OS. Intended for environments without automation to ease admin work :D

.Description
Script for installing Zabbix Agent on Windows machines.

.Author Tomaž Čoha & Tone Kravanja

.Version 2.00 (Robust version)
#>

param([switch]$Elevated, [string]$ip, [switch]$force)

function Log-Error {
    param ([string]$message)
    $file = "$PSScriptRoot\ZabbixAgentInstaller.log"
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp ERROR: $message" | Out-File -FilePath $file -Append
}

function Get-LatestMajorVersions {
    param ([int]$count = 3)
    try {
        $baseUrl = "https://cdn.zabbix.com/zabbix/binaries/stable/"
        $response = Invoke-WebRequest -Uri $baseUrl -UseBasicParsing
        $allVersions = $response.Links.href | Where-Object { $_ -match '^\d+\.\d+' } | ForEach-Object {
            $_.TrimEnd('/')
        }
        $parsedVersions = $allVersions | Sort-Object {[version]$_} -Descending
        return $parsedVersions | Select-Object -First $count
    } catch {
        Log-Error $_.Exception.Message
        Write-Host -BackgroundColor DarkRed -ForegroundColor White "Napaka pri dostopu do $baseUrl"
        Write-Host $_.Exception.Message
        exit 1
    }
}

function Get-LatestPatchVersion {
    param ([string]$majorVersion)
    try {
        $url = "https://cdn.zabbix.com/zabbix/binaries/stable/$majorVersion/"
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing
        $versions = $response.Links.href | Where-Object { $_ -match "^$majorVersion" } | ForEach-Object { $_.TrimEnd('/')
        }
        $latestPatch = ($versions | ForEach-Object { [Version]$_ }) | Sort-Object -Descending | Select-Object -First 1
        return $latestPatch.ToString()
    } catch {
        Log-Error $_.Exception.Message
        Write-Host -BackgroundColor DarkRed -ForegroundColor White "Napaka pri pridobivanju verzije iz $url"
        Write-Host $_.Exception.Message
        exit 1
    }
}

function CheckAdmin {
    $currentUser = New-Object Security.Principal.WindowsPrincipal $([Security.Principal.WindowsIdentity]::GetCurrent())
    $currentUser.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

if ((CheckAdmin) -eq $false)  {
    if ($Elevated) {
        Write-Warning "You are not running this as local administrator. Run it again in an elevated prompt."
        break
    } else {
        Start-Process powershell.exe -Verb RunAs -ArgumentList ('-noprofile -noexit -file "{0}" -Elevated' -f ($myinvocation.MyCommand.Definition))
    }
    exit
}

Write-Host "Preverjam zadnje tri podprte Zabbix verzije ..."
$majorVersions = Get-LatestMajorVersions


Write-Host "`nIzberi verzijo Zabbix agenta za namestitev:`n"
for ($i = 0; $i -lt $majorVersions.Count; $i++) {
    Write-Host ("[{0}] Zabbix {1}" -f $i, $majorVersions[$i])
}

$index = Read-Host -Prompt "Vnesi številko verzije (0-$($majorVersions.Count - 1))"
if ($index -notmatch '^\d+$' -or [int]$index -ge $majorVersions.Count) {
    Write-Host -BackgroundColor DarkRed -ForegroundColor White "Neveljavna izbira. Izhod."
    exit 1
}

$selectedMajor = $majorVersions[$index]


$LatestVersion = Get-LatestPatchVersion -majorVersion $selectedMajor
Write-Host -BackgroundColor DarkGreen -ForegroundColor White "`nIzbrana verzija je: $LatestVersion`n"

$systemArchitecture = (Get-CimInstance CIM_OperatingSystem).OSArchitecture
Write-Host "Sistem je " -NoNewline
Write-Host -BackgroundColor DarkGreen -ForegroundColor White $systemArchitecture

$url64 = "https://cdn.zabbix.com/zabbix/binaries/stable/$selectedMajor/$LatestVersion/zabbix_agent2-$LatestVersion-windows-amd64-openssl.msi"
$url32 = "https://cdn.zabbix.com/zabbix/binaries/stable/$selectedMajor/$LatestVersion/zabbix_agent2-$LatestVersion-windows-i386-openssl.msi"

if ($ip -eq "") {
    $proxyAddress = Read-Host -Prompt 'Enter IP of local Zabbix server/proxy.'
    if (($proxyAddress -eq "") -and -not $force) {
        Write-Host -BackgroundColor DarkRed -ForegroundColor White "`nEntered IP address is empty.`nHalting script."
        exit 1
    }
} else {
    $proxyAddress = $ip
}

if (-not $force) {
    Write-Host "Checking Zabbix server/proxy ... " -NoNewline
    if ((Test-Connection $proxyAddress -Quiet -Count 2 -Delay 2) -eq $true) {
        $prereqSatisfied = $true
        Write-Host -BackgroundColor Black -ForegroundColor Green "[OK]"
    } else {
        Write-Host -BackgroundColor Black -ForegroundColor Red "[Error]"
        Write-Host -BackgroundColor DarkRed -ForegroundColor White "`nZabbix Proxy/server is unreachable.`nHalting script.`n"
        exit 1
    }
}

try {
    $output = if ($systemArchitecture -eq "64-bit") {
        "$PSScriptRoot\zabbix-amd64-openssl.msi"
    } else {
        "$PSScriptRoot\zabbix-i386-openssl.msi"
    }
    $url = if ($systemArchitecture -eq "64-bit") { $url64 } else { $url32 }

    if (Test-Path $output) {
        $choices = '&Yes', '&No'
        $decision = $Host.UI.PromptForChoice("File already exists.", "Do you want to use downloaded file?", $choices, 0)
        if ($decision -ne 0) {
            Remove-Item $output -Force
            Invoke-WebRequest -Uri $url -OutFile $output
        }
    } else {
        Invoke-WebRequest -Uri $url -OutFile $output
    }
} catch {
    Log-Error $_.Exception.Message
    Write-Host -BackgroundColor DarkRed -ForegroundColor White "Napaka med prenosom: $_.Exception.Message"
    exit 1
}

$hostname = (hostname).ToLower()
Write-Host "Agent hostname is" $hostname

$zbx = Get-Process | Where-Object {$_.ProcessName -ilike "zabbix*"}
if ($zbx) {
    Write-Host "Halting Zabbix agent."
    $zbx.Kill()
}

$MyApp = Get-CimInstance -Class Win32_Product | Where-Object {$_.name -ilike "Zabbix*"}
if ($MyApp) {
    Write-Host -BackgroundColor DarkGreen -ForegroundColor White "Removing previous Zabbix agent installation."
    foreach ($app in $MyApp) {
        Start-Process msiexec.exe -Wait -ArgumentList "/x $($app.IdentifyingNumber) /qn"
    }
} else {
    Write-Host -BackgroundColor DarkGreen -ForegroundColor White "Zabbix agent is not installed, deinstallation is not necessary."
}

if ($prereqSatisfied -or $force) {
    try {
        Start-Process msiexec.exe -Wait -ArgumentList "/I $output HOSTNAME=$hostname SERVER=$proxyAddress LPORT=10050 SERVERACTIVE=$proxyAddress RMTCMD=1 /qn"
        Write-Host -BackgroundColor DarkGreen -ForegroundColor White "`n`nNamestitev je bila uspešna.`n"
    } catch {
        Log-Error $_.Exception.Message
        Write-Host -BackgroundColor DarkRed -ForegroundColor White "Napaka med namestitvijo: $_.Exception.Message"
    }
} else {
    Write-Host -BackgroundColor DarkRed -ForegroundColor White "Predpogoji niso izpolnjeni, preskakujem namestitev."
}
