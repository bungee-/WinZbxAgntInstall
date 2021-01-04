<#

   Alarix Windows Zabbix Agent installer
   Copyright (C) 2020-2024 Alarix d.o.o.
                                          Script is continuation of Tomaž Čoha work.   

.Description 
Script for installing Zabbix Agent on windows machines.

.Author Tomaž Čoha & Tone Kravanja
#>


param([switch]$Elevated, [string]$ip, [switch]$force)
function CheckAdmin {
$currentUser = New-Object Security.Principal.WindowsPrincipal $([Security.Principal.WindowsIdentity]::GetCurrent())
$currentUser.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}


if ((CheckAdmin) -eq $false)  {
if ($elevated)
{
    Write-Warning "You are not running this as local administrator. Run it again in an elevated prompt." ; break
    #   could not elevate, quit
}
 
else {
 
Start-Process powershell.exe -Verb RunAs -ArgumentList ('-noprofile -noexit -file "{0}" -elevated' -f ($myinvocation.MyCommand.Definition))
}
exit
}

#Force argument za skripto, da preskoči ping check
#$force=$args[0]
# if ($null -ne $force) {
#     if ($force.ToString().ToLower() -eq "-force")
#     {
#         $force = 1
#     }
#     else {
#         $force = 0
#     }
# }


Write-host "IP=$ip, elevated=$elevated, force=$Force"



$systemArchitecture = (get-ciminstance CIM_OperatingSystem).OSArchitecture
Write-Host "Sistem je " -NoNewline
Write-host -BackgroundColor DarkGreen -ForegroundColor White $systemArchitecture

if ($ip -eq "") {
    $proxyAddress = Read-Host -Prompt 'Vnesi IP naslov lokalnega Zabbix Proxy strežnika'
    Write-Host -BackgroundColor DarkGreen "Naslov lokalnega Zabbix Proxy strežnika je $proxyAddress  Preverjam ... "-NoNewline

    if (($proxyAddress -eq "") -and -not $force) {  

        Write-Host -BackgroundColor DarkRed -ForegroundColor White "`nIP naslov je prazen.`nUstavljam skripto." 
        exit 1
}
} else {
    $proxyAddress = $ip
    Write-Host -BackgroundColor DarkGreen "Naslov lokalnega Zabbix Proxy strežnika je $proxyAddress  Preverjam ... "-NoNewline
}

if (-not $force){
    if ((Test-Connection $proxyAddress -Quiet -Count 2 -Delay 2) -eq $true -or $force) {
        $prereqSatisfied=$true
        Write-Host -BackgroundColor Black -ForegroundColor Green "[OK]"
    }
    else {
        Write-Host -BackgroundColor Black -ForegroundColor Red "[Error]"
        Write-Host -BackgroundColor DarkRed -ForegroundColor White "`nZabbix Proxy nedosegljiv.`nUstavljam skripto.`n" 
        exit 1
    }
}

$file = "$PSScriptRoot\ZabbixAgentInstaller.log"
try {
if ($systemArchitecture -eq "64-bit") {
    $url = "https://cdn.zabbix.com/zabbix/binaries/stable/5.0/5.0.7/zabbix_agent2-5.0.7-windows-amd64-openssl.msi"
    $output = "$PSScriptRoot\zabbix_agent2-5.0.7-windows-amd64-openssl.msi"
    }
else {
    $url = "https://cdn.zabbix.com/zabbix/binaries/stable/5.0/5.0.7/zabbix_agent2-5.0.7-windows-i386-openssl.msi"
    $output = "$PSScriptRoot\zabbix_agent2-5.0.7-windows-i386-openssl.msi"
} 

$start_time = Get-Date

Write-Host "`n`nPrenašam Zabbix Agent namestitev..."

Invoke-WebRequest -Uri $url -OutFile $output

Write-Host "Prenos zaključen.`n"
Write-Output "Time taken: $((Get-Date).Subtract($start_time).Seconds) second(s)"
} catch {
    $errorOutput = $_
    $errorOutput | Out-File -FilePath $file -Append
    Write-Host -BackgroundColor DarkRed -ForegroundColor White "Error occured. Check script log at $file"
}

$hostname = (Hostname).ToString().ToLower()
Write-Host "Hostname strežnika je" $hostname


$zbx = Get-Process | Where-Object {$_.ProcessName -ilike "zabbix*"}

if ( $null -ne $zbx ) {
    Write-Host "Ustavljam Zabbix process."
    $zbx.kill()
}

$MyApp = Get-WmiObject -Class Win32_Product | Where-Object{$_.name -ilike "Zabbix*"}
if ($(Measure-Object -InputObject $myApp).Count -gt 0) {
    Write-Host -BackgroundColor DarkGreen -ForegroundColor white "Odstranjujem prejšnji zabbix install."
    $MyApp.uninstall()
} else {
     Write-Host -BackgroundColor DarkGreen -ForegroundColor White "Zabbix agent ni nameščen, ni potrebe po odstranitvi."   
}

if ($prereqSatisfied -eq $true -or $force) {
    try {
        Write-Host "installing ..."
        Start-Process msiexec.exe -Wait -ArgumentList "/I $output HOSTNAME=$hostname SERVER=$proxyAddress LPORT=10050 SERVERACTIVE=$proxyAddress RMTCMD=1 /qn" 
    } catch {
        $errorOutput = $_
        $errorOutput | Out-File -FilePath $file -Append
        Write-Host -BackgroundColor DarkRed -ForegroundColor White "Error occured. Check script log at $file"
    } finally {
        write-host -BackgroundColor DarkGreen -ForegroundColor White "`n`n Namestitev je bila uspešna. `n"
    }
} else {
    Write-Host -BackgroundColor DarkRed -ForegroundColor White "Something went wrong, skipped install."
}


