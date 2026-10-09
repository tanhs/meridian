#requires -Version 5.1
<# Report 1: unique staff clocking in/out per center for one day. Scheduled daily 23:59. #>
param([datetime]$Date = (Get-Date).Date, [switch]$DryRun)

Import-Module (Join-Path $PSScriptRoot 'Meridian.psm1') -Force
$job = 'daily'
Invoke-UniFiGuard -DryRun:$DryRun   # free ports first; never throws
try {
    $Date = $Date.Date
    Write-MeridianLog "Daily clock-in for $($Date.ToString('yyyy-MM-dd'))" $job
    $recs = Get-ClockRecord -Year $Date.Year -Month $Date.Month -Day $Date.Day
    $recs = @($recs | Where-Object { $_.Date -eq $Date })

    $counts = @{}
    foreach ($g in ($recs | Group-Object { $_.Center.ToUpperInvariant() })) {
        $counts[$g.Name] = @($g.Group | Select-Object -ExpandProperty StaffNo -Unique).Count
    }

    $lines = @(); $i = 0
    foreach ($name in (Resolve-CenterNames $recs -Year $Date.Year -Month $Date.Month)) {
        $key = $name.ToUpperInvariant()
        $n = if ($counts.ContainsKey($key)) { $counts[$key] } else { 0 }
        $lines += '{0}. {1} - {2}' -f (Get-ListLetter $i), $name, $n
        $i++
    }

    $body = "Datetime run: $((Get-Date).ToString('d/M/yyyy HH:mm'))`r`nDaily clock-in summary for $($Date.ToString('d/M/yyyy'))`r`n`r`n" + ($lines -join "`r`n")
    $body += "`r`n`r`n(Count = unique staff clocking in/out on the day)"
    if (-not $recs) { $body += "`r`n`r`nWARNING: no clock records at all for this date - the clock/SmartPSS feed may be down." }

    Send-MeridianMail -Subject "Daily Clock-In Summary $($Date.ToString('d/M/yyyy'))" -Body $body -DryRun:$DryRun -Job $job
}
catch {
    Write-MeridianLog "FAILED: $_" $job 'ERROR'
    Send-MeridianFailure -Job $job -Error ($_ | Out-String) -DryRun:$DryRun
    exit 1
}
