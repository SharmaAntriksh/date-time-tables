/*
    usp_DateTable
    Generates a complete date dimension table.

    T-SQL equivalent of the Power Query fn_DateTable / fn_Orchestrate functions.
    Phases: base calendar, ISO weeks, monthly fiscal, and optional weekly fiscal (4-4-5).

    Parameters:
        @StartDate            date        - First date in the table
        @EndDate              date        - Last date in the table
        @AsOfDate             date        - Reference date for all relative offsets
        @FiscalStartMonth     int         - First month of fiscal year (1-12)
        @IncludeWeeklyFiscal  bit         - 1 to include 4-4-5 weekly fiscal columns
        @FirstDayOfWeek       int         - 0=Sunday .. 6=Saturday (weekly fiscal)
        @WeeklyType           nvarchar(10)- 'Last' or 'Nearest' (weekly fiscal)
        @QuarterWeekType      nvarchar(3) - '445', '454', or '544' (weekly fiscal)
        @TypeStartFiscalYear  int         - 0=start-year, 1=end-year labeling (weekly fiscal)
        @ColumnNamingStyle    nvarchar(20)- 'Spaced' (default) or 'PascalCase'
        @OutputTable          nvarchar(256)- NULL (default) returns result set;
                                             if set, creates a persistent table (e.g. 'dbo.DateTable').
                                             Errors if the table already exists.

    Usage:
        -- Return as result set:
        EXEC dbo.usp_DateTable
            @StartDate           = '2021-01-01',
            @EndDate             = '2026-12-31',
            @AsOfDate            = '2025-03-31',
            @FiscalStartMonth    = 5,
            @IncludeWeeklyFiscal = 1,
            @FirstDayOfWeek      = 0,
            @WeeklyType          = 'Last',
            @QuarterWeekType     = '445',
            @TypeStartFiscalYear = 1;

        -- Persist to a table:
        EXEC dbo.usp_DateTable
            @StartDate           = '2021-01-01',
            @EndDate             = '2026-12-31',
            @AsOfDate            = '2025-03-31',
            @FiscalStartMonth    = 5,
            @IncludeWeeklyFiscal = 0,
            @OutputTable         = 'dbo.DimDate';
*/
CREATE OR ALTER PROCEDURE dbo.usp_DateTable
    @StartDate            date         = NULL,
    @EndDate              date         = NULL,
    @AsOfDate             date         = NULL,
    @FiscalStartMonth     int          = 1,
    @IncludeWeeklyFiscal  bit          = 0,
    @FirstDayOfWeek       int          = 0,
    @WeeklyType           nvarchar(10) = N'Last',
    @QuarterWeekType      nvarchar(3)  = N'445',
    @TypeStartFiscalYear  int          = 0,
    @ColumnNamingStyle    nvarchar(20)  = N'Spaced',
    @OutputTable          nvarchar(256) = NULL,
    @Help                 bit           = 0
AS
BEGIN
    SET NOCOUNT ON;

    ---------------------------------------------------------------------------
    -- Help
    ---------------------------------------------------------------------------
    IF @Help = 1
    BEGIN
        PRINT '
usp_DateTable - Generates a complete date dimension table.

USAGE:
    -- Return as result set (minimal):
    EXEC dbo.usp_DateTable
        @StartDate = ''2021-01-01'',
        @EndDate   = ''2026-12-31'',
        @AsOfDate  = ''2025-03-31'';

    -- With fiscal year starting in May:
    EXEC dbo.usp_DateTable
        @StartDate        = ''2021-01-01'',
        @EndDate          = ''2026-12-31'',
        @AsOfDate         = ''2025-03-31'',
        @FiscalStartMonth = 5;

    -- Full weekly fiscal (4-4-5):
    EXEC dbo.usp_DateTable
        @StartDate           = ''2021-01-01'',
        @EndDate             = ''2026-12-31'',
        @AsOfDate            = ''2025-03-31'',
        @FiscalStartMonth    = 5,
        @IncludeWeeklyFiscal = 1,
        @FirstDayOfWeek      = 0,
        @WeeklyType          = ''Last'',
        @QuarterWeekType     = ''445'',
        @TypeStartFiscalYear = 1;

    -- Persist to a table:
    EXEC dbo.usp_DateTable
        @StartDate        = ''2021-01-01'',
        @EndDate          = ''2026-12-31'',
        @AsOfDate         = ''2025-03-31'',
        @FiscalStartMonth = 5,
        @OutputTable      = ''dbo.DimDate'';

PARAMETERS:
    @StartDate            date          First date in the table (required)
    @EndDate              date          Last date in the table (required)
    @AsOfDate             date          Reference date for relative offsets (required)
    @FiscalStartMonth     int = 1       First month of fiscal year (1-12)
    @IncludeWeeklyFiscal  bit = 0       1 to include 4-4-5 weekly fiscal columns
    @FirstDayOfWeek       int = 0       0=Sunday .. 6=Saturday (weekly fiscal)
    @WeeklyType           nvarchar = Last    ''Last'' or ''Nearest'' (weekly fiscal)
    @QuarterWeekType      nvarchar = 445     ''445'', ''454'', or ''544'' (weekly fiscal)
    @TypeStartFiscalYear  int = 0       0=start-year, 1=end-year labeling (weekly fiscal)
    @ColumnNamingStyle    nvarchar = Spaced  ''Spaced'' or ''PascalCase''
    @OutputTable          nvarchar = NULL    NULL returns result set; set to create
                                             a persistent table (e.g. ''dbo.DimDate'').
                                             Errors if the table already exists.
    @Help                 bit = 0       1 to show this help text
';
        RETURN;
    END;

    ---------------------------------------------------------------------------
    -- Required parameter validation
    ---------------------------------------------------------------------------
    IF @StartDate IS NULL OR @EndDate IS NULL OR @AsOfDate IS NULL
    BEGIN
        RAISERROR(N'@StartDate, @EndDate, and @AsOfDate are required. Run with @Help = 1 for usage.', 16, 1);
        RETURN; -- no temp tables created yet, nothing to clean up
    END;

    ---------------------------------------------------------------------------
    -- Parameter normalization
    ---------------------------------------------------------------------------
    DECLARE @FYStartMonth int = CASE
        WHEN @FiscalStartMonth < 1  THEN 1
        WHEN @FiscalStartMonth > 12 THEN 12
        ELSE @FiscalStartMonth END;

    DECLARE @FYEndAdd int = CASE WHEN @FYStartMonth = 1 THEN 0 ELSE 1 END;

    -- Weekly fiscal parameter normalization
    DECLARE @FDOW    int          = @FirstDayOfWeek % 7;
    DECLARE @WType   nvarchar(10) = CASE WHEN UPPER(LTRIM(RTRIM(@WeeklyType))) = 'NEAREST' THEN N'Nearest' ELSE N'Last' END;
    DECLARE @QWT     nvarchar(3)  = CASE WHEN LTRIM(RTRIM(@QuarterWeekType)) IN ('445','454','544') THEN LTRIM(RTRIM(@QuarterWeekType)) ELSE '445' END;
    DECLARE @TSY     int          = CASE WHEN @TypeStartFiscalYear = 0 THEN 0 ELSE 1 END;
    DECLARE @W1      int          = CAST(SUBSTRING(@QWT, 1, 1) AS int);
    DECLARE @W2      int          = CAST(SUBSTRING(@QWT, 2, 1) AS int);

    DECLARE @WFLabel nvarchar(30) = CASE
        WHEN @IncludeWeeklyFiscal = 1
            THEN N'Weekly (' + LTRIM(RTRIM(@QWT)) + N' ' + @WType + N')'
        ELSE N'' END;

    ---------------------------------------------------------------------------
    -- As-of reference values
    ---------------------------------------------------------------------------
    -- Calendar
    DECLARE @AsOfCalMonthIndex   int = YEAR(@AsOfDate) * 12 + MONTH(@AsOfDate);
    DECLARE @AsOfCalQuarterIndex int = YEAR(@AsOfDate) * 4  + DATEPART(QUARTER, @AsOfDate);

    -- ISO: anchor is Monday of ISO week 1 in year 2000 (any Monday works)
    DECLARE @ISOWeekRef       date = '2000-01-03';
    DECLARE @AsOfISOWeekStart date = CAST(DATEADD(DAY, -(DATEDIFF(DAY, 0, @AsOfDate) % 7), @AsOfDate) AS date);
    DECLARE @AsOfISOWeekIndex int  = DATEDIFF(DAY, @ISOWeekRef, @AsOfISOWeekStart) / 7;

    -- Monthly fiscal
    DECLARE @AsOfFYStartYear   int = CASE WHEN MONTH(@AsOfDate) >= @FYStartMonth THEN YEAR(@AsOfDate) ELSE YEAR(@AsOfDate) - 1 END;
    DECLARE @AsOfFiscalMonth   int = ((MONTH(@AsOfDate) - @FYStartMonth + 12) % 12) + 1;
    DECLARE @AsOfFiscalQtr     int = (@AsOfFiscalMonth - 1) / 3 + 1;
    DECLARE @AsOfFiscalMoIdx   int = @AsOfFYStartYear * 12 + @AsOfFiscalMonth;
    DECLARE @AsOfFiscalQtrIdx  int = @AsOfFYStartYear * 4  + @AsOfFiscalQtr;

    ---------------------------------------------------------------------------
    -- Create result table
    ---------------------------------------------------------------------------
    CREATE TABLE #DateTable (
        -- Phase 1: Base Calendar
        [Date]                  date        NOT NULL PRIMARY KEY,
        [Year]                  int         NOT NULL,
        [Month]                 int         NOT NULL,
        [Day]                   int         NOT NULL,
        [Quarter]               int         NOT NULL,
        [DateKey]               bigint      NOT NULL,
        [DateSerialNumber]      int         NOT NULL,
        [MonthName]             nvarchar(20) NOT NULL,
        [MonthShort]            nvarchar(3)  NOT NULL,
        [DayName]               nvarchar(20) NOT NULL,
        [DayShort]              nvarchar(3)  NOT NULL,
        [DayOfYear]             int         NOT NULL,
        [MonthYear]             nvarchar(10) NOT NULL,
        [MonthYearKey]          int         NOT NULL,
        [YearQuarterKey]        int         NOT NULL,
        [QuarterYear]           nvarchar(10) NOT NULL,
        [CalendarMonthIndex]    int         NOT NULL,
        [CalendarQuarterIndex]  int         NOT NULL,
        [DayOfWeek]             int         NOT NULL,
        [IsWeekend]             bit         NOT NULL,
        [IsBusinessDay]         bit         NOT NULL,
        [MonthStartDate]        date        NOT NULL,
        [MonthEndDate]          date        NOT NULL,
        [QuarterStartDate]      date        NOT NULL,
        [QuarterEndDate]        date        NOT NULL,
        [IsMonthStart]          bit         NOT NULL,
        [IsMonthEnd]            bit         NOT NULL,
        [IsQuarterStart]        bit         NOT NULL,
        [IsQuarterEnd]          bit         NOT NULL,
        [IsYearStart]           bit         NOT NULL,
        [IsYearEnd]             bit         NOT NULL,
        [WeekOfMonth]           int         NOT NULL,
        [NextBusinessDay]       date        NOT NULL,
        [PreviousBusinessDay]   date        NOT NULL,
        [IsToday]               bit         NOT NULL,
        [IsCurrentYear]         bit         NOT NULL,
        [IsCurrentMonth]        bit         NOT NULL,
        [IsCurrentQuarter]      bit         NOT NULL,
        [CurrentDayOffset]      int         NOT NULL,
        [YearOffset]            int         NOT NULL,
        [CalendarMonthOffset]   int         NOT NULL,
        [CalendarQuarterOffset] int         NOT NULL,
        -- Phase 2: ISO Weeks
        [ISOWeekNumber]         int         NOT NULL,
        [ISOYear]               int         NOT NULL,
        [ISOWeekStartDate]      date        NOT NULL,
        [ISOWeekEndDate]        date        NOT NULL,
        [ISOYearWeekIndex]      int         NOT NULL,
        [ISOWeekOffset]         int         NOT NULL,
        -- Phase 3: Monthly Fiscal
        [FiscalYearStartYear]   int         NOT NULL,
        [FiscalMonthNumber]     int         NOT NULL,
        [FiscalQuarterNumber]   int         NOT NULL,
        [FiscalYear]            int         NOT NULL,
        [FiscalYearRange]       nvarchar(10) NOT NULL,
        [FiscalYearLabel]       nvarchar(10) NOT NULL,
        [FiscalQuarterLabel]    nvarchar(20) NOT NULL,
        [FiscalMonthIndex]      int         NOT NULL,
        [FiscalQuarterIndex]    int         NOT NULL,
        [FiscalYearStartDate]   date        NOT NULL,
        [FiscalYearEndDate]     date        NOT NULL,
        [FiscalQuarterStartDate] date       NOT NULL,
        [FiscalQuarterEndDate]  date        NOT NULL,
        [IsFiscalYearStart]     bit         NOT NULL,
        [IsFiscalYearEnd]       bit         NOT NULL,
        [IsFiscalQuarterStart]  bit         NOT NULL,
        [IsFiscalQuarterEnd]    bit         NOT NULL,
        [FiscalMonthOffset]     int         NOT NULL,
        [FiscalQuarterOffset]   int         NOT NULL,
        -- Phase 4: Weekly Fiscal (NULL when not enabled)
        [FWYearNumber]          int         NULL,
        [FWStartOfYear]         date        NULL,
        [FWEndOfYear]           date        NULL,
        [FWYearLabel]           nvarchar(10) NULL,
        [FWDayOfYear]           int         NULL,
        [FWWeekNumber]          int         NULL,
        [FWPeriodNumber]        int         NULL,
        [FWQuarterNumber]       int         NULL,
        [FWWeekInQuarterNumber] int         NULL,
        [FWMonthNumber]         int         NULL,
        [FWQuarterIndex]        int         NULL,
        [FWMonthIndex]          int         NULL,
        [FWWeekDayNumber]       int         NULL,
        [FWWeekDayNameShort]    nvarchar(3)  NULL,
        [FWStartOfWeek]         date        NULL,
        [FWEndOfWeek]           date        NULL,
        [FWIsWorkingDay]        bit         NULL,
        [FWDayType]             nvarchar(20) NULL,
        [FWStartOfMonth]        date        NULL,
        [FWEndOfMonth]          date        NULL,
        [FWDayOfMonth]          int         NULL,
        [FWStartOfQuarter]      date        NULL,
        [FWEndOfQuarter]        date        NULL,
        [FWDayOfQuarter]        int         NULL,
        [FWWeekIndex]           int         NULL,
        [FWQuarterLabel]        nvarchar(20) NULL,
        [FWWeekLabel]           nvarchar(20) NULL,
        [FWPeriodLabel]         nvarchar(20) NULL,
        [FWMonthLabel]          nvarchar(30) NULL,
        [FWYearMonthLabel]      nvarchar(30) NULL,
        [FWWeekOffset]          int         NULL,
        [FWMonthOffset]         int         NULL,
        [FWQuarterOffset]       int         NULL,
        -- Phase 5: System Labels
        [FiscalSystem]          nvarchar(10) NOT NULL,
        [WeeklyFiscalSystem]    nvarchar(30) NOT NULL
    );

    ---------------------------------------------------------------------------
    -- PHASE 1-3: Base Calendar + ISO Weeks + Monthly Fiscal
    ---------------------------------------------------------------------------
    ;WITH
    -- Number generator (supports up to 100,000 dates ~ 273 years)
    E1(N) AS (SELECT 1 FROM (VALUES(1),(1),(1),(1),(1),(1),(1),(1),(1),(1)) v(n)),
    E2(N) AS (SELECT 1 FROM E1 a CROSS JOIN E1 b),
    E4(N) AS (SELECT 1 FROM E2 a CROSS JOIN E2 b),
    E5(N) AS (SELECT 1 FROM E4 a CROSS JOIN E1 b),
    Nums AS (
        SELECT TOP (DATEDIFF(DAY, @StartDate, @EndDate) + 1)
            ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS n
        FROM E5
    ),
    Spine AS (
        SELECT CAST(DATEADD(DAY, n, @StartDate) AS date) AS d
        FROM Nums
    ),
    Parts AS (
        SELECT
            d,
            YEAR(d)              AS yr,
            MONTH(d)             AS mo,
            DAY(d)               AS dy,
            DATEPART(QUARTER, d) AS qtr,
            -- DayOfWeek: 0=Sun..6=Sat (DATEFIRST-independent)
            DATEDIFF(DAY, '19000107', d) % 7 AS dow
        FROM Spine
    )
    INSERT INTO #DateTable (
        [Date],[Year],[Month],[Day],[Quarter],
        [DateKey],[DateSerialNumber],
        [MonthName],[MonthShort],[DayName],[DayShort],
        [DayOfYear],[MonthYear],[MonthYearKey],
        [YearQuarterKey],[QuarterYear],
        [CalendarMonthIndex],[CalendarQuarterIndex],
        [DayOfWeek],[IsWeekend],[IsBusinessDay],
        [MonthStartDate],[MonthEndDate],
        [QuarterStartDate],[QuarterEndDate],
        [IsMonthStart],[IsMonthEnd],[IsQuarterStart],[IsQuarterEnd],
        [IsYearStart],[IsYearEnd],
        [WeekOfMonth],
        [NextBusinessDay],[PreviousBusinessDay],
        [IsToday],[IsCurrentYear],[IsCurrentMonth],[IsCurrentQuarter],
        [CurrentDayOffset],[YearOffset],[CalendarMonthOffset],[CalendarQuarterOffset],
        [ISOWeekNumber],[ISOYear],
        [ISOWeekStartDate],[ISOWeekEndDate],
        [ISOYearWeekIndex],[ISOWeekOffset],
        [FiscalYearStartYear],[FiscalMonthNumber],[FiscalQuarterNumber],
        [FiscalYear],[FiscalYearRange],[FiscalYearLabel],[FiscalQuarterLabel],
        [FiscalMonthIndex],[FiscalQuarterIndex],
        [FiscalYearStartDate],[FiscalYearEndDate],
        [FiscalQuarterStartDate],[FiscalQuarterEndDate],
        [IsFiscalYearStart],[IsFiscalYearEnd],[IsFiscalQuarterStart],[IsFiscalQuarterEnd],
        [FiscalMonthOffset],[FiscalQuarterOffset],
        [FiscalSystem],[WeeklyFiscalSystem]
    )
    SELECT
        -- Base Calendar
        p.d,
        p.yr,
        p.mo,
        p.dy,
        p.qtr,
        CAST(p.yr AS bigint) * 10000 + p.mo * 100 + p.dy,
        DATEDIFF(DAY, '18991230', p.d),
        DATENAME(MONTH, p.d),
        LEFT(DATENAME(MONTH, p.d), 3),
        DATENAME(WEEKDAY, p.d),
        LEFT(DATENAME(WEEKDAY, p.d), 3),
        DATEPART(DAYOFYEAR, p.d),
        LEFT(DATENAME(MONTH, p.d), 3) + ' ' + CAST(p.yr AS varchar(4)),
        p.yr * 100 + p.mo,
        p.yr * 10 + p.qtr,
        'Q' + CAST(p.qtr AS varchar(1)) + ' ' + CAST(p.yr AS varchar(4)),
        p.yr * 12 + p.mo,
        p.yr * 4 + p.qtr,
        p.dow,
        CASE WHEN p.dow IN (0, 6) THEN 1 ELSE 0 END,
        CASE WHEN p.dow NOT IN (0, 6) THEN 1 ELSE 0 END,
        DATEADD(MONTH, DATEDIFF(MONTH, 0, p.d), 0),
        EOMONTH(p.d),
        DATEADD(QUARTER, DATEDIFF(QUARTER, 0, p.d), 0),
        DATEADD(DAY, -1, DATEADD(QUARTER, DATEDIFF(QUARTER, 0, p.d) + 1, 0)),
        CASE WHEN p.dy = 1 THEN 1 ELSE 0 END,
        CASE WHEN p.d = EOMONTH(p.d) THEN 1 ELSE 0 END,
        CASE WHEN p.d = DATEADD(QUARTER, DATEDIFF(QUARTER, 0, p.d), 0) THEN 1 ELSE 0 END,
        CASE WHEN p.d = DATEADD(DAY, -1, DATEADD(QUARTER, DATEDIFF(QUARTER, 0, p.d) + 1, 0)) THEN 1 ELSE 0 END,
        CASE WHEN p.mo = 1 AND p.dy = 1 THEN 1 ELSE 0 END,
        CASE WHEN p.mo = 12 AND p.dy = 31 THEN 1 ELSE 0 END,
        (p.dy - 1) / 7 + 1,
        -- NextBusinessDay
        CASE p.dow
            WHEN 5 THEN DATEADD(DAY, 3, p.d)
            WHEN 6 THEN DATEADD(DAY, 2, p.d)
            ELSE        DATEADD(DAY, 1, p.d) END,
        -- PreviousBusinessDay
        CASE p.dow
            WHEN 0 THEN DATEADD(DAY, -2, p.d)
            WHEN 1 THEN DATEADD(DAY, -3, p.d)
            ELSE        DATEADD(DAY, -1, p.d) END,
        CASE WHEN p.d = @AsOfDate THEN 1 ELSE 0 END,
        CASE WHEN p.yr = YEAR(@AsOfDate) THEN 1 ELSE 0 END,
        CASE WHEN p.yr = YEAR(@AsOfDate) AND p.mo = MONTH(@AsOfDate) THEN 1 ELSE 0 END,
        CASE WHEN p.yr = YEAR(@AsOfDate) AND p.qtr = DATEPART(QUARTER, @AsOfDate) THEN 1 ELSE 0 END,
        DATEDIFF(DAY, @AsOfDate, p.d),
        p.yr - YEAR(@AsOfDate),
        (p.yr * 12 + p.mo) - @AsOfCalMonthIndex,
        (p.yr * 4 + p.qtr) - @AsOfCalQuarterIndex,

        -- ISO Weeks
        DATEPART(ISO_WEEK, p.d),
        iso.ISOYear,
        iso.ISOWeekStart,
        DATEADD(DAY, 6, iso.ISOWeekStart),
        DATEDIFF(DAY, @ISOWeekRef, iso.ISOWeekStart) / 7,
        DATEDIFF(DAY, @ISOWeekRef, iso.ISOWeekStart) / 7 - @AsOfISOWeekIndex,

        -- Monthly Fiscal
        f.FYStartYr,
        f.FMo,
        f.FQtr,
        f.FY,
        CASE WHEN @FYStartMonth = 1
            THEN CAST(f.FYStartYr AS varchar(4))
            ELSE CAST(f.FYStartYr AS varchar(4)) + '-' + CAST(f.FY AS varchar(4))
        END,
        'FY ' + CAST(f.FY AS varchar(4)),
        'Q' + CAST(f.FQtr AS varchar(1)) + ' FY' + CAST(f.FY AS varchar(4)),
        f.FMoIdx,
        f.FQtrIdx,
        fd.FYStartDate,
        fd.FYEndDate,
        fd.FQStartDate,
        fd.FQEndDate,
        CASE WHEN p.d = fd.FYStartDate  THEN 1 ELSE 0 END,
        CASE WHEN p.d = fd.FYEndDate    THEN 1 ELSE 0 END,
        CASE WHEN p.d = fd.FQStartDate  THEN 1 ELSE 0 END,
        CASE WHEN p.d = fd.FQEndDate    THEN 1 ELSE 0 END,
        f.FMoIdx  - @AsOfFiscalMoIdx,
        f.FQtrIdx - @AsOfFiscalQtrIdx,

        -- System Labels
        N'Monthly',
        @WFLabel

    FROM Parts p
    -- ISO helper: compute ISOWeekStart and ISOYear once
    CROSS APPLY (
        SELECT
            -- Monday of ISO week (1900-01-01 = Monday, so DATEDIFF(DAY,0,d)%7 = 0=Mon..6=Sun)
            CAST(DATEADD(DAY, -(DATEDIFF(DAY, 0, p.d) % 7), p.d) AS date) AS ISOWeekStart,
            CASE
                WHEN p.mo = 1  AND DATEPART(ISO_WEEK, p.d) >= 52 THEN p.yr - 1
                WHEN p.mo = 12 AND DATEPART(ISO_WEEK, p.d) = 1   THEN p.yr + 1
                ELSE p.yr
            END AS ISOYear
    ) iso
    -- Fiscal helper: core fiscal values
    CROSS APPLY (
        SELECT
            CASE WHEN p.mo >= @FYStartMonth THEN p.yr ELSE p.yr - 1 END AS FYStartYr,
            ((p.mo - @FYStartMonth + 12) % 12) + 1                      AS FMo,
            (((p.mo - @FYStartMonth + 12) % 12)) / 3 + 1                AS FQtr,
            (CASE WHEN p.mo >= @FYStartMonth THEN p.yr ELSE p.yr - 1 END) + @FYEndAdd AS FY,
            (CASE WHEN p.mo >= @FYStartMonth THEN p.yr ELSE p.yr - 1 END) * 12
                + (((p.mo - @FYStartMonth + 12) % 12) + 1)              AS FMoIdx,
            (CASE WHEN p.mo >= @FYStartMonth THEN p.yr ELSE p.yr - 1 END) * 4
                + ((((p.mo - @FYStartMonth + 12) % 12)) / 3 + 1)        AS FQtrIdx
    ) f
    -- Fiscal helper: start/end dates
    CROSS APPLY (
        SELECT
            DATEFROMPARTS(f.FYStartYr, @FYStartMonth, 1) AS FYStartDate,
            DATEADD(DAY, -1, DATEADD(YEAR, 1, DATEFROMPARTS(f.FYStartYr, @FYStartMonth, 1))) AS FYEndDate,
            DATEFROMPARTS(
                f.FYStartYr + ((@FYStartMonth + (f.FQtr - 1) * 3 - 1) / 12),
                ((@FYStartMonth + (f.FQtr - 1) * 3 - 1) % 12) + 1,
                1
            ) AS FQStartDate,
            DATEADD(DAY, -1, DATEADD(MONTH, 3,
                DATEFROMPARTS(
                    f.FYStartYr + ((@FYStartMonth + (f.FQtr - 1) * 3 - 1) / 12),
                    ((@FYStartMonth + (f.FQtr - 1) * 3 - 1) % 12) + 1,
                    1
                )
            )) AS FQEndDate
    ) fd;

    ---------------------------------------------------------------------------
    -- PHASE 4: Weekly Fiscal (conditional)
    ---------------------------------------------------------------------------
    IF @IncludeWeeklyFiscal = 1
    BEGIN
        -- Build fiscal year boundary table
        CREATE TABLE #FWBounds (
            FWYear  int  NOT NULL PRIMARY KEY,
            FWStart date NOT NULL,
            FWEnd   date NULL
        );

        DECLARE @FWMinYear int = (SELECT MIN([Year]) FROM #DateTable) - 1;
        DECLARE @FWMaxYear int = (SELECT MAX([Year]) FROM #DateTable) + 2;

        ;WITH YearNums AS (
            SELECT @FWMinYear AS y
            UNION ALL
            SELECT y + 1 FROM YearNums WHERE y <= @FWMaxYear + 1
        )
        INSERT INTO #FWBounds (FWYear, FWStart)
        SELECT y, calc.FWStart
        FROM YearNums
        CROSS APPLY (
            SELECT DATEADD(DAY, bnd.Offset, fdm.FirstDay) AS FWStart
            FROM (VALUES (
                DATEFROMPARTS(y - (CASE WHEN @FYStartMonth > 1 THEN @TSY ELSE 0 END), @FYStartMonth, 1)
            )) fdm(FirstDay)
            CROSS APPLY (VALUES (
                (DATEDIFF(DAY, '19000107', fdm.FirstDay) % 7 - @FDOW + 7) % 7 + 1
            )) wdn(WeekdayNum)
            CROSS APPLY (VALUES (
                CASE
                    WHEN @WType = 'Last' THEN 1 - wdn.WeekdayNum
                    WHEN wdn.WeekdayNum >= 5 THEN 8 - wdn.WeekdayNum
                    ELSE 1 - wdn.WeekdayNum
                END
            )) bnd(Offset)
        ) calc
        OPTION (MAXRECURSION 200);

        -- FWEnd = day before next year's start
        UPDATE b
        SET FWEnd = DATEADD(DAY, -1, nxt.FWStart)
        FROM #FWBounds b
        JOIN #FWBounds nxt ON nxt.FWYear = b.FWYear + 1;

        -- Remove the extra boundary row (last year+2 has no next)
        DELETE FROM #FWBounds WHERE FWEnd IS NULL;

        -- Weekly fiscal as-of reference values
        DECLARE @FirstWeekRef date = DATEADD(DAY, @FDOW, '19001230');

        DECLARE @AsOfFWYearNumber int = (
            SELECT FWYear FROM #FWBounds WHERE @AsOfDate >= FWStart AND @AsOfDate <= FWEnd);
        IF @AsOfFWYearNumber IS NULL SET @AsOfFWYearNumber = YEAR(@AsOfDate);

        DECLARE @AsOfFWStart date = (SELECT FWStart FROM #FWBounds WHERE FWYear = @AsOfFWYearNumber);
        DECLARE @AsOfFWDayOfYear int = DATEDIFF(DAY, @AsOfFWStart, @AsOfDate) + 1;
        DECLARE @AsOfFWWeek int = (@AsOfFWDayOfYear - 1) / 7 + 1;
        DECLARE @AsOfFWQtr  int = CASE WHEN @AsOfFWWeek > 52 THEN 4 ELSE (@AsOfFWWeek + 12) / 13 END;
        DECLARE @AsOfFWWiQ  int = CASE WHEN @AsOfFWWeek > 52 THEN 14 ELSE @AsOfFWWeek - 13 * (@AsOfFWQtr - 1) END;
        DECLARE @AsOfFWMiQ  int = CASE WHEN @AsOfFWWiQ <= @W1 THEN 1 WHEN @AsOfFWWiQ <= @W1 + @W2 THEN 2 ELSE 3 END;
        DECLARE @AsOfFWMo   int = (@AsOfFWQtr - 1) * 3 + @AsOfFWMiQ;
        DECLARE @AsOfFWMoIdx  int = @AsOfFWYearNumber * 12 - 1 + @AsOfFWMo;
        DECLARE @AsOfFWQtrIdx int = @AsOfFWYearNumber * 4  - 1 + @AsOfFWQtr;
        DECLARE @AsOfFWWkIdx  int = DATEDIFF(DAY, @FirstWeekRef, @AsOfDate) / 7 + 1;

        -----------------------------------------------------------------------
        -- Pass 1: Assign FW year + basic columns from bounds join
        -----------------------------------------------------------------------
        UPDATE dt
        SET
            FWYearNumber     = b.FWYear,
            FWStartOfYear    = b.FWStart,
            FWEndOfYear      = b.FWEnd,
            FWYearLabel      = N'FY ' + CAST(b.FWYear AS varchar(4)),
            FWDayOfYear      = DATEDIFF(DAY, b.FWStart, dt.[Date]) + 1,
            FWWeekNumber     = (DATEDIFF(DAY, b.FWStart, dt.[Date])) / 7 + 1,
            FWWeekDayNumber  = (DATEDIFF(DAY, '19000107', dt.[Date]) % 7 - @FDOW + 7) % 7 + 1,
            FWWeekDayNameShort = LEFT(DATENAME(WEEKDAY, dt.[Date]), 3),
            FWIsWorkingDay   = CASE WHEN DATEDIFF(DAY, 0, dt.[Date]) % 7 BETWEEN 0 AND 4 THEN 1 ELSE 0 END,
            FWWeekIndex      = DATEDIFF(DAY, @FirstWeekRef, dt.[Date]) / 7 + 1
        FROM #DateTable dt
        JOIN #FWBounds b ON dt.[Date] >= b.FWStart AND dt.[Date] <= b.FWEnd;

        -----------------------------------------------------------------------
        -- Pass 2: Derived from FWWeekNumber
        -----------------------------------------------------------------------
        UPDATE #DateTable
        SET
            FWPeriodNumber  = CASE WHEN FWWeekNumber > 52 THEN 13 ELSE (FWWeekNumber + 3) / 4 END,
            FWQuarterNumber = CASE WHEN FWWeekNumber > 52 THEN 4  ELSE (FWWeekNumber + 12) / 13 END,
            FWWeekInQuarterNumber = CASE
                WHEN FWWeekNumber > 52 THEN 14
                ELSE FWWeekNumber - 13 * ((CASE WHEN FWWeekNumber > 52 THEN 4 ELSE (FWWeekNumber + 12) / 13 END) - 1)
            END,
            FWStartOfWeek = DATEADD(DAY, -(FWWeekDayNumber - 1), [Date]),
            FWEndOfWeek   = DATEADD(DAY, 6 - (FWWeekDayNumber - 1), [Date]),
            FWDayType     = CASE WHEN FWIsWorkingDay = 1 THEN N'Working Day' ELSE N'Non-Working Day' END
        WHERE FWYearNumber IS NOT NULL;

        -----------------------------------------------------------------------
        -- Pass 3: FWMonthNumber + contiguous indexes (depends on FWWeekInQuarterNumber)
        -----------------------------------------------------------------------
        UPDATE #DateTable
        SET
            FWMonthNumber = (FWQuarterNumber - 1) * 3
                + CASE
                    WHEN FWWeekInQuarterNumber <= @W1 THEN 1
                    WHEN FWWeekInQuarterNumber <= @W1 + @W2 THEN 2
                    ELSE 3
                END,
            FWQuarterIndex = FWYearNumber * 4  - 1 + FWQuarterNumber,
            FWMonthIndex   = FWYearNumber * 12 - 1
                + ((FWQuarterNumber - 1) * 3
                    + CASE
                        WHEN FWWeekInQuarterNumber <= @W1 THEN 1
                        WHEN FWWeekInQuarterNumber <= @W1 + @W2 THEN 2
                        ELSE 3
                    END),
            -- Labels that don't need boundaries
            FWQuarterLabel = N'FQ' + CAST(FWQuarterNumber AS varchar(1))
                + N' - ' + CAST(FWYearNumber AS varchar(4)),
            FWWeekLabel    = N'FW' + RIGHT('0' + CAST(FWWeekNumber AS varchar(2)), 2)
                + N' - ' + CAST(FWYearNumber AS varchar(4)),
            FWPeriodLabel  = N'P' + RIGHT('0' + CAST(FWPeriodNumber AS varchar(2)), 2)
                + N' - ' + CAST(FWYearNumber AS varchar(4))
        WHERE FWYearNumber IS NOT NULL;

        -----------------------------------------------------------------------
        -- Pass 4: Month/quarter boundaries via window functions
        -----------------------------------------------------------------------
        ;WITH Boundaries AS (
            SELECT
                [Date],
                MIN([Date]) OVER (PARTITION BY FWMonthIndex)   AS MoStart,
                MAX([Date]) OVER (PARTITION BY FWMonthIndex)   AS MoEnd,
                MIN([Date]) OVER (PARTITION BY FWQuarterIndex) AS QtrStart,
                MAX([Date]) OVER (PARTITION BY FWQuarterIndex) AS QtrEnd
            FROM #DateTable
            WHERE FWYearNumber IS NOT NULL
        )
        UPDATE dt
        SET
            FWStartOfMonth  = b.MoStart,
            FWEndOfMonth    = b.MoEnd,
            FWDayOfMonth    = DATEDIFF(DAY, b.MoStart, dt.[Date]) + 1,
            FWStartOfQuarter = b.QtrStart,
            FWEndOfQuarter  = b.QtrEnd,
            FWDayOfQuarter  = DATEDIFF(DAY, b.QtrStart, dt.[Date]) + 1
        FROM #DateTable dt
        JOIN Boundaries b ON dt.[Date] = b.[Date];

        -----------------------------------------------------------------------
        -- Pass 5: Labels needing boundaries + offsets
        -----------------------------------------------------------------------
        UPDATE #DateTable
        SET
            FWMonthLabel = N'FM ' + LEFT(DATENAME(MONTH, DATEADD(DAY, 14, FWStartOfMonth)), 3)
                + N' - ' + CAST(FWYearNumber AS varchar(4)),
            FWYearMonthLabel = N'FM ' + LEFT(DATENAME(MONTH, DATEADD(DAY, 14, FWStartOfMonth)), 3)
                + N' ' + CAST(YEAR(DATEADD(DAY, 14, FWStartOfMonth)) AS varchar(4)),
            FWWeekOffset    = FWWeekIndex    - @AsOfFWWkIdx,
            FWMonthOffset   = FWMonthIndex   - @AsOfFWMoIdx,
            FWQuarterOffset = FWQuarterIndex - @AsOfFWQtrIdx
        WHERE FWYearNumber IS NOT NULL;

        DROP TABLE #FWBounds;
    END;

    ---------------------------------------------------------------------------
    -- PHASE 5: Final output with column naming
    ---------------------------------------------------------------------------
    DECLARE @UseSpacedNames bit = CASE
        WHEN UPPER(LTRIM(RTRIM(ISNULL(@ColumnNamingStyle, 'Spaced')))) = 'PASCALCASE' THEN 0
        ELSE 1 END;

    -- Column mapping: ordinal, PascalCase name, spaced name, phase (4 = weekly fiscal)
    DECLARE @Cols TABLE (
        Ordinal    int IDENTITY(1,1),
        PascalName nvarchar(50),
        SpacedName nvarchar(50),
        Phase      tinyint
    );

    INSERT INTO @Cols (PascalName, SpacedName, Phase) VALUES
    -- Phase 1: Base Calendar
    (N'Date',                 N'Date',                   1),
    (N'Year',                 N'Year',                   1),
    (N'Month',                N'Month',                  1),
    (N'Day',                  N'Day',                    1),
    (N'Quarter',              N'Quarter',                1),
    (N'DateKey',              N'Date Key',               1),
    (N'DateSerialNumber',     N'Date Serial Number',     1),
    (N'MonthName',            N'Month Name',             1),
    (N'MonthShort',           N'Month Short',            1),
    (N'DayName',              N'Day Name',               1),
    (N'DayShort',             N'Day Short',              1),
    (N'DayOfYear',            N'Day of Year',            1),
    (N'MonthYear',            N'Month Year',             1),
    (N'MonthYearKey',         N'Month Year Key',         1),
    (N'YearQuarterKey',       N'Year Quarter Key',       1),
    (N'QuarterYear',          N'Quarter Year',           1),
    (N'CalendarMonthIndex',   N'Calendar Month Index',   1),
    (N'CalendarQuarterIndex', N'Calendar Quarter Index',  1),
    (N'DayOfWeek',            N'Day of Week',            1),
    (N'IsWeekend',            N'Is Weekend',             1),
    (N'IsBusinessDay',        N'Is Business Day',        1),
    (N'MonthStartDate',       N'Month Start Date',       1),
    (N'MonthEndDate',         N'Month End Date',         1),
    (N'QuarterStartDate',     N'Quarter Start Date',     1),
    (N'QuarterEndDate',       N'Quarter End Date',       1),
    (N'IsMonthStart',         N'Is Month Start',         1),
    (N'IsMonthEnd',           N'Is Month End',           1),
    (N'IsQuarterStart',       N'Is Quarter Start',       1),
    (N'IsQuarterEnd',         N'Is Quarter End',         1),
    (N'IsYearStart',          N'Is Year Start',          1),
    (N'IsYearEnd',            N'Is Year End',            1),
    (N'WeekOfMonth',          N'Week of Month',          1),
    (N'NextBusinessDay',      N'Next Business Day',      1),
    (N'PreviousBusinessDay',  N'Previous Business Day',  1),
    (N'IsToday',              N'Is Today',               1),
    (N'IsCurrentYear',        N'Is Current Year',        1),
    (N'IsCurrentMonth',       N'Is Current Month',       1),
    (N'IsCurrentQuarter',     N'Is Current Quarter',     1),
    (N'CurrentDayOffset',     N'Current Day Offset',     1),
    (N'YearOffset',           N'Year Offset',            1),
    (N'CalendarMonthOffset',  N'Calendar Month Offset',  1),
    (N'CalendarQuarterOffset',N'Calendar Quarter Offset', 1),
    -- Phase 2: ISO Weeks
    (N'ISOWeekNumber',        N'ISO Week Number',        2),
    (N'ISOYear',              N'ISO Year',               2),
    (N'ISOWeekStartDate',     N'ISO Week Start Date',    2),
    (N'ISOWeekEndDate',       N'ISO Week End Date',      2),
    (N'ISOYearWeekIndex',     N'ISO Year Week Index',    2),
    (N'ISOWeekOffset',        N'ISO Week Offset',        2),
    -- Phase 3: Monthly Fiscal
    (N'FiscalYearStartYear',  N'Fiscal Year Start Year', 3),
    (N'FiscalMonthNumber',    N'Fiscal Month Number',    3),
    (N'FiscalQuarterNumber',  N'Fiscal Quarter Number',  3),
    (N'FiscalYear',           N'Fiscal Year',            3),
    (N'FiscalYearRange',      N'Fiscal Year Range',      3),
    (N'FiscalYearLabel',      N'Fiscal Year Label',      3),
    (N'FiscalQuarterLabel',   N'Fiscal Quarter Label',   3),
    (N'FiscalMonthIndex',     N'Fiscal Month Index',     3),
    (N'FiscalQuarterIndex',   N'Fiscal Quarter Index',   3),
    (N'FiscalYearStartDate',  N'Fiscal Year Start Date', 3),
    (N'FiscalYearEndDate',    N'Fiscal Year End Date',   3),
    (N'FiscalQuarterStartDate',N'Fiscal Quarter Start Date',3),
    (N'FiscalQuarterEndDate', N'Fiscal Quarter End Date', 3),
    (N'IsFiscalYearStart',    N'Is Fiscal Year Start',   3),
    (N'IsFiscalYearEnd',      N'Is Fiscal Year End',     3),
    (N'IsFiscalQuarterStart', N'Is Fiscal Quarter Start', 3),
    (N'IsFiscalQuarterEnd',   N'Is Fiscal Quarter End',  3),
    (N'FiscalMonthOffset',    N'Fiscal Month Offset',    3),
    (N'FiscalQuarterOffset',  N'Fiscal Quarter Offset',  3),
    -- Phase 4: Weekly Fiscal
    (N'FWYearNumber',         N'FW Year Number',         4),
    (N'FWStartOfYear',        N'FW Start of Year',       4),
    (N'FWEndOfYear',          N'FW End of Year',         4),
    (N'FWYearLabel',          N'FW Year Label',          4),
    (N'FWDayOfYear',          N'FW Day of Year',         4),
    (N'FWWeekNumber',         N'FW Week Number',         4),
    (N'FWPeriodNumber',       N'FW Period Number',       4),
    (N'FWQuarterNumber',      N'FW Quarter Number',      4),
    (N'FWWeekInQuarterNumber',N'FW Week in Quarter Number',4),
    (N'FWMonthNumber',        N'FW Month Number',        4),
    (N'FWQuarterIndex',       N'FW Quarter Index',       4),
    (N'FWMonthIndex',         N'FW Month Index',         4),
    (N'FWWeekDayNumber',      N'FW Week Day Number',     4),
    (N'FWWeekDayNameShort',   N'FW Week Day Name Short', 4),
    (N'FWStartOfWeek',        N'FW Start of Week',       4),
    (N'FWEndOfWeek',          N'FW End of Week',         4),
    (N'FWIsWorkingDay',       N'FW Is Working Day',      4),
    (N'FWDayType',            N'FW Day Type',            4),
    (N'FWStartOfMonth',       N'FW Start of Month',      4),
    (N'FWEndOfMonth',         N'FW End of Month',        4),
    (N'FWDayOfMonth',         N'FW Day of Month',        4),
    (N'FWStartOfQuarter',     N'FW Start of Quarter',    4),
    (N'FWEndOfQuarter',       N'FW End of Quarter',      4),
    (N'FWDayOfQuarter',       N'FW Day of Quarter',      4),
    (N'FWWeekIndex',          N'FW Week Index',          4),
    (N'FWQuarterLabel',       N'FW Quarter Label',       4),
    (N'FWWeekLabel',          N'FW Week Label',          4),
    (N'FWPeriodLabel',        N'FW Period Label',        4),
    (N'FWMonthLabel',         N'FW Month Label',         4),
    (N'FWYearMonthLabel',     N'FW Year Month Label',    4),
    (N'FWWeekOffset',         N'FW Week Offset',         4),
    (N'FWMonthOffset',        N'FW Month Offset',        4),
    (N'FWQuarterOffset',      N'FW Quarter Offset',      4),
    -- Phase 5: System Labels
    (N'FiscalSystem',         N'Fiscal System',          5),
    (N'WeeklyFiscalSystem',   N'Weekly Fiscal System',   5);

    -- Build dynamic column list
    DECLARE @colList nvarchar(max) = N'';

    SELECT @colList = @colList +
        CASE
            WHEN @UseSpacedNames = 1 AND PascalName <> SpacedName
                THEN QUOTENAME(PascalName) + N' AS ' + QUOTENAME(SpacedName)
            ELSE QUOTENAME(PascalName)
        END + N', '
    FROM @Cols
    WHERE Phase <> 4 OR @IncludeWeeklyFiscal = 1
    ORDER BY Ordinal;

    -- Trim trailing comma
    SET @colList = LEFT(@colList, LEN(@colList) - 1);

    -- Build final SQL: SELECT INTO persistent table, or just return result set
    DECLARE @sql nvarchar(max);

    IF @OutputTable IS NOT NULL
    BEGIN
        -- Parse schema and table name (default schema = dbo)
        DECLARE @SchemaName sysname = ISNULL(PARSENAME(@OutputTable, 2), N'dbo');
        DECLARE @ObjName   sysname = PARSENAME(@OutputTable, 1);

        IF @ObjName IS NULL
        BEGIN
            RAISERROR(N'Invalid table name: %s', 16, 1, @OutputTable);
            DROP TABLE #DateTable;
            RETURN;
        END;

        -- Check if table already exists
        DECLARE @FullName nvarchar(256) = QUOTENAME(@SchemaName) + N'.' + QUOTENAME(@ObjName);

        IF OBJECT_ID(@FullName) IS NOT NULL
        BEGIN
            RAISERROR(N'Table %s already exists. Drop it first or choose a different name.', 16, 1, @FullName);
            DROP TABLE #DateTable;
            RETURN;
        END;

        SET @sql = N'SELECT ' + @colList + N' INTO ' + @FullName + N' FROM #DateTable ORDER BY [Date]';
        EXEC sp_executesql @sql;

        DECLARE @rowCount nvarchar(10) = CAST(@@ROWCOUNT AS nvarchar(10));

        -- Add primary key on the Date column
        DECLARE @pkSQL nvarchar(max) = N'ALTER TABLE ' + @FullName
            + N' ADD CONSTRAINT ' + QUOTENAME('PK_' + @ObjName + '_Date')
            + N' PRIMARY KEY CLUSTERED ([Date])';
        EXEC sp_executesql @pkSQL;

        PRINT N'Created table ' + @FullName + N' with ' + @rowCount + N' rows.';
    END
    ELSE
    BEGIN
        SET @sql = N'SELECT ' + @colList + N' FROM #DateTable ORDER BY [Date]';
        EXEC sp_executesql @sql;
    END;

    DROP TABLE #DateTable;
END;
