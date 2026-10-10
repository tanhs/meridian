#requires -Version 5.1
<# Report 2: per center, days in the month with zero clock-ins.
   Default: previous month (scheduled on the 1st).
   -MonthToDate: current month, 1st through YESTERDAY, resolved at run time (scheduled daily). On the 1st it sends the
                 complete previous month instead, so this single daily task replaces the monthly one.
   -Year/-Month: any specific month (the current month is capped at today). #>
param([int]$Year, [int]$Month, [switch]$MonthToDate, [switch]$DryRun)

Import-Module (Join-Path $PSScriptRoot 'Meridian.psm1') -Force
$job = 'monthend'
Invoke-UniFiGuard -DryRun:$DryRun   # free ports first; never throws
try {
    if ($MonthToDate) {
        if ((Get-Date).Day -eq 1) {
            # On the 1st there is no month-to-date yet: send the COMPLETE previous month instead (a "month-end" report),
            # so this one task replaces the separate MonthEndNoClock task.
            $prev = (Get-Date).Date.AddMonths(-1); $Year = $prev.Year; $Month = $prev.Month
            $MonthToDate = $false
        }
        else { $Year = (Get-Date).Year; $Month = (Get-Date).Month }
    }
    $through = if ($MonthToDate) { (Get-Date).Date.AddDays(-1) } else { (Get-Date).Date }
    if (-not $Year -or -not $Month) { $prev = (Get-Date).Date.AddDays(1 - (Get-Date).Day).AddMonths(-1); $Year = $prev.Year; $Month = $prev.Month }
    $first = Get-Date -Year $Year -Month $Month -Day 1 -Hour 0 -Minute 0 -Second 0 -Millisecond 0
    $last = $first.AddMonths(1).AddDays(-1)
    if ($last -gt $through) { $last = $through }   # month still in progress
    Write-MeridianLog "Month-end zero-day check $($first.ToString('yyyy-MM')) ..$($last.Day)" $job

    $recs = Get-ClockRecord -Year $Year -Month $Month
    $recs = @($recs | Where-Object { $_.Date -ge $first -and $_.Date -le $last })
    $dataDays = @($recs | ForEach-Object { $_.Date } | Select-Object -Unique).Count   # before the own-door filter
    $recs = @(Convert-ToDoorCenter $recs)   # center = the door's center, not the staff's home branch

    $active = @{}   # "CENTER|yyyyMMdd" -> $true
    foreach ($r in $recs) { $active["$($r.Center.ToUpperInvariant())|$($r.Date.ToString('yyyyMMdd'))"] = $true }

    $lines = @(); $rows = @(); $i = 0
    foreach ($c in (Resolve-CenterNames $recs -Year $Year -Month $Month)) {
        $zero = for ($d = $first; $d -le $last; $d = $d.AddDays(1)) {
            if (-not $active.ContainsKey("$($c.Name.ToUpperInvariant())|$($d.ToString('yyyyMMdd'))")) { '{0}/{1}({2})' -f $d.Day, $d.Month, $d.ToString('ddd', [Globalization.CultureInfo]::InvariantCulture) }
        }
        $days = if ($zero) { @($zero) -join ', ' } else { 'none' }
        $letter = Get-ListLetter $i
        $label = if ($c.PinDesc) { '{0} ({1})' -f $c.Name, $c.PinDesc } else { $c.Name }
        $lines += '{0}. {1} - {2}' -f $letter, $label, $days
        $rows += [pscustomobject]@{ Letter = $letter; Name = $c.Name; Desc = $c.PinDesc; Days = $days }
        $i++
    }

    $range = '{0}-{1}/{2}/{3}' -f 1, $last.Day, $Month, $Year
    $head = "Datetime run: $range $((Get-Date).ToString('HH:mm'))`r`nDays with no clock-in, per center"
    $notes = @('(Every calendar day is checked, including weekends and public holidays.)')
    if ($dataDays -eq 0) { $notes += 'WARNING: no clock records found for the month - data feed may be down.' }

    # Plain text (dry run / fallback)
    $body = $head + "`r`n`r`n" + ($lines -join "`r`n") + "`r`n`r`n" + ($notes -join "`r`n`r`n")

    # HTML email: fixed columns; the description column shows the CenterDescriptions value from config.psd1
    $enc = { param($t) [System.Net.WebUtility]::HtmlEncode([string]$t) }
    $td = 'padding:4px 14px 4px 0;border-bottom:1px solid #e0e0e0;vertical-align:top;'
    $th = 'padding:4px 14px 4px 0;border-bottom:2px solid #999;text-align:left;'
    $trs = foreach ($r in $rows) {
        "<tr><td style='$td'>$(& $enc $r.Letter).</td><td style='${td}font-weight:600;white-space:nowrap'>$(& $enc $r.Name)</td>" +
        "<td style='${td}min-width:200px'>$(& $enc $r.Days)</td><td style='${td}color:#777;font-size:9pt'>$(& $enc $r.Desc)</td></tr>"
    }
    $html = "<p>$((& $enc $head) -replace '\r?\n', '<br>')</p>" +
        "<table style='border-collapse:collapse;font-size:10.5pt'><tr><th style='$th'></th><th style='$th'>Center</th><th style='$th'>Days with no clock-in</th><th style='$th'>Center Description</th></tr>" +
        ($trs -join '') + '</table>' +
        (($notes | ForEach-Object { "<p style='color:#555'>$(& $enc $_)</p>" }) -join '')

    $subject = if ($MonthToDate) { "Month-To-Date No Clock-In Report {0:MMM yyyy} (1-{1})" -f $first, $last.Day } else { "Month-End No Clock-In Report {0:MMM yyyy}" -f $first }
    Send-MeridianMail -Subject $subject -Body $body -BodyHtml $html -DryRun:$DryRun -Job $job
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
