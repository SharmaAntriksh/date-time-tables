/*
    usp_TimeTable
    Generates a complete time dimension table at second or minute grain.

    T-SQL equivalent of the Power Query time.pq table.

    Parameters:
        @Grain              nvarchar(10) - 'Second' (86,400 rows) or 'Minute' (1,440 rows)
        @IncludeLabels      bit          - 1 (default) to include bin label columns
        @ColumnNamingStyle  nvarchar(20) - 'Spaced' (default) or 'PascalCase'
        @OutputTable        nvarchar(256)- NULL (default) returns result set;
                                           if set, creates a persistent table (e.g. 'dbo.TimeTable').
                                           Drops and recreates if the table already exists.

    Usage:
        -- Return as result set (second grain):
        EXEC dbo.usp_TimeTable;

        -- Minute grain:
        EXEC dbo.usp_TimeTable @Grain = 'Minute';

        -- Persist to a table:
        EXEC dbo.usp_TimeTable
            @Grain       = 'Second',
            @OutputTable = 'dbo.DimTime';
*/
CREATE OR ALTER PROCEDURE dbo.usp_TimeTable
    @Grain              nvarchar(10)  = N'Second',
    @IncludeLabels      bit           = 1,
    @ColumnNamingStyle  nvarchar(20)  = N'Spaced',
    @OutputTable        nvarchar(256) = NULL,
    @Help               bit           = 0
AS
BEGIN
    SET NOCOUNT ON;

    ---------------------------------------------------------------------------
    -- Help
    ---------------------------------------------------------------------------
    IF @Help = 1
    BEGIN
        PRINT '
usp_TimeTable - Generates a complete time dimension table.

USAGE:
    -- Return as result set (second grain, 86,400 rows):
    EXEC dbo.usp_TimeTable;

    -- Minute grain (1,440 rows):
    EXEC dbo.usp_TimeTable @Grain = ''Minute'';

    -- Without bin labels:
    EXEC dbo.usp_TimeTable @IncludeLabels = 0;

    -- PascalCase column names:
    EXEC dbo.usp_TimeTable @ColumnNamingStyle = ''PascalCase'';

    -- Persist to a table:
    EXEC dbo.usp_TimeTable
        @Grain       = ''Second'',
        @OutputTable = ''dbo.DimTime'';

PARAMETERS:
    @Grain              nvarchar = Second   ''Second'' (86,400 rows) or ''Minute'' (1,440 rows)
    @IncludeLabels      bit = 1             1 to include bin label columns
    @ColumnNamingStyle  nvarchar = Spaced   ''Spaced'' or ''PascalCase''
    @OutputTable        nvarchar = NULL     NULL returns result set; set to create
                                            a persistent table (e.g. ''dbo.DimTime'').
                                            Drops and recreates if the table already exists.
    @Help               bit = 0             1 to show this help text
';
        RETURN;
    END;

    ---------------------------------------------------------------------------
    -- Parameter normalization
    ---------------------------------------------------------------------------
    DECLARE @IsSecond bit = CASE
        WHEN UPPER(LTRIM(RTRIM(@Grain))) = 'MINUTE' THEN 0 ELSE 1 END;

    DECLARE @RowCount int = CASE WHEN @IsSecond = 1 THEN 86400 ELSE 1440 END;
    DECLARE @rowCountMsg nvarchar(10);

    ---------------------------------------------------------------------------
    -- Build time spine
    ---------------------------------------------------------------------------
    CREATE TABLE #TimeTable (
        [Time]                  time(0)      NOT NULL,
        [Hour24]                int          NOT NULL,
        [Hour12]                int          NOT NULL,
        [Minute]                int          NOT NULL,
        [Second]                int          NULL,
        [AmPm]                  nvarchar(2)  NOT NULL,
        [Hour12Text]            nvarchar(5)  NOT NULL,
        [TimeKey]               int          NOT NULL,
        [TimeText]              nvarchar(5)  NOT NULL,
        [TimeSeconds]           int          NOT NULL,
        [TimeOfDay]             nvarchar(8)  NOT NULL,
        -- Bin keys (always present)
        [Bin15mKey]             int          NOT NULL,
        [Bin30mKey]             int          NOT NULL,
        [Bin1hKey]              int          NOT NULL,
        [Bin6hKey]              int          NOT NULL,
        [Bin12hKey]             int          NOT NULL,
        -- Bin labels (NULL when @IncludeLabels = 0)
        [Bin15mLabel]           nvarchar(11) NULL,
        [Bin30mLabel]           nvarchar(11) NULL,
        [Bin1hLabel]            nvarchar(11) NULL,
        [Bin6hLabel]            nvarchar(11) NULL,
        [Bin12hLabel]           nvarchar(11) NULL,
        [Bin12hName]            nvarchar(12) NULL,
        -- Period of Day
        [PeriodOfDayName]       nvarchar(15) NOT NULL,
        [PeriodOfDayNameSort]   int          NOT NULL,
        -- 12-hour period
        [TwelveHourPeriodName]  nvarchar(12) NOT NULL,
        [TwelveHourBin]         nvarchar(5)  NOT NULL,
        [TwelveHourBinSort]     int          NOT NULL,
        -- 6-hour period
        [SixHourPeriodName]     nvarchar(10) NOT NULL,
        [SixHourBin]            nvarchar(5)  NOT NULL,
        [SixHourBinSort]        int          NOT NULL,
        -- 30-minute period
        [ThirtyMinutePeriodName]  nvarchar(15) NOT NULL,
        [ThirtyMinuteBin]         nvarchar(5)  NOT NULL,
        [ThirtyMinuteBinSort]     int          NOT NULL,
        -- 15-minute period
        [FifteenMinutePeriodName] nvarchar(15) NOT NULL,
        [FifteenMinuteBin]        nvarchar(5)  NOT NULL,
        [FifteenMinuteBinSort]    int          NOT NULL
    );

    ---------------------------------------------------------------------------
    -- Period lookup tables
    ---------------------------------------------------------------------------
    -- Period of Day (6 segments)
    DECLARE @PeriodOfDay TABLE (
        HourMin int, HourMax int, PeriodName nvarchar(15), PeriodSort int
    );
    INSERT INTO @PeriodOfDay VALUES
        (0,  4,  N'Midnight',      1),
        (5,  8,  N'Early Morning', 2),
        (9,  12, N'Morning',       3),
        (13, 16, N'Afternoon',     4),
        (17, 20, N'Evening',       5),
        (21, 23, N'Night',         6);

    -- 12-hour period
    DECLARE @TwelveHour TABLE (
        HourMin int, HourMax int, PeriodName nvarchar(12), Bin nvarchar(5), BinSort int
    );
    INSERT INTO @TwelveHour VALUES
        (0,  11, N'Before Noon', N'0-11',  1),
        (12, 23, N'After Noon',  N'12-23', 2);

    -- 6-hour period
    DECLARE @SixHour TABLE (
        HourMin int, HourMax int, PeriodName nvarchar(10), Bin nvarchar(5), BinSort int
    );
    INSERT INTO @SixHour VALUES
        (0,  5,  N'Down Time', N'0-5',   1),
        (6,  11, N'Login',     N'6-11',  2),
        (12, 17, N'Meetings',  N'12-17', 3),
        (18, 23, N'Logout',    N'18-23', 4);

    -- 30-minute period
    DECLARE @ThirtyMin TABLE (
        MinMin int, MinMax int, PeriodName nvarchar(15), Bin nvarchar(5), BinSort int
    );
    INSERT INTO @ThirtyMin VALUES
        (0,  29, N'Description', N'0-29',  1),
        (30, 59, N'Description', N'30-59', 2);

    -- 15-minute period
    DECLARE @FifteenMin TABLE (
        MinMin int, MinMax int, PeriodName nvarchar(15), Bin nvarchar(5), BinSort int
    );
    INSERT INTO @FifteenMin VALUES
        (0,  14, N'Description', N'0-14',  1),
        (15, 29, N'Description', N'15-29', 2),
        (30, 44, N'Description', N'30-44', 3),
        (45, 59, N'Description', N'45-59', 4);

    ---------------------------------------------------------------------------
    -- Generate rows and insert
    ---------------------------------------------------------------------------
    ;WITH
    -- Number generator (100,000 rows; covers the fixed max of 86,400 seconds per day)
    E1(N) AS (SELECT 1 FROM (VALUES(1),(1),(1),(1),(1),(1),(1),(1),(1),(1)) v(n)),
    E2(N) AS (SELECT 1 FROM E1 a CROSS JOIN E1 b),
    E4(N) AS (SELECT 1 FROM E2 a CROSS JOIN E2 b),
    E5(N) AS (SELECT 1 FROM E4 a CROSS JOIN E1 b),
    Nums AS (
        SELECT TOP (@RowCount)
            ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS n
        FROM E5
    ),
    Spine AS (
        SELECT
            n,
            n / CASE WHEN @IsSecond = 1 THEN 3600 ELSE 60 END AS h24,
            (n / CASE WHEN @IsSecond = 1 THEN 60 ELSE 1 END) % 60 AS m,
            CASE WHEN @IsSecond = 1 THEN n % 60 ELSE 0 END AS s
        FROM Nums
    ),
    Core AS (
        SELECT
            n,
            h24,
            m,
            s,
            -- Hour12: 1-12 (noon/midnight = 12)
            CASE WHEN h24 % 12 = 0 THEN 12 ELSE h24 % 12 END AS h12,
            CASE WHEN h24 < 12 THEN N'AM' ELSE N'PM' END AS ampm,
            -- MinuteOfDay for bin calculations
            h24 * 60 + m AS mod
        FROM Spine
    )
    INSERT INTO #TimeTable (
        [Time], [Hour24], [Hour12], [Minute], [Second],
        [AmPm], [Hour12Text], [TimeKey],
        [TimeText], [TimeSeconds], [TimeOfDay],
        [Bin15mKey], [Bin30mKey], [Bin1hKey], [Bin6hKey], [Bin12hKey],
        [Bin15mLabel], [Bin30mLabel], [Bin1hLabel], [Bin6hLabel], [Bin12hLabel], [Bin12hName],
        [PeriodOfDayName], [PeriodOfDayNameSort],
        [TwelveHourPeriodName], [TwelveHourBin], [TwelveHourBinSort],
        [SixHourPeriodName], [SixHourBin], [SixHourBinSort],
        [ThirtyMinutePeriodName], [ThirtyMinuteBin], [ThirtyMinuteBinSort],
        [FifteenMinutePeriodName], [FifteenMinuteBin], [FifteenMinuteBinSort]
    )
    SELECT
        -- Time
        TIMEFROMPARTS(c.h24, c.m, c.s, 0, 0),
        c.h24,
        c.h12,
        c.m,
        CASE WHEN @IsSecond = 1 THEN c.s ELSE NULL END,
        c.ampm,
        CAST(c.h12 AS varchar(2)) + N' ' + c.ampm,
        CASE WHEN @IsSecond = 1
            THEN c.h24 * 10000 + c.m * 100 + c.s
            ELSE c.h24 * 100 + c.m END,
        -- TimeText: HH:MM
        RIGHT('0' + CAST(c.h24 AS varchar(2)), 2) + N':'
            + RIGHT('0' + CAST(c.m AS varchar(2)), 2),
        -- TimeSeconds
        c.h24 * 3600 + c.m * 60 + c.s,
        -- TimeOfDay: HH:MM:SS
        RIGHT('0' + CAST(c.h24 AS varchar(2)), 2) + N':'
            + RIGHT('0' + CAST(c.m AS varchar(2)), 2) + N':'
            + RIGHT('0' + CAST(c.s AS varchar(2)), 2),

        -- Bin keys
        c.mod / 15,
        c.mod / 30,
        c.mod / 60,
        c.mod / 360,
        c.mod / 720,

        -- Bin labels (NULL when @IncludeLabels = 0)
        CASE WHEN @IncludeLabels = 1 THEN bl.Bin15mLabel  ELSE NULL END,
        CASE WHEN @IncludeLabels = 1 THEN bl.Bin30mLabel  ELSE NULL END,
        CASE WHEN @IncludeLabels = 1 THEN bl.Bin1hLabel   ELSE NULL END,
        CASE WHEN @IncludeLabels = 1 THEN bl.Bin6hLabel   ELSE NULL END,
        CASE WHEN @IncludeLabels = 1 THEN bl.Bin12hLabel  ELSE NULL END,
        CASE WHEN @IncludeLabels = 1
            THEN CASE WHEN c.h24 < 12 THEN N'Before Noon' ELSE N'After Noon' END
            ELSE NULL END,

        -- Period of Day
        pod.PeriodName,
        pod.PeriodSort,

        -- 12-hour period
        p12.PeriodName, p12.Bin, p12.BinSort,
        -- 6-hour period
        p6.PeriodName, p6.Bin, p6.BinSort,
        -- 30-minute period
        m30.PeriodName, m30.Bin, m30.BinSort,
        -- 15-minute period
        m15.PeriodName, m15.Bin, m15.BinSort

    FROM Core c
    -- Bin labels: precompute via CROSS APPLY to avoid repeating format logic
    CROSS APPLY (
        SELECT
            -- Half-open range labels (15m, 30m)
            bl15.lbl AS Bin15mLabel,
            bl30.lbl AS Bin30mLabel,
            -- Inclusive labels (1h, 6h, 12h)
            bl1h.lbl AS Bin1hLabel,
            bl6h.lbl AS Bin6hLabel,
            bl12h.lbl AS Bin12hLabel
        FROM (VALUES (
            -- Helper: format HH:MM from minute-of-day
            c.mod / 15 * 15,
            c.mod / 30 * 30,
            c.mod / 60 * 60,
            c.mod / 360 * 360,
            c.mod / 720 * 720
        )) bins(b15, b30, b1h, b6h, b12h)
        CROSS APPLY (VALUES (
            RIGHT('0' + CAST(bins.b15 / 60 AS varchar(2)), 2) + ':'
                + RIGHT('0' + CAST(bins.b15 % 60 AS varchar(2)), 2)
                + N'-'
                + RIGHT('0' + CAST((bins.b15 + 15) / 60 AS varchar(2)), 2) + ':'
                + RIGHT('0' + CAST((bins.b15 + 15) % 60 AS varchar(2)), 2)
        )) bl15(lbl)
        CROSS APPLY (VALUES (
            RIGHT('0' + CAST(bins.b30 / 60 AS varchar(2)), 2) + ':'
                + RIGHT('0' + CAST(bins.b30 % 60 AS varchar(2)), 2)
                + N'-'
                + RIGHT('0' + CAST((bins.b30 + 30) / 60 AS varchar(2)), 2) + ':'
                + RIGHT('0' + CAST((bins.b30 + 30) % 60 AS varchar(2)), 2)
        )) bl30(lbl)
        CROSS APPLY (VALUES (
            RIGHT('0' + CAST(bins.b1h / 60 AS varchar(2)), 2) + ':'
                + RIGHT('0' + CAST(bins.b1h % 60 AS varchar(2)), 2)
                + N'-'
                + RIGHT('0' + CAST(IIF(bins.b1h + 59 > 1439, 1439, bins.b1h + 59) / 60 AS varchar(2)), 2) + ':'
                + RIGHT('0' + CAST(IIF(bins.b1h + 59 > 1439, 1439, bins.b1h + 59) % 60 AS varchar(2)), 2)
        )) bl1h(lbl)
        CROSS APPLY (VALUES (
            RIGHT('0' + CAST(bins.b6h / 60 AS varchar(2)), 2) + ':'
                + RIGHT('0' + CAST(bins.b6h % 60 AS varchar(2)), 2)
                + N'-'
                + RIGHT('0' + CAST(IIF(bins.b6h + 359 > 1439, 1439, bins.b6h + 359) / 60 AS varchar(2)), 2) + ':'
                + RIGHT('0' + CAST(IIF(bins.b6h + 359 > 1439, 1439, bins.b6h + 359) % 60 AS varchar(2)), 2)
        )) bl6h(lbl)
        CROSS APPLY (VALUES (
            RIGHT('0' + CAST(bins.b12h / 60 AS varchar(2)), 2) + ':'
                + RIGHT('0' + CAST(bins.b12h % 60 AS varchar(2)), 2)
                + N'-'
                + RIGHT('0' + CAST(IIF(bins.b12h + 719 > 1439, 1439, bins.b12h + 719) / 60 AS varchar(2)), 2) + ':'
                + RIGHT('0' + CAST(IIF(bins.b12h + 719 > 1439, 1439, bins.b12h + 719) % 60 AS varchar(2)), 2)
        )) bl12h(lbl)
    ) bl
    -- Period joins (hour-based)
    JOIN @PeriodOfDay pod ON c.h24 BETWEEN pod.HourMin AND pod.HourMax
    JOIN @TwelveHour  p12 ON c.h24 BETWEEN p12.HourMin AND p12.HourMax
    JOIN @SixHour     p6  ON c.h24 BETWEEN p6.HourMin  AND p6.HourMax
    -- Period joins (minute-based)
    JOIN @ThirtyMin   m30 ON c.m BETWEEN m30.MinMin AND m30.MinMax
    JOIN @FifteenMin  m15 ON c.m BETWEEN m15.MinMin AND m15.MinMax
    ORDER BY c.n;

    ---------------------------------------------------------------------------
    -- Final output with column naming
    ---------------------------------------------------------------------------
    DECLARE @NormStyle nvarchar(20) = UPPER(LTRIM(RTRIM(ISNULL(@ColumnNamingStyle, 'Spaced'))));
    DECLARE @UseSpacedNames bit = CASE
        WHEN @NormStyle LIKE 'PASCAL%' THEN 0
        ELSE 1 END;

    DECLARE @Cols TABLE (
        Ordinal    int IDENTITY(1,1),
        PascalName nvarchar(50),
        SpacedName nvarchar(50),
        IncludeAlways bit
    );

    INSERT INTO @Cols (PascalName, SpacedName, IncludeAlways) VALUES
    -- Core
    (N'Time',                   N'Time',                     1),
    (N'Hour24',                 N'Hour 24',                  1),
    (N'Hour12',                 N'Hour 12',                  1),
    (N'Minute',                 N'Minute',                   1),
    (N'Second',                 N'Second',                   1),
    (N'AmPm',                   N'AM PM',                    1),
    (N'Hour12Text',             N'Hour 12 Text',             1),
    (N'TimeKey',                N'Time Key',                 1),
    (N'TimeText',               N'Time Text',                1),
    (N'TimeSeconds',            N'Time Seconds',             1),
    (N'TimeOfDay',              N'Time of Day',              1),
    -- Bin keys
    (N'Bin15mKey',              N'Bin 15m Key',              1),
    (N'Bin30mKey',              N'Bin 30m Key',              1),
    (N'Bin1hKey',               N'Bin 1h Key',               1),
    (N'Bin6hKey',               N'Bin 6h Key',               1),
    (N'Bin12hKey',              N'Bin 12h Key',              1),
    -- Bin labels
    (N'Bin15mLabel',            N'Bin 15m Label',            0),
    (N'Bin30mLabel',            N'Bin 30m Label',            0),
    (N'Bin1hLabel',             N'Bin 1h Label',             0),
    (N'Bin6hLabel',             N'Bin 6h Label',             0),
    (N'Bin12hLabel',            N'Bin 12h Label',            0),
    (N'Bin12hName',             N'Bin 12h Name',             0),
    -- Period of Day
    (N'PeriodOfDayName',        N'Period of Day Name',       1),
    (N'PeriodOfDayNameSort',    N'Period of Day Name Sort',  1),
    -- 12-hour
    (N'TwelveHourPeriodName',   N'12 Hour Period Name',      1),
    (N'TwelveHourBin',          N'12 Hour Bin',              1),
    (N'TwelveHourBinSort',      N'12 Hour Bin Sort',         1),
    -- 6-hour
    (N'SixHourPeriodName',      N'6 Hour Period Name',       1),
    (N'SixHourBin',             N'6 Hour Bin',               1),
    (N'SixHourBinSort',         N'6 Hour Bin Sort',          1),
    -- 30-minute
    (N'ThirtyMinutePeriodName', N'30 Minute Period Name',    1),
    (N'ThirtyMinuteBin',        N'30 Minute Bin',            1),
    (N'ThirtyMinuteBinSort',    N'30 Minute Bin Sort',       1),
    -- 15-minute
    (N'FifteenMinutePeriodName',N'15 Minute Period Name',    1),
    (N'FifteenMinuteBin',       N'15 Minute Bin',            1),
    (N'FifteenMinuteBinSort',   N'15 Minute Bin Sort',       1);

    -- Build dynamic column list
    DECLARE @colList nvarchar(max) = N'';

    SELECT @colList = @colList +
        CASE
            WHEN @UseSpacedNames = 1 AND PascalName <> SpacedName
                THEN QUOTENAME(PascalName) + N' AS ' + QUOTENAME(SpacedName)
            ELSE QUOTENAME(PascalName)
        END + N', '
    FROM @Cols
    WHERE IncludeAlways = 1
        OR (@IncludeLabels = 1 AND IncludeAlways = 0)
    ORDER BY Ordinal;

    -- Exclude Second column for minute grain (PascalName = SpacedName, so never aliased)
    IF @IsSecond = 0
        SET @colList = REPLACE(@colList, QUOTENAME(N'Second') + N', ', N'');

    -- Trim trailing comma
    SET @colList = LEFT(@colList, LEN(@colList) - 1);

    -- Build final SQL
    DECLARE @sql nvarchar(max);

    IF @OutputTable IS NOT NULL
    BEGIN
        DECLARE @SchemaName sysname = ISNULL(PARSENAME(@OutputTable, 2), N'dbo');
        DECLARE @ObjName   sysname = PARSENAME(@OutputTable, 1);

        IF @ObjName IS NULL
        BEGIN
            RAISERROR(N'Invalid table name: %s', 16, 1, @OutputTable);
            DROP TABLE #TimeTable;
            RETURN;
        END;

        DECLARE @FullName nvarchar(256) = QUOTENAME(@SchemaName) + N'.' + QUOTENAME(@ObjName);

        IF OBJECT_ID(@FullName) IS NOT NULL
        BEGIN
            SET @sql = N'DROP TABLE ' + @FullName;
            EXEC sp_executesql @sql;
        END;

        SET @sql = N'SELECT ' + @colList + N' INTO ' + @FullName + N' FROM #TimeTable ORDER BY [TimeKey]';
        EXEC sp_executesql @sql;
        SET @rowCountMsg = CAST(@@ROWCOUNT AS nvarchar(10));

        PRINT N'Created table ' + @FullName + N' with ' + @rowCountMsg + N' rows.';
    END
    ELSE
    BEGIN
        SET @sql = N'SELECT ' + @colList + N' FROM #TimeTable ORDER BY [TimeKey]';
        EXEC sp_executesql @sql;
    END;

    DROP TABLE #TimeTable;
END;
