# Date Dimension Table — Python

Standalone script that generates a date dimension table and outputs it as CSV or Parquet.

## Requirements

- Python 3.9+
- pandas, numpy
- pyarrow (for Parquet output)

## Setup

Edit the configuration section at the bottom of `generate_date_table.py`:

```python
# =====================================================================
# Configuration — edit these values
# =====================================================================
START_DATE = "2021-01-01"
END_DATE = "2026-12-31"
AS_OF_DATE = "2025-04-05"           # or None for today
FISCAL_START_MONTH = 5              # 1-12
INCLUDE_CALENDAR = True             # as-of relative columns
INCLUDE_ISO = True                  # ISO-8601 week columns
INCLUDE_FISCAL = True               # monthly fiscal columns
WEEKLY_FISCAL = WeeklyFiscalConfig(
    enabled=False,
    first_day_of_week=0,            # 0=Sun, 1=Mon, ... 6=Sat
    weekly_type="Last",             # "Last" or "Nearest"
    quarter_week_type="445",        # "445", "454", "544"
    type_start_fiscal_year=1,       # 0=start-year, 1=end-year
)
OUTPUT_FORMAT = "parquet"           # "csv" or "parquet"
OUTPUT_PATH = "output/dates"
```

Then run:

```bash
python generate_date_table.py
```

## Parameters

### WeeklyFiscalConfig

| Field | Type | Default | Description |
|---|---|---|---|
| enabled | bool | False | Enable weekly fiscal columns |
| first_day_of_week | int | 0 | 0=Sunday, 1=Monday, ... 6=Saturday |
| weekly_type | str | "Last" | "Last" or "Nearest" |
| quarter_week_type | str | "445" | "445", "454", or "544" |
| type_start_fiscal_year | int | 1 | 0=start-year, 1=end-year labeling |

### Include Flags

| Flag | Default | Controls |
|---|---|---|
| INCLUDE_CALENDAR | True | As-of relative columns (IsToday, offsets, current flags) |
| INCLUDE_ISO | True | ISO-8601 week columns |
| INCLUDE_FISCAL | True | Monthly fiscal columns |
| WEEKLY_FISCAL.enabled | False | Weekly fiscal (4-4-5) columns |

## Column Reference

### Base Columns (34 columns, always present)

| Column | Type | Description |
|---|---|---|
| Date | datetime | The date |
| DateKey | int64 | YYYYMMDD integer key |
| DateSerialNumber | int32 | Excel serial number |
| Year | int32 | Calendar year |
| Quarter | int32 | Calendar quarter (1-4) |
| QuarterStartDate | datetime | First day of quarter |
| QuarterEndDate | datetime | Last day of quarter |
| QuarterYear | str | "Q1 2025" |
| Month | int32 | Calendar month (1-12) |
| MonthName | str | "January" |
| MonthShort | str | "Jan" |
| MonthStartDate | datetime | First day of month |
| MonthEndDate | datetime | Last day of month |
| MonthYear | str | "Jan 2025" |
| MonthYearKey | int32 | YYYYMM |
| YearQuarterKey | int32 | YYYYQ |
| CalendarMonthIndex | int32 | Monotonic month counter |
| CalendarQuarterIndex | int32 | Monotonic quarter counter |
| WeekOfMonth | int32 | 1-6 (day-based) |
| CalendarWeekNumber | int32 | 1-54 (Sunday-based) |
| CalendarWeekStartDate | datetime | Sunday of the week |
| CalendarWeekEndDate | datetime | Saturday of the week |
| CalendarWeekDateRange | str | "Jan 05 - Jan 11, 2025" |
| CalendarWeekIndex | int32 | Contiguous week index |
| CalendarWeekOffset | int32 | Weeks from as_of |
| Day | int32 | Day of month |
| DayName | str | "Monday" |
| DayShort | str | "Mon" |
| DayOfYear | int32 | 1-366 |
| DayOfWeek | int32 | 0=Sunday ... 6=Saturday |
| IsWeekend | bool | Saturday or Sunday |
| IsBusinessDay | bool | Monday-Friday |
| NextBusinessDay | datetime | Next Mon-Fri |
| PreviousBusinessDay | datetime | Previous Mon-Fri |

### Calendar Columns (14 columns, when INCLUDE_CALENDAR = True)

| Column | Type | Description |
|---|---|---|
| IsYearStart | bool | January 1 |
| IsYearEnd | bool | December 31 |
| IsQuarterStart | bool | First day of quarter |
| IsQuarterEnd | bool | Last day of quarter |
| IsMonthStart | bool | First day of month |
| IsMonthEnd | bool | Last day of month |
| IsToday | bool | Date = as_of |
| IsCurrentYear | bool | Same year as as_of |
| IsCurrentMonth | bool | Same month as as_of |
| IsCurrentQuarter | bool | Same quarter as as_of |
| CurrentDayOffset | int32 | Days from as_of |
| YearOffset | int32 | Years from as_of |
| CalendarMonthOffset | int32 | Months from as_of |
| CalendarQuarterOffset | int32 | Quarters from as_of |

### ISO Columns (7 columns, when INCLUDE_ISO = True)

| Column | Type | Description |
|---|---|---|
| ISOWeekNumber | int32 | ISO week (1-53) |
| ISOYear | int32 | ISO year |
| ISOYearWeekIndex | int32 | Contiguous week index |
| ISOWeekOffset | int32 | ISO weeks from as_of |
| ISOWeekStartDate | datetime | Monday of ISO week |
| ISOWeekEndDate | datetime | Sunday of ISO week |
| ISOWeekDateRange | str | "Jan 06 - Jan 12, 2025" |

### Fiscal Columns (21 columns, when INCLUDE_FISCAL = True)

| Column | Type | Description |
|---|---|---|
| FiscalYearStartYear | int32 | Calendar year when fiscal year started |
| FiscalMonthNumber | int32 | Month within fiscal year (1-12) |
| FiscalQuarterNumber | int32 | Quarter within fiscal year (1-4) |
| FiscalMonthIndex | int32 | Monotonic fiscal month counter |
| FiscalQuarterIndex | int32 | Monotonic fiscal quarter counter |
| FiscalMonthOffset | int32 | Fiscal months from as_of |
| FiscalQuarterOffset | int32 | Fiscal quarters from as_of |
| FiscalQuarterLabel | str | "Q1 FY2025" |
| FiscalMonthName | str | Calendar month name |
| FiscalMonthShort | str | 3-letter abbreviation |
| FiscalYearRange | str | "2024-2025" or "2025" |
| FiscalYearStartDate | datetime | First day of fiscal year |
| FiscalYearEndDate | datetime | Last day of fiscal year |
| FiscalQuarterStartDate | datetime | First day of fiscal quarter |
| FiscalQuarterEndDate | datetime | Last day of fiscal quarter |
| IsFiscalYearStart | bool | First day of fiscal year |
| IsFiscalYearEnd | bool | Last day of fiscal year |
| IsFiscalQuarterStart | bool | First day of fiscal quarter |
| IsFiscalQuarterEnd | bool | Last day of fiscal quarter |
| FiscalYear | int32 | Fiscal year label |
| FiscalYearLabel | str | "FY 2025" |

### Weekly Fiscal Columns (35 columns, when enabled)

| Column | Type | Description |
|---|---|---|
| FWYearNumber | int | Weekly fiscal year |
| FWYearLabel | str | "FY 2025" |
| FWQuarterNumber | int | Quarter (1-4) |
| FWQuarterLabel | str | "FQ1 - 2025" |
| FWQuarterIndex | int | Monotonic quarter counter |
| FWQuarterOffset | int | WF quarters from as_of |
| FWMonthNumber | int | Month (1-12) |
| FWMonthLabel | str | "FM Apr - 2025" |
| FWMonthIndex | int | Monotonic month counter |
| FWMonthOffset | int | WF months from as_of |
| FWWeekNumber | int | Week (1-53) |
| FWWeekLabel | str | "FW15 - 2025" |
| FWWeekDateRange | str | "Mar 30 - Apr 05, 2025" |
| FWWeekIndex | int | Global contiguous week index |
| FWWeekOffset | int | WF weeks from as_of |
| FWPeriodNumber | int | Period (1-13) |
| FWPeriodLabel | str | "P03 - 2025" |
| FWStartOfYear | datetime | First day of WF year |
| FWEndOfYear | datetime | Last day of WF year |
| FWStartOfQuarter | datetime | First day of WF quarter |
| FWEndOfQuarter | datetime | Last day of WF quarter |
| FWStartOfMonth | datetime | First day of WF month |
| FWEndOfMonth | datetime | Last day of WF month |
| FWStartOfWeek | datetime | First day of WF week |
| FWEndOfWeek | datetime | Last day of WF week |
| FWWeekDayNumber | int | Day within week (1-7) |
| FWWeekDayNameShort | str | "Mon", "Tue", etc. |
| FWDayOfYear | int | Day within WF year |
| FWDayOfQuarter | int | Day within WF quarter |
| FWDayOfMonth | int | Day within WF month |
| FWIsWorkingDay | bool | Monday-Friday |
| FWDayType | str | "Working Day" / "Non-Working Day" |
| FWWeekInQuarterNumber | int | Week within quarter (1-14) |
| FWYearMonthLabel | str | "FM Apr 2025" |
| WeeklyFiscalSystem | str | "Weekly (445 Last)" |

## Column Counts

| Configuration | Columns |
|---|---|
| Base only | 34 |
| Base + Calendar | 48 |
| Base + Calendar + ISO | 55 |
| Base + Calendar + ISO + Fiscal (typical) | 76 |
| All (with weekly fiscal) | 111 |
