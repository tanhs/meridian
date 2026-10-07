#requires -Version 5.1
<# Prints distinct centers seen in the last N months so you can paste them into config.psd1 (Centers). #>
param([int]$Months = 3)
Import-Module (Join-Path $PSScriptRoot 'Meridian.psm1') -Force
$all = @()
for ($i = 0; $i -lt $Months; $i++) {
    $d = (Get-Date).AddMonths(-$i)
    try { $all += Get-ClockRecord -Year $d.Year -Month $d.Month } catch { Write-Warning "$($d.ToString('yyyy-MM')): $($_.Exception.Message)" }
}
$all | Group-Object { $_.Center.ToUpperInvariant() } | Sort-Object Name | ForEach-Object {
    "        '{0}'    # {1} punches" -f $_.Group[0].Center, $_.Count
}
