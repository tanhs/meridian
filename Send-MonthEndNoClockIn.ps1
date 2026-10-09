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

    $lines = @(); $rows = @(); $i = 0
    foreach ($c in (Resolve-CenterNames $recs -Year $Year -Month $Month)) {
        $zero = for ($d = $first; $d -le $last; $d = $d.AddDays(1)) {
            if (-not $active.ContainsKey("$($c.Name.ToUpperInvariant())|$($d.ToString('yyyyMMdd'))")) { '{0}/{1}' -f $d.Day, $d.Month }
        }
        $days = if ($zero) { @($zero) -join ', ' } else { 'none' }
        $letter = Get-ListLetter $i
        $lines += '{0}. {1} - {2}' -f $letter, (Format-CenterLabel $c), $days
        $rows += [pscustomobject]@{ Letter = $letter; Name = $c.Name; Desc = $c.Desc; Days = $days }
        $i++
    }

    $range = '{0}-{1}/{2}/{3}' -f 1, $last.Day, $Month, $Year
    $head = "Datetime run: $range $((Get-Date).ToString('HH:mm'))`r`nDays with no clock-in, per center"
    $notes = @('(Every calendar day is checked, including weekends and public holidays.)')
    if ($dataDays -eq 0) { $notes += 'WARNING: no clock records found for the month - data feed may be down.' }

    # Plain text (dry run / fallback)
    $body = $head + "`r`n`r`n" + ($lines -join "`r`n") + "`r`n`r`n" + ($notes -join "`r`n`r`n")

    # HTML email: fixed columns so the dates stay readable however many devices a center has
    $enc = { param($t) [System.Net.WebUtility]::HtmlEncode([string]$t) }
    $td = 'padding:4px 14px 4px 0;border-bottom:1px solid #e0e0e0;vertical-align:top;'
    $th = 'padding:4px 14px 4px 0;border-bottom:2px solid #999;text-align:left;'
    $trs = foreach ($r in $rows) {
        "<tr><td style='$td'>$(& $enc $r.Letter).</td><td style='${td}font-weight:600;white-space:nowrap'>$(& $enc $r.Name)</td>" +
        "<td style='${td}min-width:200px'>$(& $enc $r.Days)</td><td style='${td}color:#777;font-size:9pt'>$(& $enc $r.Desc)</td></tr>"
    }
    $html = "<p>$((& $enc $head) -replace '\r?\n', '<br>')</p>" +
        "<table style='border-collapse:collapse;font-size:10.5pt'><tr><th style='$th'></th><th style='$th'>Center</th><th style='$th'>Days with no clock-in</th><th style='$th'>Devices</th></tr>" +
        ($trs -join '') + '</table>' +
        (($notes | ForEach-Object { "<p style='color:#555'>$(& $enc $_)</p>" }) -join '')

    Send-MeridianMail -Subject ("Month-End No Clock-In Report {0:MMM yyyy}" -f $first) -Body $body -BodyHtml $html -DryRun:$DryRun -Job $job
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
