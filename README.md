# Date & Time Dimension Tables

Production-ready date and time dimension table generators for business intelligence, data warehousing, and analytics pipelines. Available in **SQL Server**, **Python**, and **Power Query (M)**.

## Features

- **Multi-platform** - identical output and column names across SQL Server, Python, and Power Query
- **Configurable** - toggle calendar, ISO-8601, fiscal, and weekly fiscal (4-4-5/4-5-4/5-4-4) columns independently
- **Fiscal calendar support** - any fiscal start month, with dedicated fiscal year/quarter/month columns
- **Weekly fiscal calendars** - 4-4-5, 4-5-4, and 5-4-4 patterns used in retail and enterprise reporting
- **As-of relative columns** - IsToday, CurrentDayOffset, YearOffset, QuarterOffset, and more
- **Column naming styles** - choose between `PascalCase` and `Spaced` naming

## Structure

```
date-time-tables/
├── date/
│   ├── python/              # Standalone Python generator
│   ├── sql-server/          # T-SQL stored procedure
│   └── power-query/         # Modular & standalone Power Query functions
├── time/
│   ├── python/              # Standalone Python generator
│   ├── sql-server/          # T-SQL stored procedure
│   └── power-query/         # Power Query function
└── output/                  # Example output files (Parquet, CSV)
```

## Quick Start

### Python

```bash
pip install pandas numpy pyarrow
```

```python
from date.python.generate_date_table import generate_date_table
from time.python.generate_time_table import generate_time_table

dates = generate_date_table(
    start_date="2021-01-01",
    end_date="2026-12-31",
    fiscal_start_month=7
)

times = generate_time_table(grain="minute")
```

### SQL Server

```sql
-- Date dimension
EXEC dbo.usp_DateTable
    @StartDate = '2021-01-01',
    @EndDate = '2026-12-31',
    @FiscalStartMonth = 7;

-- Time dimension
EXEC dbo.usp_TimeTable @Grain = 'minute';
```

### Power Query

Import `fn_DateTable.pq` (standalone) or the modular functions (`fn_Calendar.pq`, `fn_ISOWeeks.pq`, `fn_Fiscal.pq`, `fn_WeeklyFiscal.pq`, `fn_Orchestrate.pq`) into Power BI or Excel. See the included `Date Table.pbix` for a working example.

## Parameters

| Parameter | Description | Default |
|---|---|---|
| StartDate | Beginning of date range | - |
| EndDate | End of date range | - |
| AsOfDate | Reference date for relative columns | Today |
| FiscalStartMonth | Fiscal year start month (1-12) | 1 |
| IncludeISO | Include ISO-8601 week columns | true |
| IncludeFiscal | Include fiscal year columns | true |
| IncludeWeeklyFiscal | Include 4-4-5 weekly fiscal columns | false |
| FirstDayOfWeek | 0 = Sunday … 6 = Saturday | 0 |
| WeeklyType | `Last` or `Nearest` (weekly fiscal) | Last |
| QuarterWeekType | `445`, `454`, or `544` | 445 |
| ColumnNamingStyle | `PascalCase` or `Spaced` | PascalCase |

## Documentation

Each implementation includes a detailed `USAGE.md` with setup instructions, parameter reference, usage examples, and a complete column dictionary:

- [Date - Python](date/python/USAGE.md)
- [Date - SQL Server](date/sql-server/USAGE.md)
- [Date - Power Query](date/power-query/USAGE.md)
- [Time - Python](time/python/USAGE.md)
- [Time - SQL Server](time/sql-server/USAGE.md)
- [Time - Power Query](time/power-query/USAGE.md)

## Attribution

The weekly fiscal calendar logic is based on [SQLBI's DAX date template](https://github.com/sql-bi/DaxDateTemplate) by Marco Russo and Alberto Ferrari.

## License

This project is licensed under the [MIT License](LICENSE).
