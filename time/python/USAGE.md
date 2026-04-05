# Time Dimension Table — Python

Standalone script that generates a minute-grain time dimension table (1,440 rows) and outputs it as CSV or Parquet.

## Requirements

- Python 3.9+
- pandas, numpy
- pyarrow (optional, for Parquet output)

## Setup

Edit the configuration section at the bottom of `generate_time_table.py`, then run:

```bash
python generate_time_table.py
```

## Configuration

```python
# ── Column options ────────────────────────────────────────────────
INCLUDE_LABELS = True           # human-readable bin labels (e.g. "13:30-13:45")

# ── Output ────────────────────────────────────────────────────────
OUTPUT_FORMAT = "csv"           # "csv" or "parquet"
OUTPUT_DIR = "./output"
```

| Setting | Values | Default | Description |
|---|---|---|---|
| INCLUDE_LABELS | True / False | True | Include bin label columns (Bin15Label, Bin30Label, etc.) |
| OUTPUT_FORMAT | "csv" / "parquet" | "csv" | Output file format |
| OUTPUT_DIR | path string | "./output" | Output directory (created if it doesn't exist) |

## Usage Examples

### Basic

```python
# Edit generate_time_table.py:
INCLUDE_LABELS = True
OUTPUT_FORMAT = "csv"
OUTPUT_DIR = "./output"

# Then run:
# python generate_time_table.py
# Output: ./output/time.csv (1,440 rows x 18 columns)
```

### Without Labels

```python
INCLUDE_LABELS = False
# Output: 13 columns (keys only, no label strings)
```

### Parquet Output

```python
OUTPUT_FORMAT = "parquet"
# Output: ./output/time.parquet (snappy compression)
```

### Custom Output Directory

```python
OUTPUT_DIR = "./data/dimensions"
# Output: ./data/dimensions/time.csv
```

### Programmatic Use

```python
from generate_time_table import generate_time_table

# Default (with labels)
df = generate_time_table()
print(df.shape)  # (1440, 18)

# Without labels
df = generate_time_table(include_labels=False)
print(df.shape)  # (1440, 13)

# Use in a pipeline
df = generate_time_table()
df.to_sql("dim_time", engine, if_exists="replace", index=False)
```

### List Columns

```python
from generate_time_table import _print_columns
_print_columns()
```

## Column Reference

### Base Columns (13, always present)

| Column | Type | Description |
|---|---|---|
| TimeKey | int32 | Minute of day (0-1439) |
| Hour | int32 | Hour (0-23) |
| Minute | int32 | Minute (0-59) |
| TimeText | str | "15:00" (HH:MM) |
| TimeKey15 | int32 | 15-minute bin key (0-95) |
| TimeKey30 | int32 | 30-minute bin key (0-47) |
| TimeKey60 | int32 | 1-hour bin key (0-23) |
| TimeKey360 | int32 | 6-hour bin key (0-3) |
| TimeKey720 | int32 | 12-hour bin key (0-1) |
| TimeBucketKey4 | int32 | 6-hour bucket key (same as TimeKey360) |
| TimeBucket4 | str | "Night", "Morning", "Afternoon", "Evening" |
| TimeSeconds | int32 | Seconds since midnight (0-86340) |
| TimeOfDay | str | "15:00:00" (HH:MM:SS) |

### Bin Label Columns (5, when INCLUDE_LABELS = True)

| Column | Type | Example | Label Style |
|---|---|---|---|
| Bin15Label | str | "13:30-13:45" | Half-open range |
| Bin30Label | str | "13:30-14:00" | Half-open range |
| Bin60Label | str | "13:00-14:00" | Half-open range |
| Bin6hLabel | str | "12:00-17:59" | Inclusive |
| Bin12hLabel | str | "12:00-23:59" | Inclusive |

### TimeBucket4 Values

| Key | Name | Hours |
|---|---|---|
| 0 | Night | 0-5 |
| 1 | Morning | 6-11 |
| 2 | Afternoon | 12-17 |
| 3 | Evening | 18-23 |

## Column Counts

| Configuration | Columns |
|---|---|
| With labels (default) | 18 |
| Without labels | 13 |

## Notes

- This generator is minute-grain only (1,440 rows). For second-grain (86,400 rows), use the Power Query or SQL Server implementations.
- The `TimeBucket4` column uses fixed 6-hour segments named Night/Morning/Afternoon/Evening. To customize, edit the `_bucket_names` array in the `generate_time_table()` function.
