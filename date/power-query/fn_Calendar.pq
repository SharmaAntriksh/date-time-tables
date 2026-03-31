/*
    fn_Calendar - Base calendar columns and as-of relative offsets.

    Parameters:
    StartDate   : date    — first date in the table
    EndDate     : date    — last date in the table
    AsOfDate    : date    — reference date for relative offsets

    Returns: table with base calendar columns
*/
( StartDate as date, EndDate as date, AsOfDate as date ) as table =>
    let

        // Excel serial-date epoch (1899-12-30) — intentional Lotus 1-2-3 leap-year bug
        ExcelEpoch = #date ( 1899, 12, 30 ),
        // Generate date list
        DayCount = Duration.Days ( EndDate - StartDate ) + 1,
        DateList = List.Dates ( StartDate, DayCount, #duration ( 1, 0, 0, 0 ) ),
        // Build base table
        Source = Table.FromColumns ( { DateList }, type table [ Date = date ] ),
        // --- Core date parts ---
        AddYear = Table.AddColumn ( Source, "Year", each Date.Year ( [Date] ), Int32.Type ),
        AddMonth = Table.AddColumn ( AddYear, "Month", each Date.Month ( [Date] ), Int32.Type ),
        AddDay = Table.AddColumn ( AddMonth, "Day", each Date.Day ( [Date] ), Int32.Type ),
        AddQuarter = Table.AddColumn (
            AddDay,
            "Quarter",
            each Date.QuarterOfYear ( [Date] ),
            Int32.Type
        ),
        // DateKey: YYYYMMDD integer
        AddDateKey = Table.AddColumn (
            AddQuarter,
            "DateKey",
            each [Year] * 10000 + [Month] * 100 + [Day],
            Int64.Type
        ),
        // DateSerialNumber: Excel-like serial number
        AddSeqDay = Table.AddColumn (
            AddDateKey,
            "DateSerialNumber",
            each Duration.Days ( [Date] - ExcelEpoch ),
            Int32.Type
        ),
        // --- Name columns ---
        AddMonthName = Table.AddColumn (
            AddSeqDay,
            "MonthName",
            each Date.MonthName ( [Date] ),
            type text
        ),
        AddMonthShort = Table.AddColumn (
            AddMonthName,
            "MonthShort",
            each Text.Start ( [MonthName], 3 ),
            type text
        ),
        AddDayName = Table.AddColumn (
            AddMonthShort,
            "DayName",
            each Date.DayOfWeekName ( [Date] ),
            type text
        ),
        AddDayShort = Table.AddColumn (
            AddDayName,
            "DayShort",
            each Text.Start ( [DayName], 3 ),
            type text
        ),
        // --- DayOfYear ---
        AddDayOfYear = Table.AddColumn (
            AddDayShort,
            "DayOfYear",
            each Date.DayOfYear ( [Date] ),
            Int32.Type
        ),
        // --- Composite labels ---
        AddMonthYear = Table.AddColumn (
            AddDayOfYear,
            "MonthYear",
            each [MonthShort] & " " & Text.From ( [Year] ),
            type text
        ),
        AddMonthYearKey = Table.AddColumn (
            AddMonthYear,
            "MonthYearKey",
            each [Year] * 100 + [Month],
            Int32.Type
        ),
        // --- BI convenience keys ---
        AddYearQuarterKey = Table.AddColumn (
            AddMonthYearKey,
            "YearQuarterKey",
            each [Year] * 10 + [Quarter],
            Int32.Type
        ),
        AddQuarterYear = Table.AddColumn (
            AddYearQuarterKey,
            "QuarterYear",
            each "Q" & Text.From ( [Quarter] ) & " " & Text.From ( [Year] ),
            type text
        ),
        // --- Contiguous indexes ---
        AddCalMonthIndex = Table.AddColumn (
            AddQuarterYear,
            "CalendarMonthIndex",
            each [Year] * 12 + [Month],
            Int32.Type
        ),
        AddCalQuarterIndex = Table.AddColumn (
            AddCalMonthIndex,
            "CalendarQuarterIndex",
            each [Year] * 4 + [Quarter],
            Int32.Type
        ),
        // --- DayOfWeek: 0 = Sunday, 1 = Monday, ... 6 = Saturday ---
        // Date.DayOfWeek with Day.Sunday as firstDayOfWeek returns 0=Sun..6=Sat
        AddDayOfWeek = Table.AddColumn (
            AddCalQuarterIndex,
            "DayOfWeek",
            each Date.DayOfWeek ( [Date], Day.Sunday ),
            Int32.Type
        ),
        AddIsWeekend = Table.AddColumn (
            AddDayOfWeek,
            "IsWeekend",
            each [DayOfWeek] = 0 or [DayOfWeek] = 6,
            type logical
        ),
        AddIsBusinessDay = Table.AddColumn (
            AddIsWeekend,
            "IsBusinessDay",
            each not [IsWeekend],
            type logical
        ),
        // --- Month start/end ---
        AddMonthStartDate = Table.AddColumn (
            AddIsBusinessDay,
            "MonthStartDate",
            each Date.StartOfMonth ( [Date] ),
            type date
        ),
        AddMonthEndDate = Table.AddColumn (
            AddMonthStartDate,
            "MonthEndDate",
            each Date.EndOfMonth ( [Date] ),
            type date
        ),
        // --- Quarter start/end ---
        AddQuarterStartDate = Table.AddColumn (
            AddMonthEndDate,
            "QuarterStartDate",
            each Date.StartOfQuarter ( [Date] ),
            type date
        ),
        AddQuarterEndDate = Table.AddColumn (
            AddQuarterStartDate,
            "QuarterEndDate",
            each Date.EndOfQuarter ( [Date] ),
            type date
        ),
        // --- Boolean flags ---
        AddIsMonthStart = Table.AddColumn (
            AddQuarterEndDate,
            "IsMonthStart",
            each [Day] = 1,
            type logical
        ),
        AddIsMonthEnd = Table.AddColumn (
            AddIsMonthStart,
            "IsMonthEnd",
            each [Date] = [MonthEndDate],
            type logical
        ),
        AddIsQuarterStart = Table.AddColumn (
            AddIsMonthEnd,
            "IsQuarterStart",
            each [Date] = [QuarterStartDate],
            type logical
        ),
        AddIsQuarterEnd = Table.AddColumn (
            AddIsQuarterStart,
            "IsQuarterEnd",
            each [Date] = [QuarterEndDate],
            type logical
        ),
        AddIsYearStart = Table.AddColumn (
            AddIsQuarterEnd,
            "IsYearStart",
            each [Month] = 1 and [Day] = 1,
            type logical
        ),
        AddIsYearEnd = Table.AddColumn (
            AddIsYearStart,
            "IsYearEnd",
            each [Month] = 12 and [Day] = 31,
            type logical
        ),
        // --- WeekOfMonth (day-based: days 1-7 = week 1, 8-14 = week 2, ...) ---
        AddWeekOfMonth = Table.AddColumn (
            AddIsYearEnd,
            "WeekOfMonth",
            each Number.IntegerDivide ( [Day] - 1, 7 ) + 1,
            Int32.Type
        ),
        // --- Next/Previous Business Day ---
        // Build a lookup table: each date maps to its next and previous business day.
        // Uses day-offset arithmetic instead of per-row list scans.
        BizDayLookup =
            let


                // For each date, walk forward/backward by 1-3 days to find the nearest biz day.
                // Max gap is 3 (Fri->Mon or around a weekend).
                Lookup = List.Transform (
                    DateList,
                    each
                        let
                            d = _,
                            dow = Date.DayOfWeek ( d, Day.Sunday ),                                // 0=Sun..6=Sat
                            // Next business day strictly AFTER d
                            nextOff =
                                if dow = 5 then
                                    3                                                              // Friday -> Monday
                                else if dow = 6 then
                                    2                                                              // Saturday -> Monday
                                else
                                    1,                                                             // Sun-Thu -> next day
                            // Previous business day strictly BEFORE d
                            prevOff =
                                if dow = 0 then
                                    2                                                              // Sunday -> Friday
                                else if dow = 1 then
                                    3                                                              // Monday -> Friday
                                else
                                    1                                                              // Tue-Sat -> prev day
                        in
                            [
                                Date   = d,
                                NextBD = Date.AddDays ( d, nextOff ),
                                PrevBD = Date.AddDays ( d, - prevOff )
                            ]
                ),
                Tbl = Table.FromRecords (
                    Lookup,
                    type table [ Date = date, NextBD = date, PrevBD = date ]
                )
            in
                Table.Buffer ( Tbl ),
        AddNextBizDay = Table.NestedJoin (
            AddWeekOfMonth,
            { "Date" },
            BizDayLookup,
            { "Date" },
            "_BD",
            JoinKind.LeftOuter
        ),
        ExpandBizDay = Table.ExpandTableColumn ( AddNextBizDay, "_BD", { "NextBD", "PrevBD" } ),
        RenameBizDay = Table.RenameColumns (
            ExpandBizDay,
            { { "NextBD", "NextBusinessDay" }, { "PrevBD", "PreviousBusinessDay" } }
        ),
        // --- As-of relative columns ---
        AsOfQuarter = Date.QuarterOfYear ( AsOfDate ),
        AsOfCalMonthIndex = Date.Year ( AsOfDate ) * 12 + Date.Month ( AsOfDate ),
        AsOfCalQuarterIndex = Date.Year ( AsOfDate ) * 4 + AsOfQuarter,
        AddIsToday = Table.AddColumn (
            RenameBizDay,
            "IsToday",
            each [Date] = AsOfDate,
            type logical
        ),
        AddIsCurrentYear = Table.AddColumn (
            AddIsToday,
            "IsCurrentYear",
            each [Year] = Date.Year ( AsOfDate ),
            type logical
        ),
        AddIsCurrentMonth = Table.AddColumn (
            AddIsCurrentYear,
            "IsCurrentMonth",
            each [Year] = Date.Year ( AsOfDate ) and [Month] = Date.Month ( AsOfDate ),
            type logical
        ),
        AddIsCurrentQuarter = Table.AddColumn (
            AddIsCurrentMonth,
            "IsCurrentQuarter",
            each [Year] = Date.Year ( AsOfDate ) and [Quarter] = AsOfQuarter,
            type logical
        ),
        AddCurrentDayOffset = Table.AddColumn (
            AddIsCurrentQuarter,
            "CurrentDayOffset",
            each Duration.Days ( [Date] - AsOfDate ),
            Int32.Type
        ),
        AddYearOffset = Table.AddColumn (
            AddCurrentDayOffset,
            "YearOffset",
            each [Year] - Date.Year ( AsOfDate ),
            Int32.Type
        ),
        AddCalMonthOffset = Table.AddColumn (
            AddYearOffset,
            "CalendarMonthOffset",
            each [CalendarMonthIndex] - AsOfCalMonthIndex,
            Int32.Type
        ),
        AddCalQuarterOffset = Table.AddColumn (
            AddCalMonthOffset,
            "CalendarQuarterOffset",
            each [CalendarQuarterIndex] - AsOfCalQuarterIndex,
            Int32.Type
        )
    in
        AddCalQuarterOffset