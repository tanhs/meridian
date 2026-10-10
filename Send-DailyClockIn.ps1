#requires -Version 5.1
<# Report 1: per center, unique staff clocking in/out for one day. Scheduled daily 23:59.
   Default: lists only centers with 0 clock-ins. -ShowAll lists every center with its count. #>
param([datetime]$Date = (Get-Date).Date, [switch]$ShowAll, [switch]$DryRun)

Import-Module (Join-Path $PSScriptRoot 'Meridian.psm1') -Force
$job = 'daily'
Invoke-UniFiGuard -DryRun:$DryRun   # free ports first; never throws
try {
    $Date = $Date.Date
    Write-MeridianLog "Daily clock-in for $($Date.ToString('yyyy-MM-dd'))" $job
    $recs = Get-ClockRecord -Year $Date.Year -Month $Date.Month -Day $Date.Day
    $recs = @($recs | Where-Object { $_.Date -eq $Date })
    $rawCount = $recs.Count
    $recs = @(Select-OwnDoorRecord $recs)   # only punches at the center's own doors

    $counts = @{}
    foreach ($g in ($recs | Group-Object { $_.Center.ToUpperInvariant() })) {
        $counts[$g.Name] = @($g.Group | Select-Object -ExpandProperty StaffNo -Unique).Count
    }

    $lines = @(); $i = 0; $total = 0; $zeroCount = 0
    foreach ($c in (Resolve-CenterNames $recs -Year $Date.Year -Month $Date.Month)) {
        $key = $c.Name.ToUpperInvariant()
        $n = if ($counts.ContainsKey($key)) { $counts[$key] } else { 0 }
        $total++
        if ($n -eq 0) { $zeroCount++ }
        if (-not $ShowAll -and $n -ne 0) { continue }
        $lines += '{0}. {1} - {2}' -f (Get-ListLetter $i), (Format-CenterLabel $c), $n
        $i++
    }

    $summary = if ($ShowAll) { "$zeroCount of $total centers have 0 clock-ins." }
               elseif ($zeroCount) { "Centers with 0 clock-ins ($zeroCount of $total):" }
               else { "All $total centers have clock-ins." }
    $body = "Datetime run: $((Get-Date).ToString('d/M/yyyy HH:mm'))`r`nDaily clock-in summary for $($Date.ToString('d/M/yyyy'))`r`n`r`n$summary"
    if ($lines) { $body += "`r`n`r`n" + ($lines -join "`r`n") }
    if ($ShowAll) { $body += "`r`n`r`n(Count = unique staff clocking in/out on the day)" }
    if (-not $rawCount) { $body += "`r`n`r`nWARNING: no clock records at all for this date - the clock/SmartPSS feed may be down." }

    Send-MeridianMail -Subject "Daily Clock-In Summary $($Date.ToString('d/M/yyyy'))" -Body $body -DryRun:$DryRun -Job $job
}
catch {
    Write-MeridianLog "FAILED: $_" $job 'ERROR'
    Send-MeridianFailure -Job $job -Error ($_ | Out-String) -DryRun:$DryRun
    exit 1
}
