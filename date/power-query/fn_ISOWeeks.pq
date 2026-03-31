// fn_ISOWeeks
// ISO-8601 week columns and as-of week offset.
// Mirrors: src/dimensions/dates/iso.py
//
// Parameters:
//   InputTable  : table  — table with Date column (output of fn_Calendar)
//   AsOfDate    : date   — reference date for week offset
//
// Returns: table with ISO week columns appended

(InputTable as table, AsOfDate as date) as table =>
let
    // ISO week reference: Monday of ISO week 1 in year 2000
    ISOWeekRef = #date(2000, 1, 3),

    // As-of week start (Monday)
    AsOfWeekday = Date.DayOfWeek(AsOfDate, Day.Monday),
    AsOfWeekStart = Date.AddDays(AsOfDate, -AsOfWeekday),
    AsOfISOYearWeekIndex = Number.IntegerDivide(Duration.Days(AsOfWeekStart - ISOWeekRef), 7),

    AddWeekOfYearISO = Table.AddColumn(InputTable, "WeekOfYearISO", each
        let
            // ISO year and week via Date.WeekOfYear is not ISO-compliant;
            // use the standard: Thursday of the current week determines the year.
            thursday = Date.AddDays([Date], 3 - Date.DayOfWeek([Date], Day.Monday)),
            jan4 = #date(Date.Year(thursday), 1, 4),
            jan4Monday = Date.AddDays(jan4, -Date.DayOfWeek(jan4, Day.Monday)),
            weekNum = Number.IntegerDivide(Duration.Days([Date] - jan4Monday), 7) + 1
        in
            weekNum,
        Int32.Type
    ),

    AddISOYear = Table.AddColumn(AddWeekOfYearISO, "ISOYear", each
        let
            thursday = Date.AddDays([Date], 3 - Date.DayOfWeek([Date], Day.Monday))
        in
            Date.Year(thursday),
        Int32.Type
    ),

    // WeekStartDate: Monday of the current ISO week
    AddWeekStartDate = Table.AddColumn(AddISOYear, "WeekStartDate", each
        Date.AddDays([Date], -Date.DayOfWeek([Date], Day.Monday)),
        type date
    ),

    // WeekEndDate: Sunday of the current ISO week
    AddWeekEndDate = Table.AddColumn(AddWeekStartDate, "WeekEndDate", each
        Date.AddDays([WeekStartDate], 6),
        type date
    ),

    // ISOYearWeekIndex: contiguous week number relative to ISOWeekRef
    AddISOYearWeekIndex = Table.AddColumn(AddWeekEndDate, "ISOYearWeekIndex", each
        Number.IntegerDivide(Duration.Days([WeekStartDate] - ISOWeekRef), 7),
        Int32.Type
    ),

    // ISOWeekOffset: weeks relative to as-of date
    AddISOWeekOffset = Table.AddColumn(AddISOYearWeekIndex, "ISOWeekOffset", each
        [ISOYearWeekIndex] - AsOfISOYearWeekIndex,
        Int32.Type
    )
in
    AddISOWeekOffset