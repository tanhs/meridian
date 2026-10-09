#requires -Version 5.1
<#
Extracts usp_StaffMonthlyOTClaim for the previous month's window and emails it as CSV.
Window (OTCutoffHour=3): 1st of previous month 03:00  ->  1st of this month 03:00 (end exclusive).
The proc only filters by whole month/day, so we call it for the previous month plus day 1 of the
current month (needed for the 00:00-03:00 tail), then cut by datetime here.
Override with -RunDate (e.g. -RunDate 2026-11-01) to regenerate a past period.
#>
param([datetime]$RunDate = (Get-Date).Date, [switch]$DryRun)

Import-Module (Join-Path $PSScriptRoot 'Meridian.psm1') -Force
$job = 'otclaim'
Invoke-UniFiGuard -DryRun:$DryRun   # free ports first; never throws
try {
    $cfg = Get-MeridianConfig
    $hour = [int]$cfg.OTCutoffHour
    $end = $RunDate.Date.AddDays(1 - $RunDate.Day).AddHours($hour)   # 1st of RunDate's month
    $start = $end.AddMonths(-1)
    Write-MeridianLog "OT extract $($start.ToString('yyyy-MM-dd HH:mm')) -> $($end.ToString('yyyy-MM-dd HH:mm'))" $job

    # List.Add keeps each DataTable intact; array += would enumerate it into rows.
    $tables = New-Object System.Collections.Generic.List[object]
    $tables.Add((Invoke-ClockProc -Year $start.Year -Month $start.Month))
    $warn = ''
    if ($hour -gt 0) {
        try { $tables.Add((Invoke-ClockProc -Year $end.Year -Month $end.Month -Day 1)) }
        catch { $warn = "WARNING: could not read day 1 of $($end.ToString('yyyy-MM')) (00:00-$('{0:00}' -f $hour):00 tail is missing): $($_.Exception.Message)"; Write-MeridianLog $warn $job 'WARN' }
    }

    $rows = foreach ($t in $tables) {
        foreach ($rec in (ConvertTo-ClockRecord $t)) {
            if ($rec.DateTime -ge $start -and $rec.DateTime -lt $end) { $rec }
        }
    }
    $rows = @($rows | Sort-Object Center, DateTime)
    if (-not $rows) { throw "Procedure returned no rows inside the window - not sending an empty claim." }

    $csv = Join-Path $cfg.OutputDir ('StaffMonthlyOTClaim_{0:yyyyMMdd}_{1:yyyyMMdd}.csv' -f $start, $end)
    $rows | ForEach-Object {
        [pscustomobject][ordered]@{
            TransID = $_.Row['TransID']; TransDate = $_.DateTime.ToString('dd-MM-yyyy'); TransTime = $_.Time.ToString('hh\:mm\:ss')
            BranchCode = $_.Center; tdesc = $_.Row['tdesc']; StaffName = $_.Row['StaffName']; StaffNo = $_.StaffNo
        }
    } | Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8

    $body = "Datetime run: $((Get-Date).ToString('d/M/yyyy HH:mm'))`r`nStaff monthly OT claim extract`r`nPeriod: $($start.ToString('d/M/yyyy HH:mm')) to $($end.ToString('d/M/yyyy HH:mm'))`r`nRows: $($rows.Count)`r`n`r`nSee attached CSV."
    if ($warn) { $body += "`r`n`r`n$warn" }
    Send-MeridianMail -Subject ("Staff Monthly OT Claim {0:d/M/yyyy} - {1:d/M/yyyy}" -f $start, $end) -Body $body -Attachments @($csv) -DryRun:$DryRun -Job $job
}
catch {
    Write-MeridianLog "FAILED: $_" $job 'ERROR'
    Send-MeridianFailure -Job $job -Error ($_ | Out-String) -DryRun:$DryRun
    exit 1
}
