#requires -Version 5.1
<#
Quick check of one or more centers (BranchCode): per day, unique staff, punches and the doors used.
Use it to see why a center shows "none" (punches every day) or zero days in the reports.
  .\Check-Center.ps1 -Center 'HQ','NUSG BG','NUSG KJ'                  current month
  .\Check-Center.ps1 -Center 'NUSG KJ' -Year 2026 -Month 10 -Staff     also lists StaffNo/StaffName per day
Read-only; sends no mail.
#>
param([Parameter(Mandatory)][string[]]$Center, [int]$Year = (Get-Date).Year, [int]$Month = (Get-Date).Month, [switch]$Staff)

Import-Module (Join-Path $PSScriptRoot 'Meridian.psm1') -Force
$recs = @(Get-ClockRecord -Year $Year -Month $Month)
$first = Get-Date -Year $Year -Month $Month -Day 1 -Hour 0 -Minute 0 -Second 0 -Millisecond 0
$last = $first.AddMonths(1).AddDays(-1); if ($last -gt (Get-Date).Date) { $last = (Get-Date).Date }

foreach ($c in $Center) {
    $mine = @($recs | Where-Object { $_.Center -eq $c })   # -eq is case-insensitive
    Write-Host "`n=== $c  $($first.ToString('yyyy-MM'))  ($($mine.Count) punches, $(@($mine | Select-Object -ExpandProperty StaffNo -Unique).Count) staff in the month) ==="
    for ($d = $first; $d -le $last; $d = $d.AddDays(1)) {
        $day = @($mine | Where-Object { $_.Date -eq $d })
        $doors = @($day | ForEach-Object { $_.Desc } | Where-Object { $_ } | Sort-Object -Unique) -join '; '
        $line = '{0:dd/MM ddd}  staff={1,-3} punches={2,-4} {3}' -f $d, @($day | Select-Object -ExpandProperty StaffNo -Unique).Count, $day.Count, $doors
        Write-Host $line
        if ($Staff -and $day) {
            $day | Group-Object StaffNo | ForEach-Object { Write-Host ('      {0}  {1}  x{2}' -f $_.Name, $_.Group[0].Row['StaffName'], $_.Count) }
        }
    }
}
