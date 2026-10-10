#requires -Version 5.1
<#
Run once on the server from an elevated PowerShell. Creates the scheduled tasks under -RunAsUser
(MUST be the same Windows account that created smtp.cred, because DPAPI is per-user).
schtasks.exe is used because New-ScheduledTaskTrigger has no "monthly on day 1" option.
You will be prompted for the account password once per task.
Use -Only to (re)register just some tasks, e.g.  -Only UniFiPortWatch
#>
param([Parameter(Mandatory)][string]$RunAsUser, [string]$BaseDir = 'C:\overtime\scripts\meridian', [string[]]$Only)

$principal = New-Object Security.Principal.WindowsPrincipal ([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Not elevated. Right-click PowerShell > Run as administrator, then run this script again.'
}
if ($RunAsUser -notmatch '[\\@]') { $RunAsUser = "$env:COMPUTERNAME\$RunAsUser" }   # e.g. DVKLSRV08\administrator
Write-Host "Tasks will run as $RunAsUser (must be the account that created smtp.cred)"

function New-Job($name, $script, $schedule, $scriptArgs = '') {
    $tr = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$BaseDir\$script`" $scriptArgs".TrimEnd()
    & schtasks.exe /Create /F /TN "Meridian\$name" /TR $tr @schedule /RU $RunAsUser /RP * /RL HIGHEST
    if ($LASTEXITCODE -ne 0) { throw "Failed to create $name" }
}

$jobs = [ordered]@{
    DailyClockIn    = @('Send-DailyClockIn.ps1',      @('/SC', 'DAILY',   '/ST', '23:59'))
    MonthEndNoClock = @('Send-MonthEndNoClockIn.ps1', @('/SC', 'MONTHLY', '/D', '1', '/ST', '03:30'))
    MonthlyOTClaim  = @('Send-MonthlyOTClaim.ps1',    @('/SC', 'MONTHLY', '/D', '1', '/ST', '03:00'))
    UniFiPortWatch  = @('Watch-UniFiPorts.ps1',       @('/SC', 'HOURLY',  '/MO', '1', '/ST', '00:05'))
    MonthToDateNoClock = @('Send-MonthEndNoClockIn.ps1', @('/SC', 'DAILY', '/ST', '07:00'), '-MonthToDate')
}
foreach ($name in $jobs.Keys) {
    if ($Only -and $Only -notcontains $name) { continue }
    New-Job $name $jobs[$name][0] $jobs[$name][1] $jobs[$name][2]
}

& schtasks.exe /Query /TN 'Meridian\' /FO LIST | Select-String 'TaskName|Next Run'
