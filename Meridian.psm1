#requires -Version 5.1
Set-StrictMode -Version Latest

$script:Config = $null

function Get-MeridianConfig {
    if (-not $script:Config) {
        $script:Config = Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot 'config.psd1')
        foreach ($d in $script:Config.LogDir, $script:Config.OutputDir) {
            if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
        }
    }
    $script:Config
}

function Write-MeridianLog {
    param([string]$Message, [string]$Job = 'meridian', [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO')
    $cfg = Get-MeridianConfig
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -Path (Join-Path $cfg.LogDir ("$Job-{0}.log" -f (Get-Date -Format 'yyyyMM'))) -Value $line
    Write-Host $line
}

function Invoke-MeridianHousekeeping {
    <# Deletes files in LogDir and OutputDir whose LastWriteTime is older than RetentionMonths. #>
    param([string]$Job = 'meridian', [switch]$DryRun)
    $cfg = Get-MeridianConfig
    $cutoff = (Get-Date).Date.AddMonths(-[int]$cfg.RetentionMonths)
    foreach ($dir in $cfg.LogDir, $cfg.OutputDir) {
        foreach ($f in @(Get-ChildItem -Path $dir -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $cutoff })) {
            try {
                if ($DryRun) { Write-MeridianLog "DRY RUN - would delete $($f.FullName)" $Job; continue }
                Remove-Item -LiteralPath $f.FullName -Force
                Write-MeridianLog "Housekeeping deleted $($f.FullName) ($($f.LastWriteTime.ToString('yyyy-MM-dd')))" $Job
            }
            catch { Write-MeridianLog "Housekeeping could not delete $($f.FullName): $_" $Job 'WARN' }
        }
    }
}

function Get-PlainSecret {
    # Reads a DPAPI-protected file created by: Read-Host -AsSecureString | ConvertFrom-SecureString
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path $Path)) { throw "Credential file not found: $Path" }
    # -Raw keeps the trailing CRLF that Set-Content adds, which breaks the hex parse; strip all whitespace.
    $text = (Get-Content -Path $Path -Raw) -replace '\s', ''
    try { $secure = ConvertTo-SecureString -String $text }
    catch { throw "Cannot decrypt $Path as $env:USERDOMAIN\$env:USERNAME ($($_.Exception.Message)). Recreate it while logged in as the account that runs the task (Read-Host -AsSecureString | ConvertFrom-SecureString | Set-Content)." }
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

function New-MeridianSqlConnection {
    <# Opens a SQL connection (TCP only, 60s timeout, 3 attempts). Caller disposes it. #>
    $cfg = Get-MeridianConfig
    # "tcp:" skips the named-pipes fallback, which only hides the real TCP error behind "error: 40".
    $server = $cfg.SqlServer
    if ($server -notmatch '^(tcp|np|lpc):') { $server = "tcp:$server" }
    $cs = "Server=$server;Database=$($cfg.SqlDatabase);Application Name=Meridian;Connect Timeout=60;"
    if ($cfg.SqlUser) { $cs += "User ID=$($cfg.SqlUser);Password=$(Get-PlainSecret $cfg.SqlPasswordFile);" }
    else { $cs += 'Integrated Security=SSPI;' }

    $conn = New-Object System.Data.SqlClient.SqlConnection $cs
    for ($attempt = 1; ; $attempt++) {
        try { $conn.Open(); break }
        catch {
            if ($attempt -ge 3) { $conn.Dispose(); throw }
            Write-MeridianLog "SQL connect attempt $attempt failed ($($_.Exception.Message)); retrying in 20s" 'sql' 'WARN'
            Start-Sleep -Seconds 20
        }
    }
    $conn
}

function Invoke-ClockProc {
    <# Runs dbo.usp_StaffMonthlyOTClaim and returns raw DataTable. -Day is optional. #>
    param([Parameter(Mandatory)][int]$Year, [Parameter(Mandatory)][int]$Month, [Nullable[int]]$Day = $null)
    $cfg = Get-MeridianConfig
    $conn = New-MeridianSqlConnection
    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandType = [System.Data.CommandType]::StoredProcedure
        $cmd.CommandText = 'dbo.usp_StaffMonthlyOTClaim'
        $cmd.CommandTimeout = $cfg.SqlTimeoutSec
        [void]$cmd.Parameters.AddWithValue('@Year', $Year)
        [void]$cmd.Parameters.AddWithValue('@Month', $Month)
        if ($null -ne $Day) { [void]$cmd.Parameters.AddWithValue('@Day', [int]$Day) }
        $table = New-Object System.Data.DataTable
        [void](New-Object System.Data.SqlClient.SqlDataAdapter $cmd).Fill($table)
        , $table
    }
    finally { $conn.Dispose() }
}

function Get-ControllerRow {
    <# TCode / TDesc pairs from xpndb.dbo.tbl_controller (one row per door reader, e.g. "DVA JB 2 Out"). #>
    $conn = New-MeridianSqlConnection
    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = 'SELECT TCode, TDesc FROM [xpndb].[dbo].[tbl_controller]'
        $cmd.CommandTimeout = (Get-MeridianConfig).SqlTimeoutSec
        $table = New-Object System.Data.DataTable
        [void](New-Object System.Data.SqlClient.SqlDataAdapter $cmd).Fill($table)
        foreach ($r in $table.Rows) { [pscustomobject]@{ TCode = ([string]$r['TCode']).Trim(); TDesc = ([string]$r['TDesc']).Trim() } }
    }
    finally { $conn.Dispose() }
}

function Get-OwnDoorMap {
    <#
    Center -> set of its own doors (normalised tdesc, "Out"/"In" removed). From tbl_controller: a reader belongs to the
    center named by its TCode once a trailing " Out"/" In" and then a door number are removed. config CenterDoors
    overrides a center explicitly.
    #>
    $cfg = Get-MeridianConfig
    $map = @{}
    $norm = { param($t) (([string]$t) -replace '\s+(Out|In)$', '' -replace '\s+', ' ').Trim().ToUpperInvariant() }
    $addDoor = {
        param($center, $door)
        $k = ([string]$center).Trim().ToUpperInvariant(); $d = & $norm $door
        if (-not $k -or -not $d) { return }
        if (-not $map.ContainsKey($k)) { $map[$k] = @{} }
        $map[$k][$d] = $true
    }
    foreach ($row in (Get-ControllerRow)) {
        $t1 = ($row.TCode -replace '\s+(Out|In)$', '').Trim()
        $t2 = ($t1 -replace '\s+\d+$', '').Trim()
        & $addDoor $t1 $row.TDesc
        if ($t2 -ne $t1) { & $addDoor $t2 $row.TDesc }
    }
    if ($cfg.CenterDoors) {
        foreach ($kv in $cfg.CenterDoors.GetEnumerator()) {
            $k = ([string]$kv.Key).Trim().ToUpperInvariant()
            $map[$k] = @{}
            foreach ($d in @($kv.Value)) { $map[$k][(& $norm $d)] = $true }
        }
    }
    $map
}

function Select-OwnDoorRecord {
    <#
    Keeps a punch for center C only when it happened at one of C's own doors. BranchCode is the staff member's home
    branch, so staff who punch at other centers' doors would otherwise make their home center look active.
    Centers with no controller rows (e.g. SmartPSS) are left untouched. Off when OwnDoorsOnly is not true.
    #>
    param($Records)
    $cfg = Get-MeridianConfig
    $all = @($Records)
    if (-not $cfg.OwnDoorsOnly) { return $all }
    try { $map = Get-OwnDoorMap }
    catch { Write-MeridianLog "Own-door filter skipped (tbl_controller not read): $($_.Exception.Message)" 'meridian' 'WARN'; return $all }
    $kept = foreach ($r in $all) {
        $k = $r.Center.ToUpperInvariant()
        if (-not $map.ContainsKey($k)) { $r; continue }
        $d = (([string]$r.Desc) -replace '\s+(Out|In)$', '' -replace '\s+', ' ').Trim().ToUpperInvariant()
        if ($map[$k].ContainsKey($d)) { $r }
    }
    $kept = @($kept)
    Write-MeridianLog "Own-door filter: kept $($kept.Count) of $($all.Count) punches" 'meridian'
    $kept
}

function ConvertTo-ClockRecord {
    <#
    Normalises proc rows. The two UNION branches return TransDateDDMMYYYY in DIFFERENT formats
    (dd-MM-yyyy from tbl_DailyTransLog, yyyy/MM/dd from SmartPSS), so both are parsed explicitly.
    #>
    param([Parameter(Mandatory)][System.Data.DataTable]$Table)
    $formats = [string[]]@('dd-MM-yyyy', 'yyyy/MM/dd')
    $inv = [Globalization.CultureInfo]::InvariantCulture
    foreach ($r in $Table.Rows) {
        $center = ([string]$r['BranchCode']).Trim()
        $staff = ([string]$r['StaffNo']).Trim()
        if (-not $center -or -not $staff) { continue }
        $d = [datetime]::MinValue
        if (-not [datetime]::TryParseExact(([string]$r['TransDateDDMMYYYY']).Trim(), $formats, $inv, 'None', [ref]$d)) { continue }
        $t = ([string]$r['TransTime']).Trim()
        $ts = [timespan]::Zero
        [void][timespan]::TryParse($t, $inv, [ref]$ts)
        [pscustomobject]@{
            Center   = $center
            StaffNo  = $staff
            Desc     = ([string]$r['tdesc']).Trim()
            Date     = $d.Date
            Time     = $ts
            DateTime = $d.Date + $ts
            Row      = $r
        }
    }
}

function Get-ClockRecord {
    param([int]$Year, [int]$Month, [Nullable[int]]$Day = $null)
    @(ConvertTo-ClockRecord (Invoke-ClockProc -Year $Year -Month $Month -Day $Day))
}

function Resolve-CenterNames {
    <#
    All centers to report, as objects {Name; Desc}. Centers come from -Records plus the previous DiscoverMonths
    months (ending at -Year/-Month) so zero-punch centers still appear, minus ExcludeCenters. Desc = CenterDescriptions override if set, else the doors of that center in tbl_controller, else the distinct
    tdesc / DeviceName values punched by that center (omitted when identical to the name). Case-insensitive.
    A month that cannot be read (e.g. database missing) is skipped with a warning.
    #>
    param($Records, [int]$Year, [int]$Month)
    $cfg = Get-MeridianConfig
    $names = @{}    # KEY -> display name
    $descs = @{}    # KEY -> hashtable of distinct descriptions (key upper -> text)
    $add = {
        param($r)
        $n = ([string]$r.Center).Trim(); if (-not $n) { return }
        $k = $n.ToUpperInvariant()
        if (-not $names.ContainsKey($k)) { $names[$k] = $n; $descs[$k] = @{} }
        $d = ([string]$r.Desc).Trim()
        if ($d -and $d.ToUpperInvariant() -ne $k) { $descs[$k][$d.ToUpperInvariant()] = $d }
    }

    foreach ($r in @($Records)) { & $add $r }

    $months = [int]$cfg.DiscoverMonths
    if ($months -gt 0 -and $Year -and $Month) {
        $base = Get-Date -Year $Year -Month $Month -Day 1
        for ($i = 0; $i -lt $months; $i++) {
            $d = $base.AddMonths(-$i)
            try { foreach ($r in (Get-ClockRecord -Year $d.Year -Month $d.Month)) { & $add $r } }
            catch { Write-MeridianLog "Center discovery skipped $($d.ToString('yyyy-MM')): $($_.Exception.Message)" 'meridian' 'WARN' }
        }
    }

    # Descriptions from tbl_controller: a door belongs to the center whose name equals its TCode once a trailing
    # " Out"/" In" and then a trailing door number are removed ("DVA JB 2 Out" -> "DVA JB 2" -> "DVA JB").
    # Replaces the doors-people-punched list, which also includes other centers' doors.
    $fromCtrl = @{}
    if ($cfg.UseControllerTable) {
        try {
            foreach ($row in (Get-ControllerRow)) {
                $t1 = ($row.TCode -replace '\s+(Out|In)$', '').Trim().ToUpperInvariant()
                $t2 = ($t1 -replace '\s+\d+$', '').Trim()
                $k = if ($names.ContainsKey($t1)) { $t1 } elseif ($names.ContainsKey($t2)) { $t2 } else { $null }
                $d = ($row.TDesc -replace '\s+(Out|In)$', '' -replace '\s+', ' ').Trim()
                if (-not $k -or -not $d) { continue }
                if (-not $fromCtrl.ContainsKey($k)) { $fromCtrl[$k] = @{} }
                $fromCtrl[$k][$d.ToUpperInvariant()] = $d
            }
        }
        catch { Write-MeridianLog "tbl_controller not read, using punched devices instead: $($_.Exception.Message)" 'meridian' 'WARN' }
    }

    $pinned = @{}
    if ($cfg.CenterDescriptions) { foreach ($kv in $cfg.CenterDescriptions.GetEnumerator()) { $pinned[([string]$kv.Key).Trim().ToUpperInvariant()] = ([string]$kv.Value).Trim() } }
    $exclude = @{}
    foreach ($e in @($cfg.ExcludeCenters)) { if ($e) { $exclude[([string]$e).Trim().ToUpperInvariant()] = $true } }
    $names.Keys | Where-Object { -not $exclude.ContainsKey($_) } | Sort-Object | ForEach-Object {
        # CenterDescriptions pins a center to ONE description (an empty string = show the name only).
        $desc = if ($pinned.ContainsKey($_)) { $pinned[$_] }
                elseif ($fromCtrl.ContainsKey($_)) { @($fromCtrl[$_].Values | Sort-Object) -join '; ' }
                else { @($descs[$_].Values | Sort-Object) -join '; ' }
        if ($desc -and $desc.Trim().ToUpperInvariant() -eq $_) { $desc = '' }   # "HQ (HQ)" -> "HQ"
        # PinDesc = only the CenterDescriptions value (no automatic fallback); used by the month-end table.
        $pinDesc = if ($pinned.ContainsKey($_) -and $pinned[$_] -and $pinned[$_].ToUpperInvariant() -ne $_) { $pinned[$_] } else { '' }
        [pscustomobject]@{ Name = $names[$_]; Desc = $desc; PinDesc = $pinDesc }
    }
}

function Format-CenterLabel {
    param([Parameter(Mandatory)]$Center)   # object from Resolve-CenterNames
    if ($Center.Desc) { '{0} ({1})' -f $Center.Name, $Center.Desc } else { $Center.Name }
}

function Get-ListLetter {
    param([int]$Index)   # 0 -> a, 25 -> z, 26 -> aa
    $s = ''
    do { $s = [char](97 + $Index % 26) + $s; $Index = [math]::Floor($Index / 26) - 1 } while ($Index -ge 0)
    $s
}

function Send-MeridianMail {
    param([Parameter(Mandatory)][string]$Subject, [Parameter(Mandatory)][string]$Body, [string]$BodyHtml, [string[]]$Attachments = @(), [switch]$DryRun, [string]$Job = 'meridian')
    $cfg = Get-MeridianConfig
    if ($DryRun) {
        Write-MeridianLog "DRY RUN - not sent. Subject: $Subject" $Job
        Write-Host "`n$Body`n"
        return
    }
    $password = Get-PlainSecret $cfg.SmtpPasswordFile
    for ($attempt = 1; ; $attempt++) {
        # Rebuilt each attempt: a failed send can leave attachment streams unusable.
        $msg = New-Object System.Net.Mail.MailMessage
        $smtp = New-Object System.Net.Mail.SmtpClient $cfg.SmtpHost, $cfg.SmtpPort
        try {
            $msg.From = $cfg.MailFrom
            foreach ($to in $cfg.MailTo) { $msg.To.Add($to) }
            $msg.Subject = $Subject
            # Outlook strips single line breaks from plain-text mail ("We removed extra line breaks"), which
            # flattens the center list. Send HTML with explicit <br> instead; the text is HTML-encoded first.
            # -BodyHtml (pre-built, caller encodes) replaces the plain -Body, which is still used for dry runs.
            $inner = if ($BodyHtml) { $BodyHtml } else { [System.Net.WebUtility]::HtmlEncode($Body) -replace "`r?`n", '<br>' }
            $msg.Body = '<div style="font-family:Segoe UI,Calibri,Arial,sans-serif;font-size:11pt">' + $inner + '</div>'
            $msg.IsBodyHtml = $true
            foreach ($a in $Attachments) { $msg.Attachments.Add((New-Object System.Net.Mail.Attachment $a)) }
            $smtp.EnableSsl = $true
            $smtp.Timeout = 60000
            $smtp.Credentials = New-Object System.Net.NetworkCredential $cfg.SmtpUser, $password
            $smtp.Send($msg)
            Write-MeridianLog "Mail sent: $Subject" $Job
            return
        }
        catch {
            # "Failure sending mail." hides the real reason in the inner exceptions.
            $chain = @(); for ($e = $_.Exception; $e; $e = $e.InnerException) { $chain += $e.Message }
            $detail = $chain -join ' <- '
            if ($attempt -ge 3) { throw "SMTP send failed after $attempt attempts: $detail" }
            Write-MeridianLog "SMTP attempt $attempt failed: $detail; retrying in 30s" $Job 'WARN'
            Start-Sleep -Seconds 30
        }
        finally { $msg.Dispose(); $smtp.Dispose() }
    }
}

function Send-MeridianFailure {
    param([string]$Job, [string]$Error, [switch]$DryRun)
    try {
        Send-MeridianMail -Subject "[Meridian] FAILED: $Job on $env:COMPUTERNAME" -DryRun:$DryRun -Job $Job `
            -Body "Job '$Job' failed at $(Get-Date -Format 'd/M/yyyy HH:mm').`r`n`r`n$Error"
    }
    catch { Write-MeridianLog "Could not send failure mail: $_" $Job 'ERROR' }
}

function Invoke-UniFiGuard {
    <#
    Kills the UniFi desktop UI process (command line contains UniFiCommandMatch) if it holds more than
    UniFiPortThreshold TCP sockets. Called by Watch-UniFiPorts.ps1 (hourly) and at the start of every report
    script so the SQL/SMTP work never runs on an exhausted port range. Never throws: a failure here must not
    stop a report. Does NOT restart UniFi.
    #>
    param([switch]$DryRun)
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
            Start-Sleep -Seconds 5   # let Windows release the ports before any mail is attempted
            try {
                Send-MeridianMail -Job $job -Subject "[Meridian] UniFi killed on $env:COMPUTERNAME" `
                    -Body "$msg`r`n`r`nThe process was stopped to free ephemeral ports. It has NOT been restarted.`r`nTime: $((Get-Date).ToString('d/M/yyyy HH:mm'))"
            }
            catch { Write-MeridianLog "Could not send kill notice: $_" $job 'ERROR' }
        }
    }
    catch { Write-MeridianLog "UniFi guard failed (continuing): $_" $job 'WARN' }
}

Export-ModuleMember -Function *-*
