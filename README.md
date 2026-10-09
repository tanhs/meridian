# meridian

PowerShell + Task Scheduler reports on the clock-in data (SQL Server Express, `10.234.0.21`).
All reports reuse `dbo.usp_StaffMonthlyOTClaim` (source in `stored_procedure.txt`) so there is one definition of "a clock-in".

| Script | What | Schedule |
|---|---|---|
| `Send-DailyClockIn.ps1` | Centers with 0 clock-ins for the day (`-ShowAll` = every center with its unique `StaffNo` count) | daily 23:59 |
| `Send-MonthEndNoClockIn.ps1` | Per center, days of the previous month with 0 clock-ins | 1st, 03:30 |
| `Send-MonthlyOTClaim.ps1` | OT extract as CSV, 1st prev month 03:00 -> 1st this month 03:00 | 1st, 03:00 |
| `Watch-UniFiPorts.ps1` | Kills the UniFi desktop UI process (`ace.jar" ui`, not the headless controller) if it holds >10,000 TCP sockets (socket leak starves SMTP/SQL), emails a notice, does not restart it | hourly at :05 |

The UniFi check also runs at the start of each report script, before any SQL or email work.

All mail goes to `APAC_MY_IT_GENERAL@davita.com`; failures also email that address.

## Server setup (`C:\overtime\scripts\meridian`)
1. `git pull origin claude/vibrant-volta-nn1z4o` (or clone the repo into that folder).
2. SMTP password (once, as the account that will run the tasks):
   `Read-Host "SMTP password" -AsSecureString | ConvertFrom-SecureString | Set-Content C:\overtime\scripts\meridian\smtp.cred`
3. All centers seen in the last `DiscoverMonths` (3) months are reported automatically, zero-punch ones as `- 0`. To hide some, list them in `config.psd1` -> `ExcludeCenters` (`.\Get-CenterList.ps1` shows the names).
4. Test without sending: `.\Send-DailyClockIn.ps1 -DryRun`, then without `-DryRun`.
   `.\Send-MonthEndNoClockIn.ps1 -Year 2026 -Month 9 -DryRun`, `.\Send-MonthlyOTClaim.ps1 -RunDate 2026-10-01 -DryRun`
5. Elevated PowerShell: `.\Register-MeridianTasks.ps1 -RunAsUser DOMAIN\svc_account`

Auth: SQL uses Windows auth of the task account unless `SqlUser` is set in `config.psd1`.
Logs: `logs\`, CSVs: `output\`. The month-end report also deletes files older than `RetentionMonths` (3) from both folders; `-DryRun` only lists what it would delete.

## Data quirks handled
- The proc returns `TransDateDDMMYYYY` as `dd-MM-yyyy` from `tbl_DailyTransLog` but `yyyy/MM/dd` from SmartPSS; both are parsed explicitly.
- Center = `BranchCode` (SmartPSS: `DeviceName` minus `_TMS`), matched case-insensitively; staff = `StaffNo`/`PersonID`.
- The monthly DB `XPNTR<yyyyMM>` must exist, otherwise the proc raises an error and a failure mail is sent.
