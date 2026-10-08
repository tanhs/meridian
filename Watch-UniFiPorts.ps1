#requires -Version 5.1
<#
Hourly watchdog for the Ubiquiti UniFi controller (java -jar ...\ace.jar), which leaks sockets until the
server runs out of ephemeral ports and SMTP/SQL connections start failing (WSAENOBUFS).
If a matching process holds more than UniFiPortThreshold TCP sockets it is killed and an email is sent.
It is NOT restarted automatically.
Only processes whose command line contains UniFiCommandMatch are ever touched.
#>
param([switch]$DryRun)

Import-Module (Join-Path $PSScriptRoot 'Meridian.psm1') -Force
$job = 'unifiwatch'
try {
    $cfg = Get-MeridianConfig
    $limit = [int]$cfg.UniFiPortThreshold
    $match = [string]$cfg.UniFiCommandMatch

    $procs = @(Get-CimInstance Win32_Process -Filter "Name='javaw.exe' OR Name='java.exe'" |
        Where-Object { $_.CommandLine -and $_.CommandLine -like "*$match*" })

    if (-not $procs) { Write-MeridianLog "No process matching '$match' running" $job; return }

    foreach ($p in $procs) {
        $count = @(Get-NetTCPConnection -OwningProcess $p.ProcessId -ErrorAction SilentlyContinue).Count
        Write-MeridianLog "PID $($p.ProcessId) holds $count sockets (limit $limit)" $job
        if ($count -le $limit) { continue }

        $msg = "UniFi (PID $($p.ProcessId), started $($p.CreationDate.ToString('d/M/yyyy HH:mm'))) held $count TCP sockets, over the limit of $limit."
        if ($DryRun) { Write-MeridianLog "DRY RUN - would kill. $msg" $job 'WARN'; continue }

        Stop-Process -Id $p.ProcessId -Force
        Write-MeridianLog "KILLED. $msg" $job 'WARN'
        Start-Sleep -Seconds 5   # let Windows release the ports before we try to send mail
        try {
            Send-MeridianMail -Job $job -Subject "[Meridian] UniFi killed on $env:COMPUTERNAME" `
                -Body "$msg`r`n`r`nThe process was stopped to free ephemeral ports. It has NOT been restarted.`r`nTime: $((Get-Date).ToString('d/M/yyyy HH:mm'))"
        }
        catch { Write-MeridianLog "Could not send kill notice: $_" $job 'ERROR' }
    }
}
catch {
    Write-MeridianLog "FAILED: $_" $job 'ERROR'
    exit 1
}
