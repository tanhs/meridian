#requires -Version 5.1
<#
Hourly watchdog for the Ubiquiti UniFi desktop UI (java -jar ...\ace.jar ui), which leaks sockets until the
server runs out of ephemeral ports and SMTP/SQL connections fail (WSAENOBUFS).
Logic lives in Invoke-UniFiGuard (Meridian.psm1), which every report script also runs before its own work.
Settings: UniFiPortThreshold / UniFiCommandMatch in config.psd1. UniFi is NOT restarted automatically.
#>
param([switch]$DryRun)

Import-Module (Join-Path $PSScriptRoot 'Meridian.psm1') -Force
Invoke-UniFiGuard -DryRun:$DryRun
