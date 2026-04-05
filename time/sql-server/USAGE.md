# Time Dimension Table — SQL Server

Stored procedure that generates a complete time dimension table at second or minute grain. Returns a result set or persists to a permanent table.

## Setup

Execute the `usp_TimeTable.sql` script in your database to create the stored procedure:

```sql
-- Run the script to create/update the procedure
-- Then call it:
EXEC dbo.usp_TimeTable @Help = 1;  -- prints usage info
```

## Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| @Grain | nvarchar(10) | 'Second' | 'Second' (86,400 rows) or 'Minute' (1,440 rows) |
| @IncludeLabels | bit | 1 | Include bin label columns |
| @ColumnNamingStyle | nvarchar(20) | 'Spaced' | 'Spaced' or 'PascalCase' (accepts partial like 'Pascal') |
| @OutputTable | nvarchar(256) | NULL | NULL returns result set. Set to a table name to persist (e.g. `'dbo.DimTime'`). Drops and recreates if table already exists |
| @Help | bit | 0 | 1 to print usage info |

## Usage Examples

### Help

```sql
-- Print usage information
EXEC dbo.usp_TimeTable @Help = 1;
```

### Grain Selection

```sql
-- Second grain (default, 86,400 rows, includes Second column)
EXEC dbo.usp_TimeTable;

-- Minute grain (1,440 rows, no Second column)
EXEC dbo.usp_TimeTable @Grain = 'Minute';
```

### Bin Labels

```sql
-- With bin labels (default): Bin15mLabel, Bin30mLabel, etc. included (36 columns at second grain)
EXEC dbo.usp_TimeTable @IncludeLabels = 1;

-- Without bin labels: keys only, no label columns (30 columns at second grain)
EXEC dbo.usp_TimeTable @IncludeLabels = 0;

-- Minute grain without labels (29 columns)
EXEC dbo.usp_TimeTable
    @Grain         = 'Minute',
    @IncludeLabels = 0;
```

### Column Naming

```sql
-- Spaced names (default): "Hour 24", "AM PM", "Time Key", "Period of Day Name"
EXEC dbo.usp_TimeTable @ColumnNamingStyle = 'Spaced';

-- PascalCase names: "Hour24", "AmPm", "TimeKey", "PeriodOfDayName"
EXEC dbo.usp_TimeTable @ColumnNamingStyle = 'Pascal';

-- Minute grain with PascalCase
EXEC dbo.usp_TimeTable
    @Grain             = 'Minute',
    @ColumnNamingStyle = 'Pascal';
```

### Persisting to a Table

```sql
-- Create dbo.DimTime with defaults (second grain, spaced names, with labels)
EXEC dbo.usp_TimeTable @OutputTable = 'dbo.DimTime';

-- Create in a custom schema
EXEC dbo.usp_TimeTable @OutputTable = 'dim.Time';

-- Re-run to refresh (drops and recreates automatically)
EXEC dbo.usp_TimeTable @OutputTable = 'dbo.DimTime';

-- Persist minute grain with PascalCase
EXEC dbo.usp_TimeTable
    @Grain             = 'Minute',
    @ColumnNamingStyle = 'Pascal',
    @OutputTable       = 'dbo.DimTime';

-- Persist second grain without labels
EXEC dbo.usp_TimeTable
    @Grain         = 'Second',
    @IncludeLabels = 0,
    @OutputTable   = 'dbo.DimTime';

-- Full example: all options specified
EXEC dbo.usp_TimeTable
    @Grain             = 'Second',
    @IncludeLabels     = 1,
    @ColumnNamingStyle = 'Spaced',
    @OutputTable       = 'dbo.DimTime';
```

### Combined Date + Time Tables

```sql
-- Create both dimension tables together
EXEC dbo.usp_DateTable
    @StartDate        = '2021-01-01',
    @EndDate          = '2026-12-31',
    @AsOfDate         = '2025-04-05',
    @FiscalStartMonth = 5,
    @OutputTable      = 'dbo.DimDate';

EXEC dbo.usp_TimeTable
    @Grain       = 'Minute',
    @OutputTable = 'dbo.DimTime';
```

## Column Reference

### Core Columns (10-11)

| Column (Spaced) | Column (PascalCase) | Type | Description |
|---|---|---|---|
| Time | Time | time(0) | The time value |
| Hour 24 | Hour24 | int | Hour (0-23) |
| Hour 12 | Hour12 | int | Hour (1-12). Noon and midnight = 12 |
| Minute | Minute | int | Minute (0-59) |
| Second | Second | int | Second (0-59). **Only at second grain** |
| AM PM | AmPm | nvarchar | "AM" or "PM" |
| Hour 12 Text | Hour12Text | nvarchar | "3 PM", "12 AM" |
| Time Key | TimeKey | int | Sort key. Second: HHMMSS. Minute: HHMM |
| Time Text | TimeText | nvarchar | "15:00" |
| Time Seconds | TimeSeconds | int | Seconds since midnight (0-86399) |
| Time of Day | TimeOfDay | nvarchar | "15:00:00" |

### Bin Keys (5 columns, always present)

| Column (Spaced) | Column (PascalCase) | Type | Range | Description |
|---|---|---|---|---|
| Bin 15m Key | Bin15mKey | int | 0-95 | 15-minute bin |
| Bin 30m Key | Bin30mKey | int | 0-47 | 30-minute bin |
| Bin 1h Key | Bin1hKey | int | 0-23 | 1-hour bin |
| Bin 6h Key | Bin6hKey | int | 0-3 | 6-hour bin |
| Bin 12h Key | Bin12hKey | int | 0-1 | 12-hour bin |

### Bin Labels (6 columns, when @IncludeLabels = 1)

NULL when `@IncludeLabels = 0`.

| Column (Spaced) | Column (PascalCase) | Type | Example | Style |
|---|---|---|---|---|
| Bin 15m Label | Bin15mLabel | nvarchar | "13:30-13:45" | Half-open |
| Bin 30m Label | Bin30mLabel | nvarchar | "13:30-14:00" | Half-open |
| Bin 1h Label | Bin1hLabel | nvarchar | "13:00-13:59" | Inclusive |
| Bin 6h Label | Bin6hLabel | nvarchar | "12:00-17:59" | Inclusive |
| Bin 12h Label | Bin12hLabel | nvarchar | "12:00-23:59" | Inclusive |
| Bin 12h Name | Bin12hName | nvarchar | "After Noon" | Descriptive |

### Period of Day (2 columns)

| Column (Spaced) | Column (PascalCase) | Type | Description |
|---|---|---|---|
| Period of Day Name | PeriodOfDayName | nvarchar | Segment name |
| Period of Day Name Sort | PeriodOfDayNameSort | int | Sort order (1-6) |

| Sort | Name | Hours |
|---|---|---|
| 1 | Midnight | 0-4 |
| 2 | Early Morning | 5-8 |
| 3 | Morning | 9-12 |
| 4 | Afternoon | 13-16 |
| 5 | Evening | 17-20 |
| 6 | Night | 21-23 |

### 12-Hour Period (3 columns)

| Column (Spaced) | Column (PascalCase) | Type | Description |
|---|---|---|---|
| 12 Hour Period Name | TwelveHourPeriodName | nvarchar | "Before Noon" / "After Noon" |
| 12 Hour Bin | TwelveHourBin | nvarchar | "0-11" / "12-23" |
| 12 Hour Bin Sort | TwelveHourBinSort | int | 1-2 |

### 6-Hour Period (3 columns)

| Column (Spaced) | Column (PascalCase) | Type | Description |
|---|---|---|---|
| 6 Hour Period Name | SixHourPeriodName | nvarchar | Customizable name |
| 6 Hour Bin | SixHourBin | nvarchar | "0-5", "6-11", "12-17", "18-23" |
| 6 Hour Bin Sort | SixHourBinSort | int | 1-4 |

Default names: Down Time, Login, Meetings, Logout.

### 30-Minute Period (3 columns)

| Column (Spaced) | Column (PascalCase) | Type | Description |
|---|---|---|---|
| 30 Minute Period Name | ThirtyMinutePeriodName | nvarchar | Customizable (default: "Description") |
| 30 Minute Bin | ThirtyMinuteBin | nvarchar | "0-29", "30-59" |
| 30 Minute Bin Sort | ThirtyMinuteBinSort | int | 1-2 |

### 15-Minute Period (3 columns)

| Column (Spaced) | Column (PascalCase) | Type | Description |
|---|---|---|---|
| 15 Minute Period Name | FifteenMinutePeriodName | nvarchar | Customizable (default: "Description") |
| 15 Minute Bin | FifteenMinuteBin | nvarchar | "0-14", "15-29", "30-44", "45-59" |
| 15 Minute Bin Sort | FifteenMinuteBinSort | int | 1-4 |

## Customization

To change period names, edit the `INSERT INTO` values for the lookup table variables in the stored procedure:

```sql
-- Example: rename 6-hour periods
INSERT INTO @SixHour VALUES
    (0,  5,  N'Night Shift',   N'0-5',   1),
    (6,  11, N'Morning Shift', N'6-11',  2),
    (12, 17, N'Day Shift',     N'12-17', 3),
    (18, 23, N'Evening Shift', N'18-23', 4);
```

## Column Counts

| Configuration | Columns |
|---|---|
| Second grain, with labels | 36 |
| Second grain, without labels | 30 |
| Minute grain, with labels | 35 |
| Minute grain, without labels | 29 |
