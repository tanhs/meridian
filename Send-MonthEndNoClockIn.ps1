#requires -Version 5.1
<# Report 2: per center, days in the month with zero clock-ins. Scheduled on the 1st for the previous month. #>
param([int]$Year, [int]$Month, [switch]$DryRun)

Import-Module (Join-Path $PSScriptRoot 'Meridian.psm1') -Force
$job = 'monthend'
Invoke-UniFiGuard -DryRun:$DryRun   # free ports first; never throws
try {
    if (-not $Year -or -not $Month) { $prev = (Get-Date).Date.AddDays(1 - (Get-Date).Day).AddMonths(-1); $Year = $prev.Year; $Month = $prev.Month }
    $first = Get-Date -Year $Year -Month $Month -Day 1 -Hour 0 -Minute 0 -Second 0 -Millisecond 0
    $last = $first.AddMonths(1).AddDays(-1)
    if ($last -gt (Get-Date).Date) { $last = (Get-Date).Date }   # month still in progress
    Write-MeridianLog "Month-end zero-day check $($first.ToString('yyyy-MM')) ..$($last.Day)" $job

    $recs = Get-ClockRecord -Year $Year -Month $Month
    $recs = @($recs | Where-Object { $_.Date -ge $first -and $_.Date -le $last })

    $active = @{}   # "CENTER|yyyyMMdd" -> $true
    foreach ($r in $recs) { $active["$($r.Center.ToUpperInvariant())|$($r.Date.ToString('yyyyMMdd'))"] = $true }
    $dataDays = @($recs | ForEach-Object { $_.Date } | Select-Object -Unique).Count

    $lines = @(); $i = 0
    foreach ($name in (Resolve-CenterNames $recs)) {
        $zero = for ($d = $first; $d -le $last; $d = $d.AddDays(1)) {
            if (-not $active.ContainsKey("$($name.ToUpperInvariant())|$($d.ToString('yyyyMMdd'))")) { '{0}/{1}' -f $d.Day, $d.Month }
        }
        $lines += '{0}. {1} - {2}' -f (Get-ListLetter $i), $name, $(if ($zero) { @($zero) -join ', ' } else { 'none' })
        $i++
    }

    $range = '{0}-{1}/{2}/{3}' -f 1, $last.Day, $Month, $Year
    $body = "Datetime run: $range $((Get-Date).ToString('HH:mm'))`r`nDays with no clock-in, per center`r`n`r`n" + ($lines -join "`r`n")
    $body += "`r`n`r`n(Every calendar day is checked, including weekends and public holidays.)"
    if ($dataDays -eq 0) { $body += "`r`n`r`nWARNING: no clock records found for the month - data feed may be down." }
    if (-not @((Get-MeridianConfig).Centers)) { $body += "`r`n`r`nNOTE: Centers list in config.psd1 is empty; centers with zero punches all month are not shown." }

    Send-MeridianMail -Subject ("Month-End No Clock-In Report {0:MMM yyyy}" -f $first) -Body $body -DryRun:$DryRun -Job $job
}
catch {
    Write-MeridianLog "FAILED: $_" $job 'ERROR'
    Send-MeridianFailure -Job $job -Error ($_ | Out-String) -DryRun:$DryRun
    exit 1
}
finally {
    # Runs whether or not the report succeeded.
    try { Invoke-MeridianHousekeeping -Job $job -DryRun:$DryRun }
    catch { Write-MeridianLog "Housekeeping failed: $_" $job 'WARN' }
}
