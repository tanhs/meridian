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

function Invoke-ClockProc {
    <# Runs dbo.usp_StaffMonthlyOTClaim and returns raw DataTable. -Day is optional. #>
    param([Parameter(Mandatory)][int]$Year, [Parameter(Mandatory)][int]$Month, [Nullable[int]]$Day = $null)
    $cfg = Get-MeridianConfig
    # "tcp:" skips the named-pipes fallback, which only hides the real TCP error behind "error: 40".
    $server = $cfg.SqlServer
    if ($server -notmatch '^(tcp|np|lpc):') { $server = "tcp:$server" }
    $cs = "Server=$server;Database=$($cfg.SqlDatabase);Application Name=Meridian;Connect Timeout=60;"
    if ($cfg.SqlUser) { $cs += "User ID=$($cfg.SqlUser);Password=$(Get-PlainSecret $cfg.SqlPasswordFile);" }
    else { $cs += 'Integrated Security=SSPI;' }

    $conn = New-Object System.Data.SqlClient.SqlConnection $cs
    try {
        for ($attempt = 1; ; $attempt++) {
            try { $conn.Open(); break }
            catch {
                if ($attempt -ge 3) { throw }
                Write-MeridianLog "SQL connect attempt $attempt failed ($($_.Exception.Message)); retrying in 20s" 'sql' 'WARN'
                Start-Sleep -Seconds 20
            }
        }
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
    <# Master list from config + any extra centers seen in the data (case-insensitive). Returns display names, sorted. #>
    param($Records)
    $map = @{}
    foreach ($c in @((Get-MeridianConfig).Centers)) { if ($c) { $map[$c.Trim().ToUpperInvariant()] = $c.Trim() } }
    foreach ($r in @($Records)) { $k = $r.Center.ToUpperInvariant(); if (-not $map.ContainsKey($k)) { $map[$k] = $r.Center } }
    $map.Values | Sort-Object
}

function Get-ListLetter {
    param([int]$Index)   # 0 -> a, 25 -> z, 26 -> aa
    $s = ''
    do { $s = [char](97 + $Index % 26) + $s; $Index = [math]::Floor($Index / 26) - 1 } while ($Index -ge 0)
    $s
}

function Send-MeridianMail {
    param([Parameter(Mandatory)][string]$Subject, [Parameter(Mandatory)][string]$Body, [string[]]$Attachments = @(), [switch]$DryRun, [string]$Job = 'meridian')
    $cfg = Get-MeridianConfig
    if ($DryRun) {
        Write-MeridianLog "DRY RUN - not sent. Subject: $Subject" $Job
        Write-Host "`n$Body`n"
        return
    }
    $msg = New-Object System.Net.Mail.MailMessage
    $msg.From = $cfg.MailFrom
    foreach ($to in $cfg.MailTo) { $msg.To.Add($to) }
    $msg.Subject = $Subject
    $msg.Body = $Body
    $msg.IsBodyHtml = $false
    foreach ($a in $Attachments) { $msg.Attachments.Add((New-Object System.Net.Mail.Attachment $a)) }
    $smtp = New-Object System.Net.Mail.SmtpClient $cfg.SmtpHost, $cfg.SmtpPort
    $smtp.EnableSsl = $true
    $smtp.Credentials = New-Object System.Net.NetworkCredential $cfg.SmtpUser, (Get-PlainSecret $cfg.SmtpPasswordFile)
    try { $smtp.Send($msg); Write-MeridianLog "Mail sent: $Subject" $Job }
    finally { $msg.Dispose(); $smtp.Dispose() }
}

function Send-MeridianFailure {
    param([string]$Job, [string]$Error, [switch]$DryRun)
    try {
        Send-MeridianMail -Subject "[Meridian] FAILED: $Job on $env:COMPUTERNAME" -DryRun:$DryRun -Job $Job `
            -Body "Job '$Job' failed at $(Get-Date -Format 'd/M/yyyy HH:mm').`r`n`r`n$Error"
    }
    catch { Write-MeridianLog "Could not send failure mail: $_" $Job 'ERROR' }
}

Export-ModuleMember -Function *-*
