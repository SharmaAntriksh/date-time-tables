// fn_WeeklyFiscal
// Weekly fiscal (4-4-5 / 4-5-4 / 5-4-4) calendar columns and offsets.
// Mirrors: src/dimensions/dates/weekly_fiscal.py (with the off-by-one fix applied)
//
// Parameters:
//   InputTable          : table  — table with Date, Year, Month columns
//   FiscalStartMonth    : number — first month of fiscal year (1-12)
//   FirstDayOfWeek      : number — 0=Sunday, 1=Monday, ... 6=Saturday
//   WeeklyType          : text   — "Last" or "Nearest"
//   QuarterWeekType     : text   — "445", "454", or "544"
//   TypeStartFiscalYear : number — 0=start-year labeling, 1=end-year labeling
//   AsOfDate            : date   — reference date for offsets
//
// Returns: table with weekly fiscal columns appended

(
    InputTable as table,
    FiscalStartMonth as number,
    FirstDayOfWeek as number,
    WeeklyType as text,
    QuarterWeekType as text,
    TypeStartFiscalYear as number,
    AsOfDate as date
) as table =>
let
    // --- Parameter normalization ---
    FYStartMonth = List.Max({1, List.Min({12, FiscalStartMonth})}),
    FDOW = Number.Mod(FirstDayOfWeek, 7),
    WType = if Text.Upper(Text.Trim(WeeklyType)) = "NEAREST" then "Nearest" else "Last",
    QWT = if List.Contains({"445","454","544"}, Text.Trim(QuarterWeekType))
          then Text.Trim(QuarterWeekType) else "445",
    TSY = if TypeStartFiscalYear = 0 then 0 else 1,

    // Weeks per period in each quarter (e.g. 4-4-5)
    W1 = Number.FromText(Text.At(QWT, 0)),
    W2 = Number.FromText(Text.At(QWT, 1)),

    // --- Helper: weekday number (1..7) relative to FirstDayOfWeek ---
    // Input: a date. Output: 1 = FirstDayOfWeek, 7 = day before FirstDayOfWeek
    // Date.DayOfWeek with Day.Sunday returns 0=Sun..6=Sat
    WeekdayNum = (d as date) as number =>
        let
            sun0 = Date.DayOfWeek(d, Day.Sunday),
            pos0 = Number.Mod(sun0 - FDOW + 7, 7)
        in
            pos0 + 1,

    // --- Helper: compute fiscal year start date for a given FW year number ---
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

    // --- Build bounds table: FW year -> (start, end) ---
    StartYear = List.Min(Table.Column(InputTable, "Year")) - 1,
    EndYear = List.Max(Table.Column(InputTable, "Year")) + 2,
    YearList = {StartYear..EndYear},

    BoundsTable = List.Transform(YearList, each
        let
            y = _,
            s = FYBoundaryStart(y),
            nextS = FYBoundaryStart(y + 1),
            e = Date.AddDays(nextS, -1)
        in
            [FWYear = y, FWStart = s, FWEnd = e]
    ),

    // Expand bounds into a date-to-FWYear lookup: one row per date with FWYear, FWStart, FWEnd.
    // This replaces the per-row List.Select scan with an O(n) hash join.
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

    // --- Assign FWYearNumber, FWStartOfYear, FWEndOfYear via join ---
    JoinFWYear = Table.NestedJoin(InputTable, {"Date"}, DateToFWYear, {"Date"}, "_FW", JoinKind.LeftOuter),
    ExpandFWYear = Table.ExpandTableColumn(JoinFWYear, "_FW", {"FWYear", "FWStart", "FWEnd"}),
    AddFWYearNumber = Table.RenameColumns(ExpandFWYear, {{"FWYear", "FWYearNumber"}, {"FWStart", "FWStartOfYear"}, {"FWEnd", "FWEndOfYear"}}),

    AddFWYearLabel = Table.AddColumn(AddFWYearNumber, "FWYearLabel", each
        "FY " & Text.From([FWYearNumber]),
        type text
    ),

    // --- Day/week within fiscal year ---
    AddFWDayOfYearNumber = Table.AddColumn(AddFWYearLabel, "FWDayOfYearNumber", each
        Duration.Days([Date] - [FWStartOfYear]) + 1,
        Int32.Type
    ),

    AddFWWeekNumber = Table.AddColumn(AddFWDayOfYearNumber, "FWWeekNumber", each
        Number.IntegerDivide([FWDayOfYearNumber] - 1, 7) + 1,
        Int32.Type
    ),

    // --- Period (13 x 4-week periods, week 53+ -> period 13) ---
    AddFWPeriodNumber = Table.AddColumn(AddFWWeekNumber, "FWPeriodNumber", each
        if [FWWeekNumber] > 52 then 13
        else Number.IntegerDivide([FWWeekNumber] + 3, 4),
        Int32.Type
    ),

    // --- Quarter (4 x 13-week quarters, week 53+ -> Q4) ---
    AddFWQuarterNumber = Table.AddColumn(AddFWPeriodNumber, "FWQuarterNumber", each
        if [FWWeekNumber] > 52 then 4
        else Number.IntegerDivide([FWWeekNumber] + 12, 13),
        Int32.Type
    ),

    // --- Week in quarter ---
    AddFWWeekInQuarterNumber = Table.AddColumn(AddFWQuarterNumber, "FWWeekInQuarterNumber", each
        if [FWWeekNumber] > 52 then 14
        else [FWWeekNumber] - 13 * ([FWQuarterNumber] - 1),
        Int32.Type
    ),

    // --- Month within fiscal year (based on 4-4-5 pattern) ---
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

    // --- Contiguous indexes ---
    AddFWYearQuarterNumber = Table.AddColumn(AddFWMonthNumber, "FWYearQuarterNumber", each
        [FWYearNumber] * 4 - 1 + [FWQuarterNumber],
        Int32.Type
    ),

    AddFWYearMonthNumber = Table.AddColumn(AddFWYearQuarterNumber, "FWYearMonthNumber", each
        [FWYearNumber] * 12 - 1 + [FWMonthNumber],
        Int32.Type
    ),

    // --- Weekday relative to first_day_of_week (1..7) ---
    AddWeekDayNumber = Table.AddColumn(AddFWYearMonthNumber, "WeekDayNumber", each
        WeekdayNum([Date]),
        Int32.Type
    ),

    AddWeekDayNameShort = Table.AddColumn(AddWeekDayNumber, "WeekDayNameShort", each
        Text.Start(Date.DayOfWeekName([Date]), 3),
        type text
    ),

    // --- Week start/end (relative to first_day_of_week) ---
    AddFWStartOfWeek = Table.AddColumn(AddWeekDayNameShort, "FWStartOfWeek", each
        Date.AddDays([Date], -([WeekDayNumber] - 1)),
        type date
    ),

    AddFWEndOfWeek = Table.AddColumn(AddFWStartOfWeek, "FWEndOfWeek", each
        Date.AddDays([FWStartOfWeek], 6),
        type date
    ),

    // --- Working day (Mon-Fri) ---
    AddIsWorkingDay = Table.AddColumn(AddFWEndOfWeek, "IsWorkingDay", each
        let dow = Date.DayOfWeek([Date], Day.Monday) in dow >= 0 and dow <= 4,
        type logical
    ),

    AddDayType = Table.AddColumn(AddIsWorkingDay, "DayType", each
        if [IsWorkingDay] then "Working Day" else "Non-Working Day",
        type text
    ),

    // --- FW Month boundaries (min/max date per FWYearMonthNumber) ---
    MonthBounds = Table.Group(
        Table.SelectColumns(AddDayType, {"Date", "FWYearMonthNumber"}),
        {"FWYearMonthNumber"},
        {{"FWMonthMin", each List.Min([Date]), type date},
         {"FWMonthMax", each List.Max([Date]), type date}}
    ),

    JoinMonth = Table.NestedJoin(AddDayType, {"FWYearMonthNumber"}, MonthBounds, {"FWYearMonthNumber"}, "MB", JoinKind.LeftOuter),
    ExpandMonth = Table.ExpandTableColumn(JoinMonth, "MB", {"FWMonthMin", "FWMonthMax"}),
    RenameFWStartOfMonth = Table.RenameColumns(ExpandMonth, {{"FWMonthMin", "FWStartOfMonth"}, {"FWMonthMax", "FWEndOfMonth"}}),

    AddFWDayOfMonthNumber = Table.AddColumn(RenameFWStartOfMonth, "FWDayOfMonthNumber", each
        Duration.Days([Date] - [FWStartOfMonth]) + 1,
        Int32.Type
    ),

    // --- FW Quarter boundaries (min/max date per FWYearQuarterNumber) ---
    QuarterBounds = Table.Group(
        Table.SelectColumns(AddDayType, {"Date", "FWYearQuarterNumber"}),
        {"FWYearQuarterNumber"},
        {{"FWQtrMin", each List.Min([Date]), type date},
         {"FWQtrMax", each List.Max([Date]), type date}}
    ),

    JoinQuarter = Table.NestedJoin(AddFWDayOfMonthNumber, {"FWYearQuarterNumber"}, QuarterBounds, {"FWYearQuarterNumber"}, "QB", JoinKind.LeftOuter),
    ExpandQuarter = Table.ExpandTableColumn(JoinQuarter, "QB", {"FWQtrMin", "FWQtrMax"}),
    RenameFWStartOfQuarter = Table.RenameColumns(ExpandQuarter, {{"FWQtrMin", "FWStartOfQuarter"}, {"FWQtrMax", "FWEndOfQuarter"}}),

    AddFWDayOfQuarterNumber = Table.AddColumn(RenameFWStartOfQuarter, "FWDayOfQuarterNumber", each
        Duration.Days([Date] - [FWStartOfQuarter]) + 1,
        Int32.Type
    ),

    // --- Global week index (DAX-like FWYearWeekNumber) ---
    FirstWeekReference = Date.AddDays(#date(1900, 12, 30), FDOW),
    AddFWYearWeekNumber = Table.AddColumn(AddFWDayOfQuarterNumber, "FWYearWeekNumber", each
        Number.IntegerDivide(Duration.Days([Date] - FirstWeekReference), 7) + 1,
        Int32.Type
    ),

    // --- Labels ---
    AddFWQuarterLabel = Table.AddColumn(AddFWYearWeekNumber, "FWQuarterLabel", each
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

    // FWMonthLabel: use midpoint of fiscal month to get representative calendar month name
    AddFWMonthLabel = Table.AddColumn(AddFWPeriodLabel, "FWMonthLabel", each
        "FM " & Text.Start(Date.MonthName(Date.AddDays([FWStartOfMonth], 14)), 3) & " - " & Text.From([FWYearNumber]),
        type text
    ),

    AddFWYearMonthLabel = Table.AddColumn(AddFWMonthLabel, "FWYearMonthLabel", each
        "FM " & Text.Start(Date.MonthName(Date.AddDays([FWStartOfMonth], 14)), 3) & " " & Text.From(Date.Year(Date.AddDays([FWStartOfMonth], 14))),
        type text
    ),

    // --- Offsets relative to as-of ---
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

    AddFWYearWeekOffset = Table.AddColumn(AddFWYearMonthLabel, "FWYearWeekOffset", each
        [FWYearWeekNumber] - AsOfFWYearWeekIndex,
        Int32.Type
    ),

    AddFWYearMonthOffset = Table.AddColumn(AddFWYearWeekOffset, "FWYearMonthOffset", each
        [FWYearMonthNumber] - AsOfFWYearMonthIndex,
        Int32.Type
    ),

    AddFWYearQuarterOffset = Table.AddColumn(AddFWYearMonthOffset, "FWYearQuarterOffset", each
        [FWYearQuarterNumber] - AsOfFWYearQuarterIndex,
        Int32.Type
    )
in
    AddFWYearQuarterOffset