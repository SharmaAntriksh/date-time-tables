// fn_Orchestrate
// Orchestrator: calls fn_Calendar, fn_ISOWeeks, fn_Fiscal, fn_WeeklyFiscal
// in sequence and appends the FiscalSystem / WeeklyFiscalSystem label columns.
//
// Prerequisites: the four fn_* queries must exist in the same Power BI model
// with the exact names: fn_Calendar, fn_ISOWeeks, fn_Fiscal, fn_WeeklyFiscal.
//
// Parameters:
//   StartDate            : date   — first date in the table
//   EndDate              : date   — last date in the table
//   AsOfDate             : date   — reference date for all relative offsets
//   FiscalStartMonth     : number — first month of the fiscal year (1-12)
//   IncludeWeeklyFiscal  : logical — true to include 4-4-5 weekly fiscal columns
//   FirstDayOfWeek       : number — 0=Sunday .. 6=Saturday (weekly fiscal)
//   WeeklyType           : text   — "Last" or "Nearest" (weekly fiscal)
//   QuarterWeekType      : text   — "445", "454", or "544" (weekly fiscal)
//   TypeStartFiscalYear  : number — 0=start-year, 1=end-year labeling (weekly fiscal)
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
    TypeStartFiscalYear as number
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

    // System label columns
    WFLabel = if IncludeWeeklyFiscal then
                "Weekly (" & Text.Trim(QuarterWeekType) & " " &
                (if Text.Upper(Text.Trim(WeeklyType)) = "NEAREST" then "Nearest" else "Last") & ")"
              else "",

    AddFiscalSystem = Table.AddColumn(T4, "FiscalSystem", each "Monthly", type text),
    AddWeeklyFiscalSystem = Table.AddColumn(AddFiscalSystem, "WeeklyFiscalSystem", each WFLabel, type text)
in
    AddWeeklyFiscalSystem