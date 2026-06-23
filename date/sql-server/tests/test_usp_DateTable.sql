/*
=====================================================================
    test_usp_DateTable.sql
    Regression tests for dbo.usp_DateTable (weekly-fiscal boundary fix
    + hardening guards).

    HOW TO RUN
        1. Deploy ..\usp_DateTable.sql first.
        2. Run this file in SSMS or:  sqlcmd -b -i test_usp_DateTable.sql
           (-b makes sqlcmd return a non-zero exit code on failure, so CI
            fails the build.)

    OUTPUT
        On success: prints 'ALL TESTS PASSED'.
        On failure: returns a result set of the failed assertions and THROWs.

    DESIGN
        - GOLDEN checks (section A) pin the exact values that were verified
          against the Python reference implementation and a live server,
          including the leading/trailing partial fiscal periods that the
          original groupby/window logic clipped.
        - INVARIANT checks are config-agnostic identities of a 4-4-5 calendar
          (day-of-period in range, start+length-1=end, contiguity, valid
          period lengths). They catch a broad class of regressions on ANY
          configuration, which is why section B reuses them on a different
          quarter pattern and a span that includes 53-week fiscal years.
        - NEGATIVE checks (section V) assert the validation guards raise.
=====================================================================
*/
SET NOCOUNT ON;

IF OBJECT_ID('tempdb..#Fail') IS NOT NULL DROP TABLE #Fail;
CREATE TABLE #Fail (TestName nvarchar(200), Detail nvarchar(400));

-- Start clean even if a previous run aborted before its own cleanup.
IF OBJECT_ID('dbo.DimDate_Test') IS NOT NULL DROP TABLE dbo.DimDate_Test;

/*  Each assertion below INSERTs a row into #Fail ONLY when it fails, so a
    clean run leaves #Fail empty. Single-row golden checks filter to the probe
    date; whole-table invariants aggregate and use HAVING COUNT(*) > 0 to emit
    at most one summary row per invariant.                                    */

---------------------------------------------------------------------
-- CONFIG A: 445 / Last / Sunday weeks / FY=Jan, starting AND ending
--           mid-fiscal-month (the case the bug clipped).
---------------------------------------------------------------------
EXEC dbo.usp_DateTable
    @StartDate           = '2021-03-10',
    @EndDate             = '2024-12-31',
    @AsOfDate            = '2024-12-31',
    @FiscalStartMonth    = 1,
    @IncludeWeeklyFiscal = 1,
    @FirstDayOfWeek      = 0,
    @WeeklyType          = 'Last',
    @QuarterWeekType     = '445',
    @ColumnNamingStyle   = 'PascalCase',
    @OutputTable         = 'dbo.DimDate_Test';

-- Probe dates must exist (golden checks below filter on them, so a missing
-- row would otherwise pass silently).
INSERT INTO #Fail
SELECT 'A: probe dates present', CONCAT('found ', COUNT(*), ' of 6 expected')
FROM dbo.DimDate_Test
WHERE [Date] IN ('2021-03-10','2021-03-28','2024-12-28','2024-12-29','2024-12-31','2023-01-29')
HAVING COUNT(*) <> 6;

-- A.G1  Leading partial month/quarter are NOT clipped to the table start.
INSERT INTO #Fail
SELECT 'A.G1: leading partial period (2021-03-10)',
       CONCAT('SoM=', CONVERT(char(10),FWStartOfMonth,23),
              ' EoM=', CONVERT(char(10),FWEndOfMonth,23),
              ' DoM=', FWDayOfMonth,
              ' SoQ=', CONVERT(char(10),FWStartOfQuarter,23),
              ' DoQ=', FWDayOfQuarter,
              ' Lbl=', FWMonthLabel)
FROM dbo.DimDate_Test
WHERE [Date] = '2021-03-10'
  AND NOT ( FWStartOfMonth   = '2021-02-21'
        AND FWEndOfMonth     = '2021-03-27'
        AND FWDayOfMonth     = 18
        AND FWStartOfQuarter = '2020-12-27'
        AND FWDayOfQuarter   = 74
        AND FWMonthLabel     = 'FM Mar - 2021' );

-- A.G2  Month boundary flips cleanly: 2021-03-28 is day 1 of the next FM.
INSERT INTO #Fail
SELECT 'A.G2: month rolls over (2021-03-28)',
       CONCAT('SoM=', CONVERT(char(10),FWStartOfMonth,23), ' DoM=', FWDayOfMonth)
FROM dbo.DimDate_Test
WHERE [Date] = '2021-03-28'
  AND NOT (FWStartOfMonth = '2021-03-28' AND FWDayOfMonth = 1);

-- A.G3  Trailing partial month reports its TRUE end past @EndDate.
INSERT INTO #Fail
SELECT 'A.G3: trailing partial month (2024-12-29..31)',
       CONCAT('29:SoM=', CONVERT(char(10),MAX(CASE WHEN [Date]='2024-12-29' THEN FWStartOfMonth END),23),
              ' EoM=', CONVERT(char(10),MAX(CASE WHEN [Date]='2024-12-29' THEN FWEndOfMonth END),23),
              ' 31:DoM=', MAX(CASE WHEN [Date]='2024-12-31' THEN FWDayOfMonth END))
FROM dbo.DimDate_Test
WHERE [Date] IN ('2024-12-29','2024-12-31')
HAVING NOT ( MAX(CASE WHEN [Date]='2024-12-29' THEN FWDayOfMonth END) = 1
         AND MAX(CASE WHEN [Date]='2024-12-29' THEN FWStartOfMonth END) = '2024-12-29'
         AND MAX(CASE WHEN [Date]='2024-12-29' THEN FWEndOfMonth END) = '2025-01-25'
         AND MAX(CASE WHEN [Date]='2024-12-31' THEN FWDayOfMonth END) = 3 );

-- A.G4  Interior month is unchanged (golden 4-week month: Jan 2023).
INSERT INTO #Fail
SELECT 'A.G4: interior month (2023-01-28 / 29)',
       CONCAT('28:SoM=', CONVERT(char(10),MAX(CASE WHEN [Date]='2023-01-28' THEN FWStartOfMonth END),23),
              ' DoM=', MAX(CASE WHEN [Date]='2023-01-28' THEN FWDayOfMonth END),
              ' 29:DoM=', MAX(CASE WHEN [Date]='2023-01-29' THEN FWDayOfMonth END))
FROM dbo.DimDate_Test
WHERE [Date] IN ('2023-01-28','2023-01-29')
HAVING NOT ( MAX(CASE WHEN [Date]='2023-01-28' THEN FWStartOfMonth END) = '2023-01-01'
         AND MAX(CASE WHEN [Date]='2023-01-28' THEN FWEndOfMonth END) = '2023-01-28'
         AND MAX(CASE WHEN [Date]='2023-01-28' THEN FWDayOfMonth END) = 28
         AND MAX(CASE WHEN [Date]='2023-01-29' THEN FWDayOfMonth END) = 1 );

-- A.I1  Row count = day span.
INSERT INTO #Fail
SELECT 'A.I1: row count = DATEDIFF+1', CONCAT('rows=', COUNT(*))
FROM dbo.DimDate_Test
HAVING COUNT(*) <> DATEDIFF(DAY, '2021-03-10', '2024-12-31') + 1;

-- A.I2  No duplicate or missing days; range endpoints correct.
INSERT INTO #Fail
SELECT 'A.I2: dates unique and span exact', 'min/max/distinct mismatch'
FROM dbo.DimDate_Test
HAVING MIN([Date]) <> '2021-03-10'
    OR MAX([Date]) <> '2024-12-31'
    OR COUNT(DISTINCT [Date]) <> COUNT(*);

-- A.I3  Day-of-month within the real period length (core clipping guard).
INSERT INTO #Fail
SELECT 'A.I3: FWDayOfMonth in [1,FWMonthDays]',
       CONCAT(COUNT(*), ' bad, first=', CONVERT(char(10),MIN([Date]),23))
FROM dbo.DimDate_Test
WHERE FWDayOfMonth NOT BETWEEN 1 AND FWMonthDays
HAVING COUNT(*) > 0;

-- A.I4  Day-of-quarter within the real period length.
INSERT INTO #Fail
SELECT 'A.I4: FWDayOfQuarter in [1,FWQuarterDays]',
       CONCAT(COUNT(*), ' bad, first=', CONVERT(char(10),MIN([Date]),23))
FROM dbo.DimDate_Test
WHERE FWDayOfQuarter NOT BETWEEN 1 AND FWQuarterDays
HAVING COUNT(*) > 0;

-- A.I5  Boundaries self-consistent: end = start + length - 1.
INSERT INTO #Fail
SELECT 'A.I5: FWEndOfMonth = start + FWMonthDays - 1',
       CONCAT(COUNT(*), ' bad, first=', CONVERT(char(10),MIN([Date]),23))
FROM dbo.DimDate_Test
WHERE DATEADD(DAY, FWMonthDays - 1, FWStartOfMonth) <> FWEndOfMonth
   OR DATEADD(DAY, FWQuarterDays - 1, FWStartOfQuarter) <> FWEndOfQuarter
HAVING COUNT(*) > 0;

-- A.I6  Start derives from the date and day-of-period.
INSERT INTO #Fail
SELECT 'A.I6: FWStartOfMonth = Date - (FWDayOfMonth-1)',
       CONCAT(COUNT(*), ' bad, first=', CONVERT(char(10),MIN([Date]),23))
FROM dbo.DimDate_Test
WHERE DATEADD(DAY, -(FWDayOfMonth - 1), [Date]) <> FWStartOfMonth
   OR DATEADD(DAY, -(FWDayOfQuarter - 1), [Date]) <> FWStartOfQuarter
HAVING COUNT(*) > 0;

-- A.I7  Day-of-month = 1 exactly when the row is the month's start.
INSERT INTO #Fail
SELECT 'A.I7: FWDayOfMonth=1 iff Date=FWStartOfMonth', CONCAT(COUNT(*), ' mismatch')
FROM dbo.DimDate_Test
WHERE CASE WHEN [Date] = FWStartOfMonth THEN 1 ELSE 0 END
   <> CASE WHEN FWDayOfMonth = 1 THEN 1 ELSE 0 END
HAVING COUNT(*) > 0;

-- A.I8  Day-of-month increments by 1 between consecutive days of the same month.
INSERT INTO #Fail
SELECT 'A.I8: FWDayOfMonth contiguous within month',
       CONCAT(COUNT(*), ' break(s), first=', CONVERT(char(10),MIN(b.[Date]),23))
FROM dbo.DimDate_Test a
JOIN dbo.DimDate_Test b ON b.[Date] = DATEADD(DAY, 1, a.[Date])
WHERE b.FWMonthIndex = a.FWMonthIndex AND b.FWDayOfMonth <> a.FWDayOfMonth + 1
HAVING COUNT(*) > 0;

-- A.I9  Valid 4-4-5 period lengths; the 53rd week only extends Q4.
INSERT INTO #Fail
SELECT 'A.I9: period lengths valid (28/35/42, 91/98, 364/371)',
       CONCAT(COUNT(*), ' bad, first=', CONVERT(char(10),MIN([Date]),23))
FROM dbo.DimDate_Test
WHERE FWMonthDays % 7 <> 0 OR FWMonthDays NOT BETWEEN 28 AND 42
   OR FWQuarterDays NOT IN (91, 98)
   OR FWYearDays    NOT IN (364, 371)
   OR (FWQuarterDays = 98 AND FWQuarterNumber <> 4)
HAVING COUNT(*) > 0;

---------------------------------------------------------------------
-- CONFIG B: 544 / Last / Sunday weeks, long span including 53-week
--           years. Invariants only (no hand-typed values needed).
---------------------------------------------------------------------
EXEC dbo.usp_DateTable
    @StartDate           = '2010-06-15',
    @EndDate             = '2035-07-20',
    @AsOfDate            = '2025-01-01',
    @FiscalStartMonth    = 1,
    @IncludeWeeklyFiscal = 1,
    @FirstDayOfWeek      = 0,
    @WeeklyType          = 'Last',
    @QuarterWeekType     = '544',
    @ColumnNamingStyle   = 'PascalCase',
    @OutputTable         = 'dbo.DimDate_Test';

INSERT INTO #Fail
SELECT 'B.I3: FWDayOfMonth in [1,FWMonthDays]',
       CONCAT(COUNT(*), ' bad, first=', CONVERT(char(10),MIN([Date]),23))
FROM dbo.DimDate_Test
WHERE FWDayOfMonth NOT BETWEEN 1 AND FWMonthDays HAVING COUNT(*) > 0;

INSERT INTO #Fail
SELECT 'B.I5: FWEndOfMonth/Quarter = start + length - 1',
       CONCAT(COUNT(*), ' bad, first=', CONVERT(char(10),MIN([Date]),23))
FROM dbo.DimDate_Test
WHERE DATEADD(DAY, FWMonthDays - 1, FWStartOfMonth) <> FWEndOfMonth
   OR DATEADD(DAY, FWQuarterDays - 1, FWStartOfQuarter) <> FWEndOfQuarter
HAVING COUNT(*) > 0;

INSERT INTO #Fail
SELECT 'B.I8: FWDayOfMonth contiguous within month',
       CONCAT(COUNT(*), ' break(s), first=', CONVERT(char(10),MIN(b.[Date]),23))
FROM dbo.DimDate_Test a
JOIN dbo.DimDate_Test b ON b.[Date] = DATEADD(DAY, 1, a.[Date])
WHERE b.FWMonthIndex = a.FWMonthIndex AND b.FWDayOfMonth <> a.FWDayOfMonth + 1
HAVING COUNT(*) > 0;

INSERT INTO #Fail
SELECT 'B.I9: period lengths valid + 53rd week only in Q4',
       CONCAT(COUNT(*), ' bad, first=', CONVERT(char(10),MIN([Date]),23))
FROM dbo.DimDate_Test
WHERE FWMonthDays % 7 <> 0 OR FWMonthDays NOT BETWEEN 28 AND 42
   OR FWQuarterDays NOT IN (91, 98)
   OR FWYearDays    NOT IN (364, 371)
   OR (FWQuarterDays = 98 AND FWQuarterNumber <> 4)
HAVING COUNT(*) > 0;

-- B.53  At least one 53-week fiscal year must appear in this 25-year span,
--       otherwise the long-year branch is never exercised by the suite.
INSERT INTO #Fail
SELECT 'B.53: span exercises a 53-week year', 'no FWYearDays=371 found'
FROM dbo.DimDate_Test
HAVING SUM(CASE WHEN FWYearDays = 371 THEN 1 ELSE 0 END) = 0;

---------------------------------------------------------------------
-- NEGATIVE: the validation guards must raise (each EXEC should error).
---------------------------------------------------------------------
-- Each guard must raise AND raise for the right reason: the CATCH asserts the
-- specific guard message, so a regression that removes a guard but errors
-- elsewhere does not pass silently.
BEGIN TRY
    EXEC dbo.usp_DateTable @StartDate='2025-12-31', @EndDate='2025-01-01', @AsOfDate='2025-06-01';
    INSERT INTO #Fail VALUES ('V1: reversed range rejected', 'no error raised');
END TRY BEGIN CATCH
    IF ERROR_MESSAGE() NOT LIKE '%must be on or after%'
        INSERT INTO #Fail VALUES ('V1: reversed range rejected', 'wrong error: ' + ERROR_MESSAGE());
END CATCH;

BEGIN TRY
    EXEC dbo.usp_DateTable @StartDate='0001-01-01', @EndDate='9999-12-31', @AsOfDate='2025-06-01';
    INSERT INTO #Fail VALUES ('V2: over-capacity range rejected', 'no error raised');
END TRY BEGIN CATCH
    IF ERROR_MESSAGE() NOT LIKE '%capacity%'
        INSERT INTO #Fail VALUES ('V2: over-capacity range rejected', 'wrong error: ' + ERROR_MESSAGE());
END CATCH;

BEGIN TRY
    EXEC dbo.usp_DateTable @StartDate='2025-01-01', @EndDate='2025-12-31'; -- @AsOfDate omitted
    INSERT INTO #Fail VALUES ('V3: missing @AsOfDate rejected', 'no error raised');
END TRY BEGIN CATCH
    IF ERROR_MESSAGE() NOT LIKE '%required%'
        INSERT INTO #Fail VALUES ('V3: missing @AsOfDate rejected', 'wrong error: ' + ERROR_MESSAGE());
END CATCH;

BEGIN TRY
    EXEC dbo.usp_DateTable @StartDate='2025-01-01', @EndDate='2025-12-31', @AsOfDate='2025-06-01',
        @OutputTable='a.b.c.d.e';
    INSERT INTO #Fail VALUES ('V4: malformed @OutputTable rejected', 'no error raised');
END TRY BEGIN CATCH
    IF ERROR_MESSAGE() NOT LIKE '%Invalid @OutputTable%'
        INSERT INTO #Fail VALUES ('V4: malformed @OutputTable rejected', 'wrong error: ' + ERROR_MESSAGE());
END CATCH;

-- V5: an empty schema part must be rejected. Depending on PARSENAME it is caught
-- either up front ('Invalid @OutputTable name') or by the failing SELECT INTO
-- inside the proc's own TRY/CATCH; either way it must raise rather than silently
-- create a mis-named table, so here we only require that it threw.
BEGIN TRY
    EXEC dbo.usp_DateTable @StartDate='2025-01-01', @EndDate='2025-12-31', @AsOfDate='2025-06-01',
        @OutputTable='.DimDate'; -- empty schema part
    INSERT INTO #Fail VALUES ('V5: empty-part @OutputTable rejected', 'no error raised');
END TRY BEGIN CATCH END CATCH;

---------------------------------------------------------------------
-- Cleanup + report
---------------------------------------------------------------------
IF OBJECT_ID('dbo.DimDate_Test') IS NOT NULL DROP TABLE dbo.DimDate_Test;

DECLARE @failCount int = (SELECT COUNT(*) FROM #Fail);
IF @failCount > 0
BEGIN
    SELECT TestName, Detail FROM #Fail ORDER BY TestName;
    DECLARE @msg nvarchar(200) = CONCAT(@failCount, ' usp_DateTable test(s) FAILED (see result set).');
    DROP TABLE #Fail;
    THROW 51000, @msg, 1;
END
ELSE
BEGIN
    DROP TABLE #Fail;
    PRINT 'ALL TESTS PASSED';
END
