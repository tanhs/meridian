#requires -Version 5.1
<#
Quick check of one or more centers, counted the way the reports count them: a punch belongs to the center that owns
the DOOR it was made at (tbl_controller / CenterDoors), whoever made it. Per day it prints unique staff, punches, the
doors, and which home branch (BranchCode) those staff belong to. Doors unknown to tbl_controller (e.g. TMS_) keep
their BranchCode.
  .\Check-Center.ps1 -Center 'DSS RWG','NUSG BG'                       current month
  .\Check-Center.ps1 -Center 'NUSG KJ' -Year 2026 -Month 10 -Staff     also lists StaffNo/StaffName per day
Read-only; sends no mail.
#>
param([Parameter(Mandatory)][string[]]$Center, [int]$Year = (Get-Date).Year, [int]$Month = (Get-Date).Month, [switch]$Staff)

Import-Module (Join-Path $PSScriptRoot 'Meridian.psm1') -Force
$recs = @(Convert-ToDoorCenter (Get-ClockRecord -Year $Year -Month $Month))
$first = Get-Date -Year $Year -Month $Month -Day 1 -Hour 0 -Minute 0 -Second 0 -Millisecond 0
$last = $first.AddMonths(1).AddDays(-1); if ($last -gt (Get-Date).Date) { $last = (Get-Date).Date }
try { $doorMap = Get-DoorMap } catch { Write-Warning "tbl_controller not read: $($_.Exception.Message)"; $doorMap = @{} }

foreach ($c in $Center) {
    $mine = @($recs | Where-Object { $_.Center -eq $c })   # -eq is case-insensitive
    $doorsOfCenter = @($doorMap.GetEnumerator() | Where-Object { $_.Value.ContainsKey($c.ToUpperInvariant()) } | ForEach-Object { $_.Key } | Sort-Object)
    Write-Host "`n=== $c  $($first.ToString('yyyy-MM'))  ($($mine.Count) punches, $(@($mine | Select-Object -ExpandProperty StaffNo -Unique).Count) staff in the month) ==="
    Write-Host ('    doors (tbl_controller / CenterDoors): ' + $(if ($doorsOfCenter) { $doorsOfCenter -join '; ' } else { '(none - punches counted by BranchCode)' }))
    $shared = @($doorsOfCenter | Where-Object { $doorMap[$_].Count -gt 1 })
    if ($shared) { Write-Host ('    NOTE: shared with other centers (kept by home branch): ' + ($shared -join '; ')) }
    for ($d = $first; $d -le $last; $d = $d.AddDays(1)) {
        $day = @($mine | Where-Object { $_.Date -eq $d })
        $doors = @($day | ForEach-Object { $_.Desc } | Where-Object { $_ } | Sort-Object -Unique) -join '; '
        $from = @($day | Group-Object HomeBranch | Sort-Object Count -Descending | ForEach-Object { '{0} x{1}' -f $_.Name, $_.Count }) -join ', '
        $line = '{0:dd/MM ddd}  staff={1,-3} punches={2,-4} doors: {3}   from: {4}' -f $d, @($day | Select-Object -ExpandProperty StaffNo -Unique).Count, $day.Count, $doors, $from
        Write-Host $line
        if ($Staff -and $day) {
            $day | Group-Object StaffNo | ForEach-Object { Write-Host ('      {0}  {1}  [{2}]  x{3}' -f $_.Name, $_.Group[0].Row['StaffName'], $_.Group[0].HomeBranch, $_.Count) }
        }
    }
}
