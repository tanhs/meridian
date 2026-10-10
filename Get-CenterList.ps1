#requires -Version 5.1
<#
Lists the centers (BranchCode) seen in the last N months.
  .\Get-CenterList.ps1                 names + punch counts, to pick centers for ExcludeCenters in config.psd1
  .\Get-CenterList.ps1 -Descriptions   paste-ready lines for CenterDescriptions in config.psd1: the most-used
                                       device is the suggested value, all devices seen are shown as a comment
Review the suggestions: tdesc is the door that was punched, and staff also punch at other centers' doors.
#>
param([int]$Months = 3, [switch]$Descriptions)

Import-Module (Join-Path $PSScriptRoot 'Meridian.psm1') -Force
$all = @()
for ($i = 0; $i -lt $Months; $i++) {
    $d = (Get-Date).AddMonths(-$i)
    try { $all += Get-ClockRecord -Year $d.Year -Month $d.Month } catch { Write-Warning "$($d.ToString('yyyy-MM')): $($_.Exception.Message)" }
}

$groups = $all | Group-Object { $_.Center.ToUpperInvariant() } | Sort-Object Name

if (-not $Descriptions) {
    $groups | ForEach-Object { "        '{0}'    # {1} punches" -f $_.Group[0].Center, $_.Count }
    return
}

# Same normalisation as the reports: "Davita Tulips Out" counts as "Davita Tulips".
$groups | ForEach-Object {
    $center = $_.Group[0].Center
    $devices = $_.Group | Where-Object { $_.Desc } |
        Group-Object { ($_.Desc -replace '\s+(Out|In)$', '' -replace '\s+', ' ').Trim().ToUpperInvariant() } |
        Sort-Object @{ e = { $_.Count }; Descending = $true } |
        ForEach-Object { '{0} ({1})' -f ($_.Group[0].Desc -replace '\s+(Out|In)$', '' -replace '\s+', ' ').Trim(), $_.Count }

    $best = if ($devices) { ($devices[0] -replace '\s+\(\d+\)$', '') } else { '' }
    "    '{0}' = '{1}'    # {2}" -f ($center -replace "'", "''"), ($best -replace "'", "''"), ($devices -join '; ')
}
