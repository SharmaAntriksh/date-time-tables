# Time Dimension Table - Power Query

Function that generates a time dimension table at second or minute grain.

## Setup

1. Import `time.pq` as a query named `fn_TimeTable` in Power BI Desktop (Home > Transform Data > New Source > Blank Query, then paste into Advanced Editor)
2. Invoke it with your parameters

## Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| Grain | text | *(required)* | `"Second"` (86,400 rows) or `"Minute"` (1,440 rows) |
| ColumnNamingStyle | text (optional) | `"Spaced"` | `"Spaced"` or `"PascalCase"` |

## Usage

```powerquery
// Second grain with spaced names (default)
fn_TimeTable( "Second" )

// Minute grain
fn_TimeTable( "Minute" )

// Second grain with PascalCase names
fn_TimeTable( "Second", "PascalCase" )

// Minute grain with PascalCase names
fn_TimeTable( "Minute", "Pascal" )
```

## Column Reference

### Core Columns

| Column (PascalCase) | Column (Spaced) | Type | Description |
|---|---|---|---|
| Time | Time | time | The time value |
| Hour24 | Hour 24 | Int64 | Hour in 24-hour format (0-23) |
| Hour12 | Hour 12 | Int64 | Hour in 12-hour format (1-12). Noon and midnight = 12 |
| Minute | Minute | Int64 | Minute (0-59) |
| Second | Second | Int64 | Second (0-59). **Only present at second grain** |
| AmPm | AM PM | text | "AM" or "PM" |
| Hour12Text | Hour 12 Text | text | "3 PM", "12 AM" |
| TimeKey | Time Key | Int64 | Sort key. Second: HHMMSS. Minute: HHMM |

### Computed Columns

| Column | Type | Description |
|---|---|---|
| TimeText | text | "15:00" (HH:MM) |
| TimeSeconds | Int64 | Seconds since midnight (0-86399) |
| TimeOfDay | text | "15:00:00" (HH:MM:SS, for `Time.FromText`) |

### Bin Keys

| Column | Type | Range | Description |
|---|---|---|---|
| Bin15mKey | Int64 | 0-95 | 15-minute bin index |
| Bin30mKey | Int64 | 0-47 | 30-minute bin index |
| Bin1hKey | Int64 | 0-23 | 1-hour bin index |
| Bin6hKey | Int64 | 0-3 | 6-hour bin index |
| Bin12hKey | Int64 | 0-1 | 12-hour bin index |

### Bin Labels

| Column | Type | Example | Style |
|---|---|---|---|
| Bin15mLabel | text | "13:30-13:45" | Half-open range |
| Bin30mLabel | text | "13:30-14:00" | Half-open range |
| Bin1hLabel | text | "13:00-13:59" | Inclusive |
| Bin6hLabel | text | "12:00-17:59" | Inclusive |
| Bin12hLabel | text | "12:00-23:59" | Inclusive |
| Bin12hName | text | "After Noon" | "Before Noon" / "After Noon" |

### Period of Day (6 segments)

| Column | Type | Description |
|---|---|---|
| Period of Day Name | text | Segment name |
| Period of Day Name Sort | Int64 | Sort order (1-6) |

| Sort | Name | Hours |
|---|---|---|
| 1 | Midnight | 0-4 |
| 2 | Early Morning | 5-8 |
| 3 | Morning | 9-12 |
| 4 | Afternoon | 13-16 |
| 5 | Evening | 17-20 |
| 6 | Night | 21-23 |

### 12-Hour Period

| Column | Type | Description |
|---|---|---|
| 12 Hour Period Name | text | "Before Noon" or "After Noon" |
| 12 Hour Bin | text | "0-11" or "12-23" |
| 12 Hour Bin Sort | Int64 | Sort order (1-2) |

### 6-Hour Period

| Column | Type | Description |
|---|---|---|
| 6 Hour Period Name | text | Customizable name |
| 6 Hour Bin | text | "0-5", "6-11", "12-17", "18-23" |
| 6 Hour Bin Sort | Int64 | Sort order (1-4) |

Default names: Down Time, Login, Meetings, Logout.

### 30-Minute Period

| Column | Type | Description |
|---|---|---|
| 30 Minute Period Name | text | Customizable name (default: "Description") |
| 30 Minute Bin | text | "0-29", "30-59" |
| 30 Minute Bin Sort | Int64 | Sort order (1-2) |

### 15-Minute Period

| Column | Type | Description |
|---|---|---|
| 15 Minute Period Name | text | Customizable name (default: "Description") |
| 15 Minute Bin | text | "0-14", "15-29", "30-44", "45-59" |
| 15 Minute Bin Sort | Int64 | Sort order (1-4) |

## Customization

To change period names, edit the lookup table definitions at the top of `time.pq`. For example, to rename the 6-hour periods:

```powerquery
SixHourPeriod = Table.FromColumns (
    {
        { 0, 6, 12, 18 },
        { 5, 11, 17, 23 },
        { "Night Shift", "Morning Shift", "Day Shift", "Evening Shift" },  // your names
        { "0-5", "6-11", "12-17", "18-23" },
        { 1, 2, 3, 4 }
    },
    ...
```

## Column Counts

| Grain | Columns |
|---|---|
| Second | 36 |
| Minute | 35 |
