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

    # Files in LogDir / OutputDir older than this many months are deleted by the month-end report.
    RetentionMonths = 3

    # --- UniFi socket-leak watchdog (Watch-UniFiPorts.ps1) -------------------
    UniFiPortThreshold = 10000          # kill UniFi when it holds more TCP sockets than this
    # Only java/javaw processes whose command line contains this (substring, quote included).
    # 'ace.jar" ui' = the desktop UI window only; the headless controller ('ace.jar" start') is never touched.
    UniFiCommandMatch  = 'ace.jar" ui'

    # --- OT claim extract ---------------------------------------------------
    # Window = 1st of previous month @ this hour  ->  1st of this month @ this hour.
    # Set to 0 to extract plain calendar months instead.
    OTCutoffHour   = 3

    # --- Centers ------------------------------------------------------------
    # By default ALL centers are reported: every BranchCode / DeviceName (minus "_TMS") seen in the clock data
    # of the last DiscoverMonths months, so a center with 0 punches today still shows as "- 0".
    DiscoverMonths = 3                 # 0 = only centers that have punches in the report period

    # Centers listed here are HIDDEN from the daily and month-end reports (the OT claim CSV is never filtered).
    # Must match the name exactly as reported; case-insensitive. Empty list = hide nothing.
    ExcludeCenters = @(
        # 'HQ'
        # 'TMS_Kuala Lumpur'
    )

    # Pin a center to ONE description in the emails instead of every door its staff have punched at.
    # Key = center name as reported (case-insensitive); value = text shown in brackets. '' = show the name only.
    # Centers not listed here keep the automatic list of devices.
    CenterDescriptions = @{
        # 'QDC PE' = 'Davita Pendang'
    }
}
