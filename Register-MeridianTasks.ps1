#requires -Version 5.1
<#
Run once on the server from an elevated PowerShell. Creates 3 scheduled tasks under -RunAsUser
(MUST be the same Windows account that created smtp.cred, because DPAPI is per-user).
schtasks.exe is used because New-ScheduledTaskTrigger has no "monthly on day 1" option.
You will be prompted for the account password.
#>
param([Parameter(Mandatory)][string]$RunAsUser, [string]$BaseDir = 'C:\overtime\scripts\meridian')

function New-Job($name, $script, $schedule) {
    $tr = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$BaseDir\$script`""
    & schtasks.exe /Create /F /TN "Meridian\$name" /TR $tr @schedule /RU $RunAsUser /RP * /RL HIGHEST
    if ($LASTEXITCODE -ne 0) { throw "Failed to create $name" }
}

New-Job 'DailyClockIn'     'Send-DailyClockIn.ps1'       @('/SC', 'DAILY',   '/ST', '23:59')
New-Job 'MonthEndNoClock'  'Send-MonthEndNoClockIn.ps1'  @('/SC', 'MONTHLY', '/D', '1', '/ST', '03:30')
New-Job 'MonthlyOTClaim'   'Send-MonthlyOTClaim.ps1'     @('/SC', 'MONTHLY', '/D', '1', '/ST', '03:00')

& schtasks.exe /Query /TN 'Meridian\' /FO LIST | Select-String 'TaskName|Next Run'
