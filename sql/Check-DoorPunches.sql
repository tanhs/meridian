-- Why does a center show no punches on some days?  Run in SSMS against 10.234.0.21.
-- Edit the month DB, the dates and the controller prefix (TCode of the center, e.g. 'NUSG BG' = Davita Bangsar + Out).
-- These queries read the raw tables, so they show what the reports' filters (TransCode P0/Pi, not 'Unlisted User',
-- controller must exist in tbl_controller) hide.

-- 1) The center's controllers (door readers) as the reports see them
SELECT TCode, TDesc
FROM   xpndb.dbo.tbl_controller
WHERE  TCode LIKE 'NUSG BG%'
ORDER  BY TCode;

-- 2) When did each of those controllers last report this month?  (a last date of 02/10 = the reader stopped sending)
SELECT a.CtrlCode, MAX(a.TransDate) AS LastDate, MAX(a.TransTime) AS LastTime, COUNT(*) AS Transactions
FROM   XPNTR202610.dbo.tbl_DailyTransLog a
WHERE  a.CtrlCode LIKE 'NUSG BG%'
GROUP  BY a.CtrlCode;

-- 3) Everything at those controllers 3-10 Oct, ANY TransCode and ANY staff (the report only counts TransCode P0/Pi
--    and drops StaffName 'Unlisted User')
SELECT CONVERT(varchar(10), a.TransDate, 120) AS [Day], a.CtrlCode, a.TransCode, a.StaffName, COUNT(*) AS n
FROM   XPNTR202610.dbo.tbl_DailyTransLog a
WHERE  a.CtrlCode LIKE 'NUSG BG%'
  AND  a.TransDate >= '2026-10-03' AND a.TransDate < '2026-10-11'
GROUP  BY CONVERT(varchar(10), a.TransDate, 120), a.CtrlCode, a.TransCode, a.StaffName
ORDER  BY 1, 2, 3, 4;

-- 4) Is the whole feed alive?  Transactions per day across ALL controllers
SELECT CONVERT(varchar(10), TransDate, 120) AS [Day], COUNT(*) AS Transactions
FROM   XPNTR202610.dbo.tbl_DailyTransLog
WHERE  TransDate >= '2026-10-01'
GROUP  BY CONVERT(varchar(10), TransDate, 120)
ORDER  BY 1;

-- 5) Controller codes seen in the log that tbl_controller does not know (their punches are dropped by the proc's join)
SELECT a.CtrlCode, COUNT(*) AS Transactions
FROM   XPNTR202610.dbo.tbl_DailyTransLog a
WHERE  NOT EXISTS (SELECT 1 FROM xpndb.dbo.tbl_controller b
                   WHERE a.CtrlCode COLLATE SQL_Latin1_General_CP1_CI_AS = b.TCode)
GROUP  BY a.CtrlCode
ORDER  BY 2 DESC;

-- 6) What the stored procedure itself returns for one day (the report's source), filtered to the Bangsar doors
CREATE TABLE #p (TransID nvarchar(100), TransDate nvarchar(30), TransTime nvarchar(30), BranchCode nvarchar(100),
                 tdesc nvarchar(200), StaffName nvarchar(200), StaffNo nvarchar(100));
INSERT #p EXEC master.dbo.usp_StaffMonthlyOTClaim @Year = 2026, @Month = 10, @Day = 3;
SELECT BranchCode, tdesc, COUNT(*) AS Punches FROM #p
WHERE  tdesc LIKE 'Davita Bangsar%' OR BranchCode = 'NUSG BG'
GROUP  BY BranchCode, tdesc;
DROP TABLE #p;
