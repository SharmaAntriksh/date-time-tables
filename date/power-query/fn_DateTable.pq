// fn_DateTable
// Self-contained date dimension table. Combines base calendar, ISO weeks,
// monthly fiscal, and optional weekly fiscal (4-4-5 / 4-5-4 / 5-4-4).
//
// Single-file alternative to the modular fn_Orchestrate setup.
//
// Parameters:
//   StartDate            : date    — first date in the table
//   EndDate              : date    — last date in the table
//   AsOfDate             : date    — reference date for all relative offsets
//   FiscalStartMonth     : number  — first month of the fiscal year (1-12)
//   IncludeWeeklyFiscal  : logical — true to include 4-4-5 weekly fiscal columns
//   FirstDayOfWeek       : number  — 0=Sunday .. 6=Saturday (weekly fiscal)
//   WeeklyType           : text    — "Last" or "Nearest" (weekly fiscal)
//   QuarterWeekType      : text    — "445", "454", or "544" (weekly fiscal)
//   TypeStartFiscalYear  : number  — 0=start-year, 1=end-year labeling (weekly fiscal)
//   ColumnNamingStyle    : text    — "Spaced" (default) or "PascalCase"
//
// Returns: complete date dimension table

(
    StartDate as date,
    EndDate as date,
    AsOfDate as date,
    FiscalStartMonth as number,
    IncludeWeeklyFiscal as logical,
    FirstDayOfWeek as number,
    WeeklyType as text,
    QuarterWeekType as text,
    TypeStartFiscalYear as number,
    optional ColumnNamingStyle as text
) as table =>
let
    // Shared parameter normalization
    FYStartMonth = List.Max({1, List.Min({12, FiscalStartMonth})}),
    NormWeeklyType = if Text.Upper(Text.Trim(WeeklyType)) = "NEAREST" then "Nearest" else "Last",
    NormQuarterWeekType = if List.Contains({"445","454","544"}, Text.Trim(QuarterWeekType))
                          then Text.Trim(QuarterWeekType) else "445",

    // ═══════════════════════════════════════════════════════════════
    // PHASE 1 — BASE CALENDAR
    // ═══════════════════════════════════════════════════════════════

    ExcelEpoch = #date(1899, 12, 30),

    DayCount = Duration.Days(EndDate - StartDate) + 1,
    DateList = List.Dates(StartDate, DayCount, #duration(1, 0, 0, 0)),

    Source = Table.FromColumns(
        {DateList},
        type table [Date = date]
    ),

    // Core date parts
    AddYear       = Table.AddColumn(Source,    "Year",    each Date.Year([Date]),    Int32.Type),
    AddMonth      = Table.AddColumn(AddYear,   "Month",   each Date.Month([Date]),   Int32.Type),
    AddDay        = Table.AddColumn(AddMonth,  "Day",     each Date.Day([Date]),     Int32.Type),
    AddQuarter    = Table.AddColumn(AddDay,    "Quarter", each Date.QuarterOfYear([Date]), Int32.Type),

    AddDateKey = Table.AddColumn(AddQuarter, "DateKey",
        each [Year] * 10000 + [Month] * 100 + [Day], Int64.Type),
    AddSeqDay = Table.AddColumn(AddDateKey, "DateSerialNumber",
        each Duration.Days([Date] - ExcelEpoch), Int32.Type),

    // Name columns
    AddMonthName  = Table.AddColumn(AddSeqDay,     "MonthName",  each Date.MonthName([Date]),       type text),
    AddMonthShort = Table.AddColumn(AddMonthName,  "MonthShort", each Text.Start([MonthName], 3), type text),
    AddDayName    = Table.AddColumn(AddMonthShort, "DayName",    each Date.DayOfWeekName([Date]),    type text),
    AddDayShort   = Table.AddColumn(AddDayName,    "DayShort",   each Text.Start([DayName], 3), type text),

    AddDayOfYear = Table.AddColumn(AddDayShort, "DayOfYear",
        each Date.DayOfYear([Date]), Int32.Type),

    // Composite labels
    AddMonthYear = Table.AddColumn(AddDayOfYear, "MonthYear",
        each [MonthShort] & " " & Text.From([Year]), type text),
    AddMonthYearKey = Table.AddColumn(AddMonthYear, "MonthYearKey",
        each [Year] * 100 + [Month], Int32.Type),

    // BI convenience keys
    AddYearQuarterKey = Table.AddColumn(AddMonthYearKey, "YearQuarterKey",
        each [Year] * 10 + [Quarter], Int32.Type),
    AddQuarterYear = Table.AddColumn(AddYearQuarterKey, "QuarterYear",
        each "Q" & Text.From([Quarter]) & " " & Text.From([Year]), type text),

    // Contiguous indexes
    AddCalMonthIndex = Table.AddColumn(AddQuarterYear, "CalendarMonthIndex",
        each [Year] * 12 + [Month], Int32.Type),
    AddCalQuarterIndex = Table.AddColumn(AddCalMonthIndex, "CalendarQuarterIndex",
        each [Year] * 4 + [Quarter], Int32.Type),

    // DayOfWeek: 0=Sunday .. 6=Saturday
    AddDayOfWeek = Table.AddColumn(AddCalQuarterIndex, "DayOfWeek",
        each Date.DayOfWeek([Date], Day.Sunday), Int32.Type),
    AddIsWeekend = Table.AddColumn(AddDayOfWeek, "IsWeekend",
        each [DayOfWeek] = 0 or [DayOfWeek] = 6, type logical),
    AddIsBusinessDay = Table.AddColumn(AddIsWeekend, "IsBusinessDay",
        each not [IsWeekend], type logical),

    // Month start/end
    AddMonthStartDate = Table.AddColumn(AddIsBusinessDay, "MonthStartDate",
        each Date.StartOfMonth([Date]), type date),
    AddMonthEndDate = Table.AddColumn(AddMonthStartDate, "MonthEndDate",
        each Date.EndOfMonth([Date]), type date),

    // Quarter start/end
    AddQuarterStartDate = Table.AddColumn(AddMonthEndDate, "QuarterStartDate",
        each Date.StartOfQuarter([Date]), type date),
    AddQuarterEndDate = Table.AddColumn(AddQuarterStartDate, "QuarterEndDate",
        each Date.EndOfQuarter([Date]), type date),

    // Boolean flags
    AddIsMonthStart   = Table.AddColumn(AddQuarterEndDate,  "IsMonthStart",   each [Day] = 1, type logical),
    AddIsMonthEnd     = Table.AddColumn(AddIsMonthStart,    "IsMonthEnd",     each [Date] = [MonthEndDate], type logical),
    AddIsQuarterStart = Table.AddColumn(AddIsMonthEnd,      "IsQuarterStart", each [Date] = [QuarterStartDate], type logical),
    AddIsQuarterEnd   = Table.AddColumn(AddIsQuarterStart,  "IsQuarterEnd",   each [Date] = [QuarterEndDate], type logical),
    AddIsYearStart    = Table.AddColumn(AddIsQuarterEnd,    "IsYearStart",    each [Month] = 1 and [Day] = 1, type logical),
    AddIsYearEnd      = Table.AddColumn(AddIsYearStart,     "IsYearEnd",      each [Month] = 12 and [Day] = 31, type logical),

    // WeekOfMonth (day-based: days 1-7 = week 1, 8-14 = week 2, ...)
    AddWeekOfMonth = Table.AddColumn(AddIsYearEnd, "WeekOfMonth",
        each Number.IntegerDivide([Day] - 1, 7) + 1, Int32.Type),

    // Next/Previous Business Day via lookup join
    BizDayLookup = let
        Lookup = List.Transform(DateList, each
            let
                d = _,
                dow = Date.DayOfWeek(d, Day.Sunday),
                nextOff = if dow = 5 then 3       // Friday -> Monday
                          else if dow = 6 then 2  // Saturday -> Monday
                          else 1,                  // Sun-Thu -> next day
                prevOff = if dow = 0 then 2        // Sunday -> Friday
                          else if dow = 1 then 3   // Monday -> Friday
                          else 1                    // Tue-Sat -> prev day
            in
                [Date = d, NextBD = Date.AddDays(d, nextOff), PrevBD = Date.AddDays(d, -prevOff)]
        ),
        Tbl = Table.FromRecords(Lookup, type table [Date = date, NextBD = date, PrevBD = date])
    in
        Table.Buffer(Tbl),

    AddNextBizDay = Table.NestedJoin(AddWeekOfMonth, {"Date"}, BizDayLookup, {"Date"}, "_BD", JoinKind.LeftOuter),
    ExpandBizDay = Table.ExpandTableColumn(AddNextBizDay, "_BD", {"NextBD", "PrevBD"}),
    RenameBizDay = Table.RenameColumns(ExpandBizDay, {{"NextBD", "NextBusinessDay"}, {"PrevBD", "PreviousBusinessDay"}}),

    // As-of relative columns
    AsOfQuarter = Date.QuarterOfYear(AsOfDate),
    AsOfCalMonthIndex = Date.Year(AsOfDate) * 12 + Date.Month(AsOfDate),
    AsOfCalQuarterIndex = Date.Year(AsOfDate) * 4 + AsOfQuarter,

    AddIsToday = Table.AddColumn(RenameBizDay, "IsToday",
        each [Date] = AsOfDate, type logical),
    AddIsCurrentYear = Table.AddColumn(AddIsToday, "IsCurrentYear",
        each [Year] = Date.Year(AsOfDate), type logical),
    AddIsCurrentMonth = Table.AddColumn(AddIsCurrentYear, "IsCurrentMonth",
        each [Year] = Date.Year(AsOfDate) and [Month] = Date.Month(AsOfDate), type logical),
    AddIsCurrentQuarter = Table.AddColumn(AddIsCurrentMonth, "IsCurrentQuarter",
        each [Year] = Date.Year(AsOfDate) and [Quarter] = AsOfQuarter, type logical),

    AddCurrentDayOffset = Table.AddColumn(AddIsCurrentQuarter, "CurrentDayOffset",
        each Duration.Days([Date] - AsOfDate), Int32.Type),
    AddYearOffset = Table.AddColumn(AddCurrentDayOffset, "YearOffset",
        each [Year] - Date.Year(AsOfDate), Int32.Type),
    AddCalMonthOffset = Table.AddColumn(AddYearOffset, "CalendarMonthOffset",
        each [CalendarMonthIndex] - AsOfCalMonthIndex, Int32.Type),
    AddCalQuarterOffset = Table.AddColumn(AddCalMonthOffset, "CalendarQuarterOffset",
        each [CalendarQuarterIndex] - AsOfCalQuarterIndex, Int32.Type),

    T_Calendar = AddCalQuarterOffset,

    // ═══════════════════════════════════════════════════════════════
    // PHASE 2 — ISO WEEKS
    // ═══════════════════════════════════════════════════════════════

    // Monday of ISO week 1 in year 2000; any Monday works as an anchor
    ISOWeekRef = #date(2000, 1, 3),
    AsOfWeekday = Date.DayOfWeek(AsOfDate, Day.Monday),
    AsOfWeekStart = Date.AddDays(AsOfDate, -AsOfWeekday),
    AsOfISOYearWeekIndex = Number.IntegerDivide(Duration.Days(AsOfWeekStart - ISOWeekRef), 7),

    AddISOWeekNumber = Table.AddColumn(T_Calendar, "ISOWeekNumber", each
        let
            thursday = Date.AddDays([Date], 3 - Date.DayOfWeek([Date], Day.Monday)),
            jan4 = #date(Date.Year(thursday), 1, 4),
            jan4Monday = Date.AddDays(jan4, -Date.DayOfWeek(jan4, Day.Monday)),
            weekNum = Number.IntegerDivide(Duration.Days([Date] - jan4Monday), 7) + 1
        in
            weekNum,
        Int32.Type
    ),

    AddISOYear = Table.AddColumn(AddISOWeekNumber, "ISOYear", each
        let
            thursday = Date.AddDays([Date], 3 - Date.DayOfWeek([Date], Day.Monday))
        in
            Date.Year(thursday),
        Int32.Type
    ),

    AddISOWeekStartDate = Table.AddColumn(AddISOYear, "ISOWeekStartDate", each
        Date.AddDays([Date], -Date.DayOfWeek([Date], Day.Monday)),
        type date
    ),

    AddISOWeekEndDate = Table.AddColumn(AddISOWeekStartDate, "ISOWeekEndDate", each
        Date.AddDays([ISOWeekStartDate], 6),
        type date
    ),

    AddISOYearWeekIndex = Table.AddColumn(AddISOWeekEndDate, "ISOYearWeekIndex", each
        Number.IntegerDivide(Duration.Days([ISOWeekStartDate] - ISOWeekRef), 7),
        Int32.Type
    ),

    AddISOWeekOffset = Table.AddColumn(AddISOYearWeekIndex, "ISOWeekOffset", each
        [ISOYearWeekIndex] - AsOfISOYearWeekIndex,
        Int32.Type
    ),

    // ═══════════════════════════════════════════════════════════════
    // PHASE 3 — MONTHLY FISCAL
    // ═══════════════════════════════════════════════════════════════

    FYEndAdd = if FYStartMonth = 1 then 0 else 1,

    AddFiscalYearStartYear = Table.AddColumn(AddISOWeekOffset, "FiscalYearStartYear", each
        if [Month] >= FYStartMonth then [Year] else [Year] - 1,
        Int32.Type
    ),

    AddFiscalMonthNumber = Table.AddColumn(AddFiscalYearStartYear, "FiscalMonthNumber", each
        Number.Mod([Month] - FYStartMonth + 12, 12) + 1,
        Int32.Type
    ),

    AddFiscalQuarterNumber = Table.AddColumn(AddFiscalMonthNumber, "FiscalQuarterNumber", each
        Number.IntegerDivide([FiscalMonthNumber] - 1, 3) + 1,
        Int32.Type
    ),

    AddFiscalYear = Table.AddColumn(AddFiscalQuarterNumber, "FiscalYear", each
        [FiscalYearStartYear] + FYEndAdd,
        Int32.Type
    ),

    AddFiscalYearRange = Table.AddColumn(AddFiscalYear, "FiscalYearRange", each
        if FYStartMonth = 1 then Text.From([FiscalYearStartYear])
        else Text.From([FiscalYearStartYear]) & "-" & Text.From([FiscalYear]),
        type text
    ),

    AddFiscalYearLabel = Table.AddColumn(AddFiscalYearRange, "FiscalYearLabel", each
        "FY " & Text.From([FiscalYear]),
        type text
    ),

    AddFiscalQuarterLabel = Table.AddColumn(AddFiscalYearLabel, "FiscalQuarterLabel", each
        "Q" & Text.From([FiscalQuarterNumber]) & " FY" & Text.From([FiscalYear]),
        type text
    ),

    AddFiscalMonthIndex = Table.AddColumn(AddFiscalQuarterLabel, "FiscalMonthIndex", each
        [FiscalYearStartYear] * 12 + [FiscalMonthNumber],
        Int32.Type
    ),

    AddFiscalQuarterIndex = Table.AddColumn(AddFiscalMonthIndex, "FiscalQuarterIndex", each
        [FiscalYearStartYear] * 4 + [FiscalQuarterNumber],
        Int32.Type
    ),

    AddFiscalYearStartDate = Table.AddColumn(AddFiscalQuarterIndex, "FiscalYearStartDate", each
        #date([FiscalYearStartYear], FYStartMonth, 1),
        type date
    ),

    AddFiscalYearEndDate = Table.AddColumn(AddFiscalYearStartDate, "FiscalYearEndDate", each
        Date.AddDays(Date.AddYears([FiscalYearStartDate], 1), -1),
        type date
    ),

    AddFiscalQuarterStartDate = Table.AddColumn(AddFiscalYearEndDate, "FiscalQuarterStartDate", each
        let
            monthsToAdd = ([FiscalQuarterNumber] - 1) * 3,
            rawMonth = FYStartMonth + monthsToAdd,
            qYear = [FiscalYearStartYear] + Number.IntegerDivide(rawMonth - 1, 12),
            qMonth = Number.Mod(rawMonth - 1, 12) + 1
        in
            #date(qYear, qMonth, 1),
        type date
    ),

    AddFiscalQuarterEndDate = Table.AddColumn(AddFiscalQuarterStartDate, "FiscalQuarterEndDate", each
        Date.AddDays(Date.AddMonths([FiscalQuarterStartDate], 3), -1),
        type date
    ),

    AddIsFiscalYearStart = Table.AddColumn(AddFiscalQuarterEndDate, "IsFiscalYearStart", each
        [Date] = [FiscalYearStartDate], type logical),
    AddIsFiscalYearEnd = Table.AddColumn(AddIsFiscalYearStart, "IsFiscalYearEnd", each
        [Date] = [FiscalYearEndDate], type logical),
    AddIsFiscalQuarterStart = Table.AddColumn(AddIsFiscalYearEnd, "IsFiscalQuarterStart", each
        [Date] = [FiscalQuarterStartDate], type logical),
    AddIsFiscalQuarterEnd = Table.AddColumn(AddIsFiscalQuarterStart, "IsFiscalQuarterEnd", each
        [Date] = [FiscalQuarterEndDate], type logical),

    AsOfFiscalYearStartYear = if Date.Month(AsOfDate) >= FYStartMonth then Date.Year(AsOfDate)
                              else Date.Year(AsOfDate) - 1,
    AsOfFiscalMonthNumber = Number.Mod(Date.Month(AsOfDate) - FYStartMonth + 12, 12) + 1,
    AsOfFiscalQuarterNumber = Number.IntegerDivide(AsOfFiscalMonthNumber - 1, 3) + 1,
    AsOfFiscalMonthIndex = AsOfFiscalYearStartYear * 12 + AsOfFiscalMonthNumber,
    AsOfFiscalQuarterIndex = AsOfFiscalYearStartYear * 4 + AsOfFiscalQuarterNumber,

    AddFiscalMonthOffset = Table.AddColumn(AddIsFiscalQuarterEnd, "FiscalMonthOffset", each
        [FiscalMonthIndex] - AsOfFiscalMonthIndex,
        Int32.Type
    ),

    AddFiscalQuarterOffset = Table.AddColumn(AddFiscalMonthOffset, "FiscalQuarterOffset", each
        [FiscalQuarterIndex] - AsOfFiscalQuarterIndex,
        Int32.Type
    ),

    // ═══════════════════════════════════════════════════════════════
    // PHASE 4 — WEEKLY FISCAL (conditional)
    // ═══════════════════════════════════════════════════════════════

    T4 = if IncludeWeeklyFiscal then
        let
            FDOW = Number.Mod(FirstDayOfWeek, 7),
            WType = NormWeeklyType,
            QWT = NormQuarterWeekType,
            TSY = if TypeStartFiscalYear = 0 then 0 else 1,

            W1 = Number.FromText(Text.At(QWT, 0)),
            W2 = Number.FromText(Text.At(QWT, 1)),

            // Weekday number (1..7) relative to FirstDayOfWeek
            WeekdayNum = (d as date) as number =>
                let
                    sun0 = Date.DayOfWeek(d, Day.Sunday),
                    pos0 = Number.Mod(sun0 - FDOW + 7, 7)
                in
                    pos0 + 1,

            // Fiscal year start date for a given FW year number
            FYBoundaryStart = (fwYearNumber as number) as date =>
                let
                    offsetFY = if FYStartMonth > 1 then 1 else 0,
                    startCalYear = fwYearNumber - (offsetFY * TSY),
                    firstDayOfMonth = #date(startCalYear, FYStartMonth, 1),
                    dow = WeekdayNum(firstDayOfMonth),
                    offset = if WType = "Last" then 1 - dow
                             else if dow >= 5 then 8 - dow
                             else 1 - dow
                in
                    Date.AddDays(firstDayOfMonth, offset),

            // Build bounds table: FW year -> (start, end)
            FWStartYear = List.Min(Table.Column(AddFiscalQuarterOffset, "Year")) - 1,
            FWEndYear = List.Max(Table.Column(AddFiscalQuarterOffset, "Year")) + 2,
            YearList = {FWStartYear..FWEndYear},

            BoundsTable = List.Transform(YearList, each
                let
                    y = _,
                    s = FYBoundaryStart(y),
                    nextS = FYBoundaryStart(y + 1),
                    e = Date.AddDays(nextS, -1)
                in
                    [FWYear = y, FWStart = s, FWEnd = e]
            ),

            // Date-to-FWYear lookup via hash join
            DateToFWYear = Table.Buffer(
                let
                    Expanded = List.Transform(BoundsTable, each
                        let
                            b = _,
                            days = Duration.Days(b[FWEnd] - b[FWStart]) + 1,
                            dates = List.Dates(b[FWStart], days, #duration(1, 0, 0, 0))
                        in
                            List.Transform(dates, each [Date = _, FWYear = b[FWYear], FWStart = b[FWStart], FWEnd = b[FWEnd]])
                    ),
                    Flat = List.Combine(Expanded)
                in
                    Table.FromRecords(Flat, type table [Date = date, FWYear = Int32.Type, FWStart = date, FWEnd = date])
            ),

            JoinFWYear = Table.NestedJoin(AddFiscalQuarterOffset, {"Date"}, DateToFWYear, {"Date"}, "_FW", JoinKind.LeftOuter),
            ExpandFWYear = Table.ExpandTableColumn(JoinFWYear, "_FW", {"FWYear", "FWStart", "FWEnd"}),
            AddFWYearNumber = Table.RenameColumns(ExpandFWYear, {{"FWYear", "FWYearNumber"}, {"FWStart", "FWStartOfYear"}, {"FWEnd", "FWEndOfYear"}}),

            AddFWYearLabel = Table.AddColumn(AddFWYearNumber, "FWYearLabel", each
                "FY " & Text.From([FWYearNumber]),
                type text
            ),

            // Day/week within fiscal year
            AddFWDayOfYear = Table.AddColumn(AddFWYearLabel, "FWDayOfYear", each
                Duration.Days([Date] - [FWStartOfYear]) + 1,
                Int32.Type
            ),

            AddFWWeekNumber = Table.AddColumn(AddFWDayOfYear, "FWWeekNumber", each
                Number.IntegerDivide([FWDayOfYear] - 1, 7) + 1,
                Int32.Type
            ),

            // Period (13 x 4-week periods, week 53+ -> period 13)
            AddFWPeriodNumber = Table.AddColumn(AddFWWeekNumber, "FWPeriodNumber", each
                if [FWWeekNumber] > 52 then 13
                else Number.IntegerDivide([FWWeekNumber] + 3, 4),
                Int32.Type
            ),

            // Quarter (4 x 13-week quarters, week 53+ -> Q4)
            AddFWQuarterNumber = Table.AddColumn(AddFWPeriodNumber, "FWQuarterNumber", each
                if [FWWeekNumber] > 52 then 4
                else Number.IntegerDivide([FWWeekNumber] + 12, 13),
                Int32.Type
            ),

            // Week in quarter
            AddFWWeekInQuarterNumber = Table.AddColumn(AddFWQuarterNumber, "FWWeekInQuarterNumber", each
                if [FWWeekNumber] > 52 then 14
                else [FWWeekNumber] - 13 * ([FWQuarterNumber] - 1),
                Int32.Type
            ),

            // Month within fiscal year (based on 4-4-5 pattern)
            AddFWMonthNumber = Table.AddColumn(AddFWWeekInQuarterNumber, "FWMonthNumber", each
                let
                    wiq = [FWWeekInQuarterNumber],
                    monthInQ = if wiq <= W1 then 1
                               else if wiq <= (W1 + W2) then 2
                               else 3
                in
                    ([FWQuarterNumber] - 1) * 3 + monthInQ,
                Int32.Type
            ),

            // Contiguous indexes
            AddFWQuarterIndex = Table.AddColumn(AddFWMonthNumber, "FWQuarterIndex", each
                [FWYearNumber] * 4 - 1 + [FWQuarterNumber],
                Int32.Type
            ),

            AddFWMonthIndex = Table.AddColumn(AddFWQuarterIndex, "FWMonthIndex", each
                [FWYearNumber] * 12 - 1 + [FWMonthNumber],
                Int32.Type
            ),

            // Weekday relative to first_day_of_week (1..7)
            AddFWWeekDayNumber = Table.AddColumn(AddFWMonthIndex, "FWWeekDayNumber", each
                WeekdayNum([Date]),
                Int32.Type
            ),

            AddFWWeekDayNameShort = Table.AddColumn(AddFWWeekDayNumber, "FWWeekDayNameShort", each
                Text.Start(Date.DayOfWeekName([Date]), 3),
                type text
            ),

            // Week start/end (relative to first_day_of_week)
            AddFWStartOfWeek = Table.AddColumn(AddFWWeekDayNameShort, "FWStartOfWeek", each
                Date.AddDays([Date], -([FWWeekDayNumber] - 1)),
                type date
            ),

            AddFWEndOfWeek = Table.AddColumn(AddFWStartOfWeek, "FWEndOfWeek", each
                Date.AddDays([FWStartOfWeek], 6),
                type date
            ),

            // Working day (Mon-Fri)
            AddFWIsWorkingDay = Table.AddColumn(AddFWEndOfWeek, "FWIsWorkingDay", each
                let dow = Date.DayOfWeek([Date], Day.Monday) in dow >= 0 and dow <= 4,
                type logical
            ),

            AddFWDayType = Table.AddColumn(AddFWIsWorkingDay, "FWDayType", each
                if [FWIsWorkingDay] then "Working Day" else "Non-Working Day",
                type text
            ),

            // FW Month boundaries (min/max date per FWMonthIndex)
            MonthBounds = Table.Group(
                Table.SelectColumns(AddFWDayType, {"Date", "FWMonthIndex"}),
                {"FWMonthIndex"},
                {{"FWMonthMin", each List.Min([Date]), type date},
                 {"FWMonthMax", each List.Max([Date]), type date}}
            ),

            JoinMonth = Table.NestedJoin(AddFWDayType, {"FWMonthIndex"}, MonthBounds, {"FWMonthIndex"}, "MB", JoinKind.LeftOuter),
            ExpandMonth = Table.ExpandTableColumn(JoinMonth, "MB", {"FWMonthMin", "FWMonthMax"}),
            RenameFWStartOfMonth = Table.RenameColumns(ExpandMonth, {{"FWMonthMin", "FWStartOfMonth"}, {"FWMonthMax", "FWEndOfMonth"}}),

            AddFWDayOfMonth = Table.AddColumn(RenameFWStartOfMonth, "FWDayOfMonth", each
                Duration.Days([Date] - [FWStartOfMonth]) + 1,
                Int32.Type
            ),

            // FW Quarter boundaries (min/max date per FWQuarterIndex)
            QuarterBounds = Table.Group(
                Table.SelectColumns(AddFWDayType, {"Date", "FWQuarterIndex"}),
                {"FWQuarterIndex"},
                {{"FWQtrMin", each List.Min([Date]), type date},
                 {"FWQtrMax", each List.Max([Date]), type date}}
            ),

            JoinQuarter = Table.NestedJoin(AddFWDayOfMonth, {"FWQuarterIndex"}, QuarterBounds, {"FWQuarterIndex"}, "QB", JoinKind.LeftOuter),
            ExpandQuarter = Table.ExpandTableColumn(JoinQuarter, "QB", {"FWQtrMin", "FWQtrMax"}),
            RenameFWStartOfQuarter = Table.RenameColumns(ExpandQuarter, {{"FWQtrMin", "FWStartOfQuarter"}, {"FWQtrMax", "FWEndOfQuarter"}}),

            AddFWDayOfQuarter = Table.AddColumn(RenameFWStartOfQuarter, "FWDayOfQuarter", each
                Duration.Days([Date] - [FWStartOfQuarter]) + 1,
                Int32.Type
            ),

            // Global week index anchor: Excel epoch + FDOW for week boundary alignment
            FirstWeekReference = Date.AddDays(#date(1900, 12, 30), FDOW),
            AddFWWeekIndex = Table.AddColumn(AddFWDayOfQuarter, "FWWeekIndex", each
                Number.IntegerDivide(Duration.Days([Date] - FirstWeekReference), 7) + 1,
                Int32.Type
            ),

            // Labels
            AddFWQuarterLabel = Table.AddColumn(AddFWWeekIndex, "FWQuarterLabel", each
                "FQ" & Text.From([FWQuarterNumber]) & " - " & Text.From([FWYearNumber]),
                type text
            ),

            AddFWWeekLabel = Table.AddColumn(AddFWQuarterLabel, "FWWeekLabel", each
                "FW" & Text.PadStart(Text.From([FWWeekNumber]), 2, "0") & " - " & Text.From([FWYearNumber]),
                type text
            ),

            AddFWPeriodLabel = Table.AddColumn(AddFWWeekLabel, "FWPeriodLabel", each
                "P" & Text.PadStart(Text.From([FWPeriodNumber]), 2, "0") & " - " & Text.From([FWYearNumber]),
                type text
            ),

            AddFWMonthLabel = Table.AddColumn(AddFWPeriodLabel, "FWMonthLabel", each
                "FM " & Text.Start(Date.MonthName(Date.AddDays([FWStartOfMonth], 14)), 3) & " - " & Text.From([FWYearNumber]),
                type text
            ),

            AddFWYearMonthLabel = Table.AddColumn(AddFWMonthLabel, "FWYearMonthLabel", each
                let mid = Date.AddDays([FWStartOfMonth], 14) in
                "FM " & Text.Start(Date.MonthName(mid), 3) & " " & Text.From(Date.Year(mid)),
                type text
            ),

            // Offsets relative to as-of
            AsOfFWYearWeekIndex =
                let ref = FirstWeekReference in
                Number.IntegerDivide(Duration.Days(AsOfDate - ref), 7) + 1,

            AsOfFWYearNumber =
                let match = List.Select(BoundsTable, each AsOfDate >= [FWStart] and AsOfDate <= [FWEnd])
                in if List.Count(match) > 0 then match{0}[FWYear] else Date.Year(AsOfDate),

            AsOfFWStartOfYear = FYBoundaryStart(AsOfFWYearNumber),
            AsOfDayOfYear = Duration.Days(AsOfDate - AsOfFWStartOfYear) + 1,
            AsOfWeek = Number.IntegerDivide(AsOfDayOfYear - 1, 7) + 1,
            AsOfFWQuarter = if AsOfWeek > 52 then 4 else Number.IntegerDivide(AsOfWeek + 12, 13),
            AsOfWeekInQ = if AsOfWeek > 52 then 14 else AsOfWeek - 13 * (AsOfFWQuarter - 1),
            AsOfMonthInQ = if AsOfWeekInQ <= W1 then 1 else if AsOfWeekInQ <= (W1 + W2) then 2 else 3,
            AsOfFWMonth = (AsOfFWQuarter - 1) * 3 + AsOfMonthInQ,

            AsOfFWYearMonthIndex = AsOfFWYearNumber * 12 - 1 + AsOfFWMonth,
            AsOfFWYearQuarterIndex = AsOfFWYearNumber * 4 - 1 + AsOfFWQuarter,

            AddFWWeekOffset = Table.AddColumn(AddFWYearMonthLabel, "FWWeekOffset", each
                [FWWeekIndex] - AsOfFWYearWeekIndex,
                Int32.Type
            ),

            AddFWMonthOffset = Table.AddColumn(AddFWWeekOffset, "FWMonthOffset", each
                [FWMonthIndex] - AsOfFWYearMonthIndex,
                Int32.Type
            ),

            AddFWQuarterOffset = Table.AddColumn(AddFWMonthOffset, "FWQuarterOffset", each
                [FWQuarterIndex] - AsOfFWYearQuarterIndex,
                Int32.Type
            )
        in
            AddFWQuarterOffset
    else
        AddFiscalQuarterOffset,

    // ═══════════════════════════════════════════════════════════════
    // PHASE 5 — SYSTEM LABELS & COLUMN RENAME
    // ═══════════════════════════════════════════════════════════════

    WFLabel = if IncludeWeeklyFiscal then
                "Weekly (" & NormQuarterWeekType & " " & NormWeeklyType & ")"
              else "",

    AddFiscalSystem = Table.AddColumn(T4, "FiscalSystem", each "Monthly", type text),
    AddWeeklyFiscalSystem = Table.AddColumn(AddFiscalSystem, "WeeklyFiscalSystem", each WFLabel, type text),

    UseSpacedNames = Text.Upper(Text.Trim(ColumnNamingStyle ?? "Spaced")) <> "PASCALCASE",

    SpacedNameMap = {
        // Base calendar
        {"DateKey", "Date Key"},
        {"DateSerialNumber", "Date Serial Number"},
        {"MonthName", "Month Name"},
        {"MonthShort", "Month Short"},
        {"DayName", "Day Name"},
        {"DayShort", "Day Short"},
        {"DayOfYear", "Day of Year"},
        {"MonthYear", "Month Year"},
        {"MonthYearKey", "Month Year Key"},
        {"YearQuarterKey", "Year Quarter Key"},
        {"QuarterYear", "Quarter Year"},
        {"CalendarMonthIndex", "Calendar Month Index"},
        {"CalendarQuarterIndex", "Calendar Quarter Index"},
        {"DayOfWeek", "Day of Week"},
        {"IsWeekend", "Is Weekend"},
        {"IsBusinessDay", "Is Business Day"},
        {"MonthStartDate", "Month Start Date"},
        {"MonthEndDate", "Month End Date"},
        {"QuarterStartDate", "Quarter Start Date"},
        {"QuarterEndDate", "Quarter End Date"},
        {"IsMonthStart", "Is Month Start"},
        {"IsMonthEnd", "Is Month End"},
        {"IsQuarterStart", "Is Quarter Start"},
        {"IsQuarterEnd", "Is Quarter End"},
        {"IsYearStart", "Is Year Start"},
        {"IsYearEnd", "Is Year End"},
        {"WeekOfMonth", "Week of Month"},
        {"NextBusinessDay", "Next Business Day"},
        {"PreviousBusinessDay", "Previous Business Day"},
        {"IsToday", "Is Today"},
        {"IsCurrentYear", "Is Current Year"},
        {"IsCurrentMonth", "Is Current Month"},
        {"IsCurrentQuarter", "Is Current Quarter"},
        {"CurrentDayOffset", "Current Day Offset"},
        {"YearOffset", "Year Offset"},
        {"CalendarMonthOffset", "Calendar Month Offset"},
        {"CalendarQuarterOffset", "Calendar Quarter Offset"},
        // ISO weeks
        {"ISOWeekNumber", "ISO Week Number"},
        {"ISOYear", "ISO Year"},
        {"ISOWeekStartDate", "ISO Week Start Date"},
        {"ISOWeekEndDate", "ISO Week End Date"},
        {"ISOYearWeekIndex", "ISO Year Week Index"},
        {"ISOWeekOffset", "ISO Week Offset"},
        // Monthly fiscal
        {"FiscalYearStartYear", "Fiscal Year Start Year"},
        {"FiscalMonthNumber", "Fiscal Month Number"},
        {"FiscalQuarterNumber", "Fiscal Quarter Number"},
        {"FiscalYear", "Fiscal Year"},
        {"FiscalYearRange", "Fiscal Year Range"},
        {"FiscalYearLabel", "Fiscal Year Label"},
        {"FiscalQuarterLabel", "Fiscal Quarter Label"},
        {"FiscalMonthIndex", "Fiscal Month Index"},
        {"FiscalQuarterIndex", "Fiscal Quarter Index"},
        {"FiscalYearStartDate", "Fiscal Year Start Date"},
        {"FiscalYearEndDate", "Fiscal Year End Date"},
        {"FiscalQuarterStartDate", "Fiscal Quarter Start Date"},
        {"FiscalQuarterEndDate", "Fiscal Quarter End Date"},
        {"IsFiscalYearStart", "Is Fiscal Year Start"},
        {"IsFiscalYearEnd", "Is Fiscal Year End"},
        {"IsFiscalQuarterStart", "Is Fiscal Quarter Start"},
        {"IsFiscalQuarterEnd", "Is Fiscal Quarter End"},
        {"FiscalMonthOffset", "Fiscal Month Offset"},
        {"FiscalQuarterOffset", "Fiscal Quarter Offset"},
        // Weekly fiscal
        {"FWYearNumber", "FW Year Number"},
        {"FWStartOfYear", "FW Start of Year"},
        {"FWEndOfYear", "FW End of Year"},
        {"FWYearLabel", "FW Year Label"},
        {"FWDayOfYear", "FW Day of Year"},
        {"FWWeekNumber", "FW Week Number"},
        {"FWPeriodNumber", "FW Period Number"},
        {"FWQuarterNumber", "FW Quarter Number"},
        {"FWWeekInQuarterNumber", "FW Week in Quarter Number"},
        {"FWMonthNumber", "FW Month Number"},
        {"FWQuarterIndex", "FW Quarter Index"},
        {"FWMonthIndex", "FW Month Index"},
        {"FWWeekDayNumber", "FW Week Day Number"},
        {"FWWeekDayNameShort", "FW Week Day Name Short"},
        {"FWStartOfWeek", "FW Start of Week"},
        {"FWEndOfWeek", "FW End of Week"},
        {"FWIsWorkingDay", "FW Is Working Day"},
        {"FWDayType", "FW Day Type"},
        {"FWStartOfMonth", "FW Start of Month"},
        {"FWEndOfMonth", "FW End of Month"},
        {"FWDayOfMonth", "FW Day of Month"},
        {"FWStartOfQuarter", "FW Start of Quarter"},
        {"FWEndOfQuarter", "FW End of Quarter"},
        {"FWDayOfQuarter", "FW Day of Quarter"},
        {"FWWeekIndex", "FW Week Index"},
        {"FWQuarterLabel", "FW Quarter Label"},
        {"FWWeekLabel", "FW Week Label"},
        {"FWPeriodLabel", "FW Period Label"},
        {"FWMonthLabel", "FW Month Label"},
        {"FWYearMonthLabel", "FW Year Month Label"},
        {"FWWeekOffset", "FW Week Offset"},
        {"FWMonthOffset", "FW Month Offset"},
        {"FWQuarterOffset", "FW Quarter Offset"},
        // System labels
        {"FiscalSystem", "Fiscal System"},
        {"WeeklyFiscalSystem", "Weekly Fiscal System"}
    },

    Result = if UseSpacedNames then
                Table.RenameColumns(AddWeeklyFiscalSystem, SpacedNameMap, MissingField.Ignore)
             else
                AddWeeklyFiscalSystem
in
    Result