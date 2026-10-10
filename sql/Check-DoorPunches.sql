-- Why does a center show no punches on some days?  Run in SSMS against 10.234.0.21.
-- Edit the month DB, the dates and the controller prefix (TCode of the center, e.g. 'NUSG BG' = Davita Bangsar + Out).
-- NOTE: tbl_DailyTransLog.TransDate is TEXT in yyyy/MM/dd form (e.g. '2026/10/02'), so every date test below goes through
--       CONVERT(date, TransDate, 111) and compares with unambiguous yyyymmdd literals.
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
SELECT CONVERT(varchar(10), CONVERT(date, a.TransDate, 111), 120) AS [Day], a.CtrlCode, a.TransCode, a.StaffName, COUNT(*) AS n
FROM   XPNTR202610.dbo.tbl_DailyTransLog a
WHERE  a.CtrlCode LIKE 'NUSG BG%'
  AND  CONVERT(date, a.TransDate, 111) BETWEEN '20261003' AND '20261010'
GROUP  BY CONVERT(varchar(10), CONVERT(date, a.TransDate, 111), 120), a.CtrlCode, a.TransCode, a.StaffName
ORDER  BY 1, 2, 3, 4;

-- 4) Is the whole feed alive?  Transactions per day across ALL controllers
SELECT CONVERT(varchar(10), CONVERT(date, TransDate, 111), 120) AS [Day], COUNT(*) AS Transactions
FROM   XPNTR202610.dbo.tbl_DailyTransLog
WHERE  CONVERT(date, TransDate, 111) >= '20261001'
GROUP  BY CONVERT(varchar(10), CONVERT(date, TransDate, 111), 120)
ORDER  BY 1;

-- 4b) Which TransCodes exist?  The stored procedure only counts 'P0' and 'Pi'; anything else (e.g. 'SK') is dropped.
SELECT TransCode, COUNT(*) AS Transactions, MIN(TransDate) AS FirstDate, MAX(TransDate) AS LastDate
FROM   XPNTR202610.dbo.tbl_DailyTransLog
GROUP  BY TransCode
ORDER  BY Transactions DESC;

-- 4c) The non-P0/Pi rows at the center's controllers (who, when, which reader)
SELECT TOP 200 *
FROM   XPNTR202610.dbo.tbl_DailyTransLog
WHERE  CtrlCode LIKE 'NUSG BG%' AND TransCode NOT IN ('P0', 'Pi')
ORDER  BY TransDate, TransTime;

-- 4d) Is there a lookup table that explains the TransCodes?
SELECT TABLE_CATALOG, TABLE_NAME FROM xpndb.INFORMATION_SCHEMA.TABLES
WHERE  TABLE_NAME LIKE '%code%' OR TABLE_NAME LIKE '%trans%';

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
