@{
    # --- SQL Server (data source) -------------------------------------------
    SqlServer      = '10.234.0.21'
    SqlDatabase    = 'master'          # usp_StaffMonthlyOTClaim lives in master
    SqlUser        = ''                # leave empty = Windows integrated auth (task account)
    SqlPasswordFile = 'C:\overtime\scripts\meridian\sql.cred'   # only used when SqlUser is set
    SqlTimeoutSec  = 600

    # --- SMTP ---------------------------------------------------------------
    SmtpHost       = 'sm09.small-dns.com'
    SmtpPort       = 587               # STARTTLS (EnableSsl); implicit-TLS 465 is NOT supported by SmtpClient
    SmtpUser       = 'no-reply@dvam.com.my'
    SmtpPasswordFile = 'C:\overtime\scripts\meridian\smtp.cred'
    MailFrom       = 'no-reply@dvam.com.my'
    MailTo         = @('APAC_MY_IT_GENERAL@davita.com')

    # --- Paths --------------------------------------------------------------
    BaseDir        = 'C:\overtime\scripts\meridian'
    LogDir         = 'C:\overtime\scripts\meridian\logs'
    OutputDir      = 'C:\overtime\scripts\meridian\output'

    # --- OT claim extract ---------------------------------------------------
    # Window = 1st of previous month @ this hour  ->  1st of this month @ this hour.
    # Set to 0 to extract plain calendar months instead.
    OTCutoffHour   = 3

    # --- Centers ------------------------------------------------------------
    # Master list so centers with ZERO punches still appear in the reports.
    # Must match BranchCode (tbl_DailyTransLog) / DeviceName minus "_TMS" (SmartPSS).
    # Generate the list with .\Get-CenterList.ps1, then paste here. Matching is case-insensitive.
    Centers        = @(
        # 'Bahau'
        # 'Bangsar'
        # 'Chongli'
    )
}
