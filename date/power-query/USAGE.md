# Date Dimension Table — Power Query

Two options: **modular** (five queries wired together) or **standalone** (single self-contained file). Both produce the same output.

## Files

| File | Role |
|---|---|
| `fn_Calendar.pq` | Base calendar columns and as-of relative offsets |
| `fn_ISOWeeks.pq` | ISO-8601 week columns |
| `fn_Fiscal.pq` | Monthly fiscal year columns |
| `fn_WeeklyFiscal.pq` | Weekly fiscal (4-4-5) columns |
| `fn_Orchestrate.pq` | Orchestrator — calls the above in sequence |
| `fn_DateTable.pq` | Standalone alternative — all logic in one file |

## Setup

### Modular (fn_Orchestrate)

1. Import all five `fn_*.pq` files as queries in Power BI Desktop (Home > Transform Data > New Source > Blank Query, then paste each file's contents into the Advanced Editor)
2. The query names must match exactly: `fn_Calendar`, `fn_ISOWeeks`, `fn_Fiscal`, `fn_WeeklyFiscal`, `fn_Orchestrate`
3. Invoke `fn_Orchestrate` with your parameters

### Standalone (fn_DateTable)

1. Import `fn_DateTable.pq` as a single query
2. Invoke it directly — no other queries needed

## Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| StartDate | date | *(required)* | First date in the table |
| EndDate | date | *(required)* | Last date in the table |
| AsOfDate | date | *(required)* | Reference date for relative offsets |
| FiscalStartMonth | number | *(required)* | First month of fiscal year (1-12) |
| IncludeWeeklyFiscal | logical | *(required)* | `true` to include 4-4-5 weekly fiscal columns |
| FirstDayOfWeek | number | *(required)* | 0=Sunday, 1=Monday, ... 6=Saturday |
| WeeklyType | text | *(required)* | `"Last"` or `"Nearest"` |
| QuarterWeekType | text | *(required)* | `"445"`, `"454"`, or `"544"` |
| TypeStartFiscalYear | number | *(required)* | 0=start-year, 1=end-year labeling |
| ColumnNamingStyle | text (optional) | `"Spaced"` | `"Spaced"` or `"PascalCase"` |

## Usage

### Modular

```powerquery
fn_Orchestrate(
    #date(2021, 1, 1),      // StartDate
    #date(2026, 12, 31),    // EndDate
    #date(2025, 4, 5),      // AsOfDate
    5,                       // FiscalStartMonth (May)
    true,                    // IncludeWeeklyFiscal
    0,                       // FirstDayOfWeek (Sunday)
    "Last",                  // WeeklyType
    "445",                   // QuarterWeekType
    1,                       // TypeStartFiscalYear (end-year)
    "Spaced"                 // ColumnNamingStyle
)
```

### Standalone

```powerquery
fn_DateTable(
    #date(2021, 1, 1),
    #date(2026, 12, 31),
    #date(2025, 4, 5),
    5,
    false,                   // No weekly fiscal
    0,
    "Last",
    "445",
    1,
    "PascalCase"
)
```

### Calendar only (no weekly fiscal)

Set `IncludeWeeklyFiscal` to `false`. ISO and fiscal columns are always included.

## Column Reference

### Phase 1: Base Calendar (48 columns)

| Column (Spaced) | Column (PascalCase) | Type | Description |
|---|---|---|---|
| Date | Date | date | The date |
| Year | Year | int | Calendar year |
| Month | Month | int | Calendar month (1-12) |
| Day | Day | int | Day of month (1-31) |
| Quarter | Quarter | int | Calendar quarter (1-4) |
| Date Key | DateKey | int | YYYYMMDD integer key |
| Date Serial Number | DateSerialNumber | int | Excel serial number (days since 1899-12-30) |
| Month Name | MonthName | text | "January" |
| Month Short | MonthShort | text | "Jan" |
| Day Name | DayName | text | "Monday" |
| Day Short | DayShort | text | "Mon" |
| Day of Year | DayOfYear | int | 1-366 |
| Month Year | MonthYear | text | "Jan 2025" |
| Month Year Key | MonthYearKey | int | YYYYMM |
| Year Quarter Key | YearQuarterKey | int | YYYYQ |
| Quarter Year | QuarterYear | text | "Q1 2025" |
| Calendar Month Index | CalendarMonthIndex | int | Monotonic month counter |
| Calendar Quarter Index | CalendarQuarterIndex | int | Monotonic quarter counter |
| Day of Week | DayOfWeek | int | 0=Sunday ... 6=Saturday |
| Is Weekend | IsWeekend | logical | Saturday or Sunday |
| Is Business Day | IsBusinessDay | logical | Monday-Friday |
| Month Start Date | MonthStartDate | date | First day of month |
| Month End Date | MonthEndDate | date | Last day of month |
| Quarter Start Date | QuarterStartDate | date | First day of quarter |
| Quarter End Date | QuarterEndDate | date | Last day of quarter |
| Is Month Start | IsMonthStart | logical | First day of month |
| Is Month End | IsMonthEnd | logical | Last day of month |
| Is Quarter Start | IsQuarterStart | logical | First day of quarter |
| Is Quarter End | IsQuarterEnd | logical | Last day of quarter |
| Is Year Start | IsYearStart | logical | January 1 |
| Is Year End | IsYearEnd | logical | December 31 |
| Week of Month | WeekOfMonth | int | 1-6 (day-based) |
| Calendar Week Start Date | CalendarWeekStartDate | date | Sunday of the week |
| Calendar Week End Date | CalendarWeekEndDate | date | Saturday of the week |
| Calendar Week Number | CalendarWeekNumber | int | 1-54 (Sunday-based) |
| Calendar Week Index | CalendarWeekIndex | int | Contiguous week index |
| Calendar Week Date Range | CalendarWeekDateRange | text | "Jan 05 - Jan 11, 2025" |
| Calendar Week Offset | CalendarWeekOffset | int | Weeks from AsOfDate |
| Next Business Day | NextBusinessDay | date | Next Mon-Fri |
| Previous Business Day | PreviousBusinessDay | date | Previous Mon-Fri |
| Is Today | IsToday | logical | Date = AsOfDate |
| Is Current Year | IsCurrentYear | logical | Same year as AsOfDate |
| Is Current Month | IsCurrentMonth | logical | Same month as AsOfDate |
| Is Current Quarter | IsCurrentQuarter | logical | Same quarter as AsOfDate |
| Current Day Offset | CurrentDayOffset | int | Days from AsOfDate |
| Year Offset | YearOffset | int | Years from AsOfDate |
| Calendar Month Offset | CalendarMonthOffset | int | Months from AsOfDate |
| Calendar Quarter Offset | CalendarQuarterOffset | int | Quarters from AsOfDate |

### Phase 2: ISO Weeks (7 columns)

| Column (Spaced) | Column (PascalCase) | Type | Description |
|---|---|---|---|
| ISO Week Number | ISOWeekNumber | int | ISO week (1-53) |
| ISO Year | ISOYear | int | ISO year |
| ISO Week Start Date | ISOWeekStartDate | date | Monday of ISO week |
| ISO Week End Date | ISOWeekEndDate | date | Sunday of ISO week |
| ISO Year Week Index | ISOYearWeekIndex | int | Contiguous week index |
| ISO Week Offset | ISOWeekOffset | int | ISO weeks from AsOfDate |
| ISO Week Date Range | ISOWeekDateRange | text | "Jan 06 - Jan 12, 2025" |

### Phase 3: Monthly Fiscal (20 columns)

| Column (Spaced) | Column (PascalCase) | Type | Description |
|---|---|---|---|
| Fiscal Year Start Year | FiscalYearStartYear | int | Calendar year when fiscal year started |
| Fiscal Month Number | FiscalMonthNumber | int | Month within fiscal year (1-12) |
| Fiscal Quarter Number | FiscalQuarterNumber | int | Quarter within fiscal year (1-4) |
| Fiscal Year | FiscalYear | int | Fiscal year label |
| Fiscal Year Range | FiscalYearRange | text | "2024-2025" or "2025" |
| Fiscal Year Label | FiscalYearLabel | text | "FY 2025" |
| Fiscal Quarter Label | FiscalQuarterLabel | text | "Q1 FY2025" |
| Fiscal Month Name | FiscalMonthName | text | Calendar month name |
| Fiscal Month Short | FiscalMonthShort | text | 3-letter abbreviation |
| Fiscal Month Index | FiscalMonthIndex | int | Monotonic fiscal month counter |
| Fiscal Quarter Index | FiscalQuarterIndex | int | Monotonic fiscal quarter counter |
| Fiscal Year Start Date | FiscalYearStartDate | date | First day of fiscal year |
| Fiscal Year End Date | FiscalYearEndDate | date | Last day of fiscal year |
| Fiscal Quarter Start Date | FiscalQuarterStartDate | date | First day of fiscal quarter |
| Fiscal Quarter End Date | FiscalQuarterEndDate | date | Last day of fiscal quarter |
| Is Fiscal Year Start | IsFiscalYearStart | logical | First day of fiscal year |
| Is Fiscal Year End | IsFiscalYearEnd | logical | Last day of fiscal year |
| Is Fiscal Quarter Start | IsFiscalQuarterStart | logical | First day of fiscal quarter |
| Is Fiscal Quarter End | IsFiscalQuarterEnd | logical | Last day of fiscal quarter |
| Fiscal Month Offset | FiscalMonthOffset | int | Fiscal months from AsOfDate |
| Fiscal Quarter Offset | FiscalQuarterOffset | int | Fiscal quarters from AsOfDate |

### Phase 4: Weekly Fiscal (35 + 1 columns)

Only present when `IncludeWeeklyFiscal = true`.

| Column (Spaced) | Column (PascalCase) | Type | Description |
|---|---|---|---|
| FW Year Number | FWYearNumber | int | Weekly fiscal year |
| FW Start of Year | FWStartOfYear | date | First day of WF year |
| FW End of Year | FWEndOfYear | date | Last day of WF year |
| FW Year Label | FWYearLabel | text | "FY 2025" |
| FW Day of Year | FWDayOfYear | int | Day within WF year |
| FW Week Number | FWWeekNumber | int | Week within WF year (1-53) |
| FW Period Number | FWPeriodNumber | int | Period (1-13) |
| FW Quarter Number | FWQuarterNumber | int | Quarter (1-4) |
| FW Week in Quarter Number | FWWeekInQuarterNumber | int | Week within quarter (1-14) |
| FW Month Number | FWMonthNumber | int | Month within WF year (1-12) |
| FW Quarter Index | FWQuarterIndex | int | Monotonic quarter counter |
| FW Month Index | FWMonthIndex | int | Monotonic month counter |
| FW Week Day Number | FWWeekDayNumber | int | Day within week (1-7) |
| FW Week Day Name Short | FWWeekDayNameShort | text | "Mon", "Tue", etc. |
| FW Start of Week | FWStartOfWeek | date | First day of WF week |
| FW End of Week | FWEndOfWeek | date | Last day of WF week |
| FW Is Working Day | FWIsWorkingDay | logical | Monday-Friday |
| FW Day Type | FWDayType | text | "Working Day" / "Non-Working Day" |
| FW Start of Month | FWStartOfMonth | date | First day of WF month |
| FW End of Month | FWEndOfMonth | date | Last day of WF month |
| FW Day of Month | FWDayOfMonth | int | Day within WF month |
| FW Start of Quarter | FWStartOfQuarter | date | First day of WF quarter |
| FW End of Quarter | FWEndOfQuarter | date | Last day of WF quarter |
| FW Day of Quarter | FWDayOfQuarter | int | Day within WF quarter |
| FW Week Index | FWWeekIndex | int | Global contiguous week index |
| FW Quarter Label | FWQuarterLabel | text | "FQ1 - 2025" |
| FW Week Label | FWWeekLabel | text | "FW15 - 2025" |
| FW Week Date Range | FWWeekDateRange | text | "Mar 30 - Apr 05, 2025" |
| FW Period Label | FWPeriodLabel | text | "P03 - 2025" |
| FW Month Label | FWMonthLabel | text | "FM Apr - 2025" |
| FW Year Month Label | FWYearMonthLabel | text | "FM Apr 2025" |
| FW Week Offset | FWWeekOffset | int | WF weeks from AsOfDate |
| FW Month Offset | FWMonthOffset | int | WF months from AsOfDate |
| FW Quarter Offset | FWQuarterOffset | int | WF quarters from AsOfDate |
| Weekly Fiscal System | WeeklyFiscalSystem | text | "Weekly (445 Last)" |

## Column Counts

| Configuration | Columns |
|---|---|
| Default (no weekly fiscal) | 75 |
| With weekly fiscal | 111 |
