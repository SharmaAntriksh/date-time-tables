// fn_Orchestrate
// Orchestrator: calls fn_Calendar, fn_ISOWeeks, fn_Fiscal, fn_WeeklyFiscal
// in sequence and appends the FiscalSystem / WeeklyFiscalSystem label columns.
//
// Prerequisites: the four fn_* queries must exist in the same Power BI model
// with the exact names: fn_Calendar, fn_ISOWeeks, fn_Fiscal, fn_WeeklyFiscal.
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
    // Phase 1: Base calendar
    T1 = fn_Calendar(StartDate, EndDate, AsOfDate),

    // Phase 2: ISO weeks
    T2 = fn_ISOWeeks(T1, AsOfDate),

    // Phase 3: Monthly fiscal
    T3 = fn_Fiscal(T2, FiscalStartMonth, AsOfDate),

    // Phase 4: Weekly fiscal (conditional)
    T4 = if IncludeWeeklyFiscal then
            fn_WeeklyFiscal(T3, FiscalStartMonth, FirstDayOfWeek, WeeklyType, QuarterWeekType, TypeStartFiscalYear, AsOfDate)
         else T3,

    // System label columns (normalize to match fn_WeeklyFiscal's internal normalization)
    NormQWT = if List.Contains({"445","454","544"}, Text.Trim(QuarterWeekType))
              then Text.Trim(QuarterWeekType) else "445",
    NormWType = if Text.Upper(Text.Trim(WeeklyType)) = "NEAREST" then "Nearest" else "Last",

    WFLabel = if IncludeWeeklyFiscal then
                "Weekly (" & NormQWT & " " & NormWType & ")"
              else "",

    AddFiscalSystem = Table.AddColumn(T4, "FiscalSystem", each "Monthly", type text),
    AddWeeklyFiscalSystem = Table.AddColumn(AddFiscalSystem, "WeeklyFiscalSystem", each WFLabel, type text),

    // Phase 5: Rename columns to user-friendly spaced names (default)
    UseSpacedNames = Text.Upper(Text.Trim(ColumnNamingStyle ?? "Spaced")) <> "PASCALCASE",

    SpacedNameMap = {
        // fn_Calendar
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
        // fn_ISOWeeks
        {"ISOWeekNumber", "ISO Week Number"},
        {"ISOYear", "ISO Year"},
        {"ISOWeekStartDate", "ISO Week Start Date"},
        {"ISOWeekEndDate", "ISO Week End Date"},
        {"ISOYearWeekIndex", "ISO Year Week Index"},
        {"ISOWeekOffset", "ISO Week Offset"},
        // fn_Fiscal
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
        // fn_WeeklyFiscal
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
        // fn_Orchestrate
        {"FiscalSystem", "Fiscal System"},
        {"WeeklyFiscalSystem", "Weekly Fiscal System"}
    },

    Result = if UseSpacedNames then
                Table.RenameColumns(AddWeeklyFiscalSystem, SpacedNameMap, MissingField.Ignore)
             else
                AddWeeklyFiscalSystem
in
    Result