/* 
    fn_Fiscal - Monthly fiscal calendar columns and as-of offsets.

    Parameters:
        InputTable       : table  — table with Date, Year, Month columns (output of fn_Calendar)
        FiscalStartMonth : number — first month of the fiscal year (1-12, e.g. 5 = May)
        AsOfDate         : date   — reference date for fiscal offsets

    Returns: table with fiscal columns appended
*/
( InputTable as table, FiscalStartMonth as number, AsOfDate as date ) as table =>
    let

        // Clamp fiscal start month to 1-12
        FYStartMonth = List.Max ( { 1, List.Min ( { 12, FiscalStartMonth } ) } ),
        
        // Offset added to start year to get the fiscal "label" year
        // When FY starts in Jan, the label year = start year; otherwise label year = start year + 1
        FYEndAdd = if FYStartMonth = 1 then 0 else 1,

        // --- Core fiscal columns ---
        AddFiscalYearStartYear = Table.AddColumn (
            InputTable,
            "FiscalYearStartYear",
            each if [Month] >= FYStartMonth then [Year] else [Year] - 1,
            Int32.Type
        ),

        AddFiscalMonthNumber = Table.AddColumn (
            AddFiscalYearStartYear,
            "FiscalMonthNumber",
            each Number.Mod ( [Month] - FYStartMonth + 12, 12 ) + 1,
            Int32.Type
        ),

        AddFiscalQuarterNumber = Table.AddColumn (
            AddFiscalMonthNumber,
            "FiscalQuarterNumber",
            each Number.IntegerDivide ( [FiscalMonthNumber] - 1, 3 ) + 1,
            Int32.Type
        ),

        // FiscalYear: the end-year label (or same as start year if FY starts in Jan)
        AddFiscalYear = Table.AddColumn (
            AddFiscalQuarterNumber,
            "FiscalYear",
            each [FiscalYearStartYear] + FYEndAdd,
            Int32.Type
        ),

        // --- Labels ---
        AddFiscalYearRange = Table.AddColumn (
            AddFiscalYear,
            "FiscalYearRange",
            each
                if FYStartMonth = 1 then
                    Text.From ( [FiscalYearStartYear] )
                else
                    Text.From ( [FiscalYearStartYear] ) & "-" & Text.From ( [FiscalYear] ),
            type text
        ),

        AddFiscalYearLabel = Table.AddColumn (
            AddFiscalYearRange,
            "FiscalYearLabel",
            each "FY " & Text.From ( [FiscalYear] ),
            type text
        ),

        AddFiscalQuarterLabel = Table.AddColumn (
            AddFiscalYearLabel,
            "FiscalQuarterLabel",
            each "Q" & Text.From ( [FiscalQuarterNumber] ) & " FY" & Text.From ( [FiscalYear] ),
            type text
        ),

        // --- Fiscal month name (independent from calendar MonthName for Power BI sorting) ---
        AddFiscalMonthName = Table.AddColumn (
            AddFiscalQuarterLabel,
            "FiscalMonthName",
            each Date.MonthName ( [Date] ),
            type text
        ),

        AddFiscalMonthShort = Table.AddColumn (
            AddFiscalMonthName,
            "FiscalMonthShort",
            each Text.Start ( [FiscalMonthName], 3 ),
            type text
        ),

        // --- Contiguous indexes ---
        AddFiscalMonthIndex = Table.AddColumn (
            AddFiscalMonthShort,
            "FiscalMonthIndex",
            each [FiscalYearStartYear] * 12 + [FiscalMonthNumber],
            Int32.Type
        ),

        AddFiscalQuarterIndex = Table.AddColumn (
            AddFiscalMonthIndex,
            "FiscalQuarterIndex",
            each [FiscalYearStartYear] * 4 + [FiscalQuarterNumber],
            Int32.Type
        ),

        // --- Fiscal year start/end dates ---
        AddFiscalYearStartDate = Table.AddColumn (
            AddFiscalQuarterIndex,
            "FiscalYearStartDate",
            each #date ( [FiscalYearStartYear], FYStartMonth, 1 ),
            type date
        ),

        AddFiscalYearEndDate = Table.AddColumn (
            AddFiscalYearStartDate,
            "FiscalYearEndDate",
            each Date.AddDays ( Date.AddYears ( [FiscalYearStartDate], 1 ), - 1 ),
            type date
        ),

        // --- Fiscal quarter start/end dates ---
        AddFiscalQuarterStartDate = Table.AddColumn (
            AddFiscalYearEndDate,
            "FiscalQuarterStartDate",
            each
                let
                    monthsToAdd = ( [FiscalQuarterNumber] - 1 ) * 3,
                    rawMonth    = FYStartMonth + monthsToAdd,
                    qYear       = [FiscalYearStartYear] + Number.IntegerDivide ( rawMonth - 1, 12 ),
                    qMonth      = Number.Mod ( rawMonth - 1, 12 ) + 1
                in
                    #date ( qYear, qMonth, 1 ),
            type date
        ),

        AddFiscalQuarterEndDate = Table.AddColumn (
            AddFiscalQuarterStartDate,
            "FiscalQuarterEndDate",
            each Date.AddDays ( Date.AddMonths ( [FiscalQuarterStartDate], 3 ), - 1 ),
            type date
        ),

        // --- Boolean flags ---
        AddIsFiscalYearStart = Table.AddColumn (
            AddFiscalQuarterEndDate,
            "IsFiscalYearStart",
            each [Date] = [FiscalYearStartDate],
            type logical
        ),

        AddIsFiscalYearEnd = Table.AddColumn (
            AddIsFiscalYearStart,
            "IsFiscalYearEnd",
            each [Date] = [FiscalYearEndDate],
            type logical
        ),

        AddIsFiscalQuarterStart = Table.AddColumn (
            AddIsFiscalYearEnd,
            "IsFiscalQuarterStart",
            each [Date] = [FiscalQuarterStartDate],
            type logical
        ),

        AddIsFiscalQuarterEnd = Table.AddColumn (
            AddIsFiscalQuarterStart,
            "IsFiscalQuarterEnd",
            each [Date] = [FiscalQuarterEndDate],
            type logical
        ),

        // --- Fiscal offsets relative to as-of ---
        // Compute as-of fiscal month/quarter index
        AsOfFiscalYearStartYear =
            if Date.Month ( AsOfDate ) >= FYStartMonth then
                Date.Year ( AsOfDate )
            else
                Date.Year ( AsOfDate ) - 1,

        AsOfFiscalMonthNumber = Number.Mod ( Date.Month ( AsOfDate ) - FYStartMonth + 12, 12 ) + 1,
        AsOfFiscalQuarterNumber = Number.IntegerDivide ( AsOfFiscalMonthNumber - 1, 3 ) + 1,
        AsOfFiscalMonthIndex = AsOfFiscalYearStartYear * 12 + AsOfFiscalMonthNumber,
        AsOfFiscalQuarterIndex = AsOfFiscalYearStartYear * 4 + AsOfFiscalQuarterNumber,

        AddFiscalMonthOffset = Table.AddColumn (
            AddIsFiscalQuarterEnd,
            "FiscalMonthOffset",
            each [FiscalMonthIndex] - AsOfFiscalMonthIndex,
            Int32.Type
        ),

        AddFiscalQuarterOffset = Table.AddColumn (
            AddFiscalMonthOffset,
            "FiscalQuarterOffset",
            each [FiscalQuarterIndex] - AsOfFiscalQuarterIndex,
            Int32.Type
        ),

        // --- Fiscal period duration and day-of-period ---
        AddFiscalQuarterDays = Table.AddColumn (
            AddFiscalQuarterOffset,
            "FiscalQuarterDays",
            each Duration.Days ( [FiscalQuarterEndDate] - [FiscalQuarterStartDate] ) + 1,
            Int32.Type
        ),

        AddFiscalYearDays = Table.AddColumn (
            AddFiscalQuarterDays,
            "FiscalYearDays",
            each Duration.Days ( [FiscalYearEndDate] - [FiscalYearStartDate] ) + 1,
            Int32.Type
        ),

        AddFiscalDayOfQuarter = Table.AddColumn (
            AddFiscalYearDays,
            "FiscalDayOfQuarter",
            each Duration.Days ( [Date] - [FiscalQuarterStartDate] ) + 1,
            Int32.Type
        ),

        AddFiscalDayOfYear = Table.AddColumn (
            AddFiscalDayOfQuarter,
            "FiscalDayOfYear",
            each Duration.Days ( [Date] - [FiscalYearStartDate] ) + 1,
            Int32.Type
        ),

        // --- Fiscal year offset ---
        AsOfFiscalYear = AsOfFiscalYearStartYear + FYEndAdd,

        AddFiscalYearOffset = Table.AddColumn (
            AddFiscalDayOfYear,
            "FiscalYearOffset",
            each [FiscalYear] - AsOfFiscalYear,
            Int32.Type
        )
    in
        AddFiscalYearOffset