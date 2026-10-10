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
        'NUSG BN'
        # 'HQ'
        # 'TMS_Kuala Lumpur'
    )

    # Descriptions come from xpndb.dbo.tbl_controller (the doors that belong to each center, e.g. TCode 'DVA JB',
    # 'DVA JB 2', 'DVA JB Out'). Centers with no controller rows (e.g. SmartPSS) use the devices that were punched.
    UseControllerTable = $true

    # Pin a center to ONE description in the emails instead of every door its staff have punched at.
    # Key = center name as reported (case-insensitive); value = text shown in brackets. '' = show the name only.
    # Centers not listed here keep the automatic list of devices.
    CenterDescriptions = @{
        'DSS RWG' = 'Rawang'
        'DVA AG' = 'Antara Gapi'
        'DVA JB' = 'Landmark Site Door'
        'DVA KW' = 'Kota Warisan'
        'DVA PB' = 'Pekan Baru'
        'DVA PPR' = 'Papar'
        'DVA SE' = 'Seremban'
        'DVA TS' = 'Tamansari'
        'DVA TSS' = 'Taman Seri Setia'
        'DVA TTJ' = 'Taman Tasik Jaya'
        'DVA TU' = 'Tulips'
        'HQ' = 'HQ'
        'NUSG AS' = 'Alor Setar'
        'NUSG BBU' = 'Bandar Baru Uda'
        'NUSG BG' = 'Bangsar'
        'NUSG BN' = 'Benut'
        'NUSG BR' = 'Batu Berendam'
        'NUSG KJ' = 'Kajang'
        'NUSG KP' = 'Kuala Pilah'
        'NUSG KSB' = 'Kuala Sg Baru'
        'NUSG KT' = 'Kota Tinggi'
        'NUSG MT' = 'Masjid Tanah'
        'NUSG PU' = 'Cheras'
        'NUSG SP' = 'Seberang Perai'
        'NUSG ST' = 'Sri Rampai'
        'QDC AN' = 'Klang'
        'QDC BA' = 'Bangi'
        'QDC BB' = 'Batang Berjuntai'
        'QDC BE' = 'Sungai Besar'
        'QDC CH' = 'Cheras'
        'QDC GU' = 'Gurun'
        'QDC JE' = 'Jerantut'
        'QDC KA' = 'Kangar'
        'QDC KK' = 'Kota Kinabalu'
        'QDC ME' = 'Meru'
        'QDC PE' = 'Pendang'
        'QDC SA' = 'Sandakan'
        'QDC SB' = 'Sabak Bernam'
        'QDC SPU' = 'Sg Petani Utara'
        'QDC SS' = 'Sg Siput'
        'QDC TK' = 'Tanjung Karang'
        'QDC WM' = 'Wangsa Maju'
        'TMS_Benut' = 'TMS_Benut'
        'TMS_Kuala Lumpur' = 'TMS_Kuala Lumpur'
        'TMS_Pontian' = 'TMS_Pontian'
        'TMS_Puchong' = 'TMS_Puchong'
        'TMS_Rembau' = 'TMS_Rembau'
        'TMS_Sungai Petani Selatan' = 'TMS_Sungai Petani Selatan'
        'TMS_Teluk Intan' = 'TMS_Teluk Intan'
    }
}
