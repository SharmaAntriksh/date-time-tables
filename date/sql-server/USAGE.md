# Date Dimension Table — SQL Server

Stored procedure that generates a complete date dimension table. Returns a result set or persists to a permanent table.

## Setup

Execute the `usp_DateTable.sql` script in your database to create the stored procedure:

```sql
-- Run the script to create/update the procedure
-- Then call it:
EXEC dbo.usp_DateTable @Help = 1;  -- prints usage info
```

## Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| @StartDate | date | NULL *(required)* | First date in the table |
| @EndDate | date | NULL *(required)* | Last date in the table |
| @AsOfDate | date | NULL *(required)* | Reference date for relative offsets |
| @IncludeISO | bit | 1 | Include ISO-8601 week columns |
| @IncludeFiscal | bit | 1 | Include monthly fiscal columns |
| @FiscalStartMonth | int | 1 | First month of fiscal year (1-12) |
| @IncludeWeeklyFiscal | bit | 0 | Include 4-4-5 weekly fiscal columns |
| @FirstDayOfWeek | int | 0 | 0=Sunday, 1=Monday, ... 6=Saturday |
| @WeeklyType | nvarchar(10) | 'Last' | 'Last' or 'Nearest' |
| @QuarterWeekType | nvarchar(3) | '445' | '445', '454', or '544' |
| @TypeStartFiscalYear | int | 0 | 0=start-year, 1=end-year labeling |
| @ColumnNamingStyle | nvarchar(20) | 'Spaced' | 'Spaced' or 'PascalCase' (accepts partial like 'Pascal') |
| @OutputTable | nvarchar(256) | NULL | NULL returns result set. Set to a table name to persist (e.g. `'dbo.DimDate'`). Drops and recreates if table already exists |
| @Help | bit | 0 | 1 to print usage info |

## Usage Examples

### Help

```sql
-- Print usage information
EXEC dbo.usp_DateTable @Help = 1;
```

### Phase Selection

```sql
-- All defaults: Calendar + ISO + Fiscal (75 columns)
EXEC dbo.usp_DateTable
    @StartDate = '2021-01-01',
    @EndDate   = '2026-12-31',
    @AsOfDate  = '2025-04-05';

-- Calendar only (48 columns)
EXEC dbo.usp_DateTable
    @StartDate     = '2021-01-01',
    @EndDate       = '2026-12-31',
    @AsOfDate      = '2025-04-05',
    @IncludeISO    = 0,
    @IncludeFiscal = 0;

-- Calendar + ISO only (55 columns)
EXEC dbo.usp_DateTable
    @StartDate     = '2021-01-01',
    @EndDate       = '2026-12-31',
    @AsOfDate      = '2025-04-05',
    @IncludeFiscal = 0;

-- Calendar + Fiscal only, no ISO (68 columns)
EXEC dbo.usp_DateTable
    @StartDate     = '2021-01-01',
    @EndDate       = '2026-12-31',
    @AsOfDate      = '2025-04-05',
    @IncludeISO    = 0;

-- Everything: Calendar + ISO + Fiscal + Weekly Fiscal (111 columns)
EXEC dbo.usp_DateTable
    @StartDate           = '2021-01-01',
    @EndDate             = '2026-12-31',
    @AsOfDate            = '2025-04-05',
    @FiscalStartMonth    = 5,
    @IncludeWeeklyFiscal = 1;
```

### Fiscal Year Configuration

```sql
-- Fiscal year starting in January (fiscal = calendar year)
EXEC dbo.usp_DateTable
    @StartDate        = '2021-01-01',
    @EndDate          = '2026-12-31',
    @AsOfDate         = '2025-04-05',
    @FiscalStartMonth = 1;

-- Fiscal year starting in May (e.g. Microsoft)
EXEC dbo.usp_DateTable
    @StartDate        = '2021-01-01',
    @EndDate          = '2026-12-31',
    @AsOfDate         = '2025-04-05',
    @FiscalStartMonth = 5;

-- Fiscal year starting in July (e.g. US government)
EXEC dbo.usp_DateTable
    @StartDate        = '2021-01-01',
    @EndDate          = '2026-12-31',
    @AsOfDate         = '2025-04-05',
    @FiscalStartMonth = 7;

-- Fiscal year starting in October (e.g. many retailers)
EXEC dbo.usp_DateTable
    @StartDate        = '2021-01-01',
    @EndDate          = '2026-12-31',
    @AsOfDate         = '2025-04-05',
    @FiscalStartMonth = 10;
```

### Weekly Fiscal (4-4-5) Variants

```sql
-- 4-4-5 Last, Sunday start, end-year labeling (common US retail)
EXEC dbo.usp_DateTable
    @StartDate           = '2021-01-01',
    @EndDate             = '2026-12-31',
    @AsOfDate            = '2025-04-05',
    @FiscalStartMonth    = 2,
    @IncludeWeeklyFiscal = 1,
    @FirstDayOfWeek      = 0,
    @WeeklyType          = 'Last',
    @QuarterWeekType     = '445',
    @TypeStartFiscalYear = 1;

-- 4-5-4 Nearest, Monday start, start-year labeling
EXEC dbo.usp_DateTable
    @StartDate           = '2021-01-01',
    @EndDate             = '2026-12-31',
    @AsOfDate            = '2025-04-05',
    @FiscalStartMonth    = 2,
    @IncludeWeeklyFiscal = 1,
    @FirstDayOfWeek      = 1,
    @WeeklyType          = 'Nearest',
    @QuarterWeekType     = '454',
    @TypeStartFiscalYear = 0;

-- 5-4-4 Last, Saturday start, end-year labeling
EXEC dbo.usp_DateTable
    @StartDate           = '2021-01-01',
    @EndDate             = '2026-12-31',
    @AsOfDate            = '2025-04-05',
    @FiscalStartMonth    = 2,
    @IncludeWeeklyFiscal = 1,
    @FirstDayOfWeek      = 6,
    @WeeklyType          = 'Last',
    @QuarterWeekType     = '544',
    @TypeStartFiscalYear = 1;

-- Weekly fiscal with May fiscal start (e.g. Walmart-style)
EXEC dbo.usp_DateTable
    @StartDate           = '2021-01-01',
    @EndDate             = '2026-12-31',
    @AsOfDate            = '2025-04-05',
    @FiscalStartMonth    = 5,
    @IncludeWeeklyFiscal = 1,
    @FirstDayOfWeek      = 0,
    @WeeklyType          = 'Last',
    @QuarterWeekType     = '445',
    @TypeStartFiscalYear = 1;
```

### Column Naming

```sql
-- Spaced names (default): "Date Key", "Month Name", "Day of Week"
EXEC dbo.usp_DateTable
    @StartDate         = '2021-01-01',
    @EndDate           = '2026-12-31',
    @AsOfDate          = '2025-04-05',
    @ColumnNamingStyle = 'Spaced';

-- PascalCase names: "DateKey", "MonthName", "DayOfWeek"
EXEC dbo.usp_DateTable
    @StartDate         = '2021-01-01',
    @EndDate           = '2026-12-31',
    @AsOfDate          = '2025-04-05',
    @ColumnNamingStyle = 'Pascal';
```

### Persisting to a Table

```sql
-- Create dbo.DimDate with default settings
EXEC dbo.usp_DateTable
    @StartDate   = '2021-01-01',
    @EndDate     = '2026-12-31',
    @AsOfDate    = '2025-04-05',
    @OutputTable = 'dbo.DimDate';

-- Create in a custom schema
EXEC dbo.usp_DateTable
    @StartDate   = '2021-01-01',
    @EndDate     = '2026-12-31',
    @AsOfDate    = '2025-04-05',
    @OutputTable = 'dim.Date';

-- Re-run to refresh (drops and recreates automatically)
EXEC dbo.usp_DateTable
    @StartDate   = '2021-01-01',
    @EndDate     = '2026-12-31',
    @AsOfDate    = '2025-04-05',
    @OutputTable = 'dbo.DimDate';

-- Persist calendar-only with PascalCase
EXEC dbo.usp_DateTable
    @StartDate         = '2021-01-01',
    @EndDate           = '2026-12-31',
    @AsOfDate          = '2025-04-05',
    @IncludeISO        = 0,
    @IncludeFiscal     = 0,
    @ColumnNamingStyle = 'Pascal',
    @OutputTable       = 'dbo.DimDate';

-- Persist full weekly fiscal table
EXEC dbo.usp_DateTable
    @StartDate           = '2021-01-01',
    @EndDate             = '2026-12-31',
    @AsOfDate            = '2025-04-05',
    @FiscalStartMonth    = 5,
    @IncludeWeeklyFiscal = 1,
    @FirstDayOfWeek      = 0,
    @WeeklyType          = 'Last',
    @QuarterWeekType     = '445',
    @TypeStartFiscalYear = 1,
    @ColumnNamingStyle   = 'Spaced',
    @OutputTable         = 'dbo.DimDate';
```

### Date Range Variations

```sql
-- Single year
EXEC dbo.usp_DateTable
    @StartDate = '2025-01-01',
    @EndDate   = '2025-12-31',
    @AsOfDate  = '2025-04-05';

-- Wide range (20 years)
EXEC dbo.usp_DateTable
    @StartDate = '2010-01-01',
    @EndDate   = '2030-12-31',
    @AsOfDate  = '2025-04-05';

-- Historical analysis (AsOfDate in the past)
EXEC dbo.usp_DateTable
    @StartDate = '2020-01-01',
    @EndDate   = '2023-12-31',
    @AsOfDate  = '2022-06-30';

-- Future planning (AsOfDate = today, range extends forward)
EXEC dbo.usp_DateTable
    @StartDate = '2025-01-01',
    @EndDate   = '2030-12-31',
    @AsOfDate  = GETDATE();
```

## Column Reference

### Phase 1: Base Calendar (48 columns)

Always included.

| Column (Spaced) | Column (PascalCase) | Type | Description |
|---|---|---|---|
| Date | Date | date | The date (primary key when persisted) |
| Year | Year | int | Calendar year |
| Month | Month | int | Month (1-12) |
| Day | Day | int | Day of month (1-31) |
| Quarter | Quarter | int | Quarter (1-4) |
| Date Key | DateKey | bigint | YYYYMMDD |
| Date Serial Number | DateSerialNumber | int | Excel serial number |
| Month Name | MonthName | nvarchar | "January" |
| Month Short | MonthShort | nvarchar | "Jan" |
| Day Name | DayName | nvarchar | "Monday" |
| Day Short | DayShort | nvarchar | "Mon" |
| Day of Year | DayOfYear | int | 1-366 |
| Month Year | MonthYear | nvarchar | "Jan 2025" |
| Month Year Key | MonthYearKey | int | YYYYMM |
| Year Quarter Key | YearQuarterKey | int | YYYYQ |
| Quarter Year | QuarterYear | nvarchar | "Q1 2025" |
| Calendar Month Index | CalendarMonthIndex | int | Monotonic month counter |
| Calendar Quarter Index | CalendarQuarterIndex | int | Monotonic quarter counter |
| Day of Week | DayOfWeek | int | 0=Sunday ... 6=Saturday |
| Is Weekend | IsWeekend | bit | Saturday or Sunday |
| Is Business Day | IsBusinessDay | bit | Monday-Friday |
| Month Start Date | MonthStartDate | date | First day of month |
| Month End Date | MonthEndDate | date | Last day of month |
| Quarter Start Date | QuarterStartDate | date | First day of quarter |
| Quarter End Date | QuarterEndDate | date | Last day of quarter |
| Is Month Start | IsMonthStart | bit | First day of month |
| Is Month End | IsMonthEnd | bit | Last day of month |
| Is Quarter Start | IsQuarterStart | bit | First day of quarter |
| Is Quarter End | IsQuarterEnd | bit | Last day of quarter |
| Is Year Start | IsYearStart | bit | January 1 |
| Is Year End | IsYearEnd | bit | December 31 |
| Week of Month | WeekOfMonth | int | 1-6 |
| Calendar Week Start Date | CalendarWeekStartDate | date | Sunday |
| Calendar Week End Date | CalendarWeekEndDate | date | Saturday |
| Calendar Week Number | CalendarWeekNumber | int | 1-54 |
| Calendar Week Index | CalendarWeekIndex | int | Contiguous week index |
| Calendar Week Date Range | CalendarWeekDateRange | nvarchar | "Jan 05 - Jan 11, 2025" |
| Calendar Week Offset | CalendarWeekOffset | int | Weeks from @AsOfDate |
| Next Business Day | NextBusinessDay | date | Next Mon-Fri |
| Previous Business Day | PreviousBusinessDay | date | Previous Mon-Fri |
| Is Today | IsToday | bit | Date = @AsOfDate |
| Is Current Year | IsCurrentYear | bit | Same year as @AsOfDate |
| Is Current Month | IsCurrentMonth | bit | Same month as @AsOfDate |
| Is Current Quarter | IsCurrentQuarter | bit | Same quarter as @AsOfDate |
| Current Day Offset | CurrentDayOffset | int | Days from @AsOfDate |
| Year Offset | YearOffset | int | Years from @AsOfDate |
| Calendar Month Offset | CalendarMonthOffset | int | Months from @AsOfDate |
| Calendar Quarter Offset | CalendarQuarterOffset | int | Quarters from @AsOfDate |

### Phase 2: ISO Weeks (7 columns, when @IncludeISO = 1)

| Column (Spaced) | Column (PascalCase) | Type | Description |
|---|---|---|---|
| ISO Week Number | ISOWeekNumber | int | ISO week (1-53) |
| ISO Year | ISOYear | int | ISO year |
| ISO Week Start Date | ISOWeekStartDate | date | Monday |
| ISO Week End Date | ISOWeekEndDate | date | Sunday |
| ISO Year Week Index | ISOYearWeekIndex | int | Contiguous week index |
| ISO Week Offset | ISOWeekOffset | int | ISO weeks from @AsOfDate |
| ISO Week Date Range | ISOWeekDateRange | nvarchar | "Jan 06 - Jan 12, 2025" |

### Phase 3: Monthly Fiscal (20 columns, when @IncludeFiscal = 1)

| Column (Spaced) | Column (PascalCase) | Type | Description |
|---|---|---|---|
| Fiscal Year Start Year | FiscalYearStartYear | int | Calendar year when fiscal year started |
| Fiscal Month Number | FiscalMonthNumber | int | Month within fiscal year (1-12) |
| Fiscal Quarter Number | FiscalQuarterNumber | int | Quarter within fiscal year (1-4) |
| Fiscal Year | FiscalYear | int | Fiscal year label |
| Fiscal Year Range | FiscalYearRange | nvarchar | "2024-2025" or "2025" |
| Fiscal Year Label | FiscalYearLabel | nvarchar | "FY 2025" |
| Fiscal Quarter Label | FiscalQuarterLabel | nvarchar | "Q1 FY2025" |
| Fiscal Month Name | FiscalMonthName | nvarchar | Calendar month name |
| Fiscal Month Short | FiscalMonthShort | nvarchar | 3-letter abbreviation |
| Fiscal Month Index | FiscalMonthIndex | int | Monotonic fiscal month counter |
| Fiscal Quarter Index | FiscalQuarterIndex | int | Monotonic fiscal quarter counter |
| Fiscal Year Start Date | FiscalYearStartDate | date | First day of fiscal year |
| Fiscal Year End Date | FiscalYearEndDate | date | Last day of fiscal year |
| Fiscal Quarter Start Date | FiscalQuarterStartDate | date | First day of fiscal quarter |
| Fiscal Quarter End Date | FiscalQuarterEndDate | date | Last day of fiscal quarter |
| Is Fiscal Year Start | IsFiscalYearStart | bit | First day of fiscal year |
| Is Fiscal Year End | IsFiscalYearEnd | bit | Last day of fiscal year |
| Is Fiscal Quarter Start | IsFiscalQuarterStart | bit | First day of fiscal quarter |
| Is Fiscal Quarter End | IsFiscalQuarterEnd | bit | Last day of fiscal quarter |
| Fiscal Month Offset | FiscalMonthOffset | int | Fiscal months from @AsOfDate |
| Fiscal Quarter Offset | FiscalQuarterOffset | int | Fiscal quarters from @AsOfDate |

### Phase 4: Weekly Fiscal (35 + 1 columns, when @IncludeWeeklyFiscal = 1)

NULL when disabled.

| Column (Spaced) | Column (PascalCase) | Type | Description |
|---|---|---|---|
| FW Year Number | FWYearNumber | int | Weekly fiscal year |
| FW Start of Year | FWStartOfYear | date | First day of WF year |
| FW End of Year | FWEndOfYear | date | Last day of WF year |
| FW Year Label | FWYearLabel | nvarchar | "FY 2025" |
| FW Day of Year | FWDayOfYear | int | Day within WF year |
| FW Week Number | FWWeekNumber | int | Week (1-53) |
| FW Period Number | FWPeriodNumber | int | Period (1-13) |
| FW Quarter Number | FWQuarterNumber | int | Quarter (1-4) |
| FW Week in Quarter Number | FWWeekInQuarterNumber | int | Week within quarter (1-14) |
| FW Month Number | FWMonthNumber | int | Month (1-12) |
| FW Quarter Index | FWQuarterIndex | int | Monotonic quarter counter |
| FW Month Index | FWMonthIndex | int | Monotonic month counter |
| FW Week Day Number | FWWeekDayNumber | int | Day within week (1-7) |
| FW Week Day Name Short | FWWeekDayNameShort | nvarchar | "Mon" |
| FW Start of Week | FWStartOfWeek | date | First day of WF week |
| FW End of Week | FWEndOfWeek | date | Last day of WF week |
| FW Is Working Day | FWIsWorkingDay | bit | Monday-Friday |
| FW Day Type | FWDayType | nvarchar | "Working Day" / "Non-Working Day" |
| FW Start of Month | FWStartOfMonth | date | First day of WF month |
| FW End of Month | FWEndOfMonth | date | Last day of WF month |
| FW Day of Month | FWDayOfMonth | int | Day within WF month |
| FW Start of Quarter | FWStartOfQuarter | date | First day of WF quarter |
| FW End of Quarter | FWEndOfQuarter | date | Last day of WF quarter |
| FW Day of Quarter | FWDayOfQuarter | int | Day within WF quarter |
| FW Week Index | FWWeekIndex | int | Global contiguous week index |
| FW Quarter Label | FWQuarterLabel | nvarchar | "FQ1 - 2025" |
| FW Week Label | FWWeekLabel | nvarchar | "FW15 - 2025" |
| FW Week Date Range | FWWeekDateRange | nvarchar | "Mar 30 - Apr 05, 2025" |
| FW Period Label | FWPeriodLabel | nvarchar | "P03 - 2025" |
| FW Month Label | FWMonthLabel | nvarchar | "FM Apr - 2025" |
| FW Year Month Label | FWYearMonthLabel | nvarchar | "FM Apr 2025" |
| FW Week Offset | FWWeekOffset | int | WF weeks from @AsOfDate |
| FW Month Offset | FWMonthOffset | int | WF months from @AsOfDate |
| FW Quarter Offset | FWQuarterOffset | int | WF quarters from @AsOfDate |
| Weekly Fiscal System | WeeklyFiscalSystem | nvarchar | "Weekly (445 Last)" |

## Column Counts

| Configuration | Columns |
|---|---|
| Calendar only | 48 |
| Calendar + ISO | 55 |
| Calendar + ISO + Fiscal (default) | 75 |
| All phases | 111 |
