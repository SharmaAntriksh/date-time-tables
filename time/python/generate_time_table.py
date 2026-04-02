"""
Standalone Time Dimension Generator
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Generates an analytics-ready time dimension table (minute grain, 1 440 rows)
for BI, data warehousing, and analytics pipelines.

Requirements:  Python 3.9+, pandas, numpy, pyarrow (for parquet output)

Usage:
    Edit the parameters in the "Configuration" section at the bottom of
    this file, then run:

        python generate_time_table.py
"""
from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd


# =====================================================================
# Generation
# =====================================================================

def _fmt_hhmm(minute_of_day: int) -> str:
    if minute_of_day == 24 * 60:
        return "24:00"
    h, m = divmod(int(minute_of_day), 60)
    return f"{h:02d}:{m:02d}"


def _label_range(start_min: int, width_min: int) -> str:
    """Half-open label like 13:30-13:45."""
    return f"{_fmt_hhmm(start_min)}-{_fmt_hhmm(start_min + width_min)}"


def _label_block_inclusive(start_min: int, block_min: int) -> str:
    """Inclusive-end label like 00:00-05:59."""
    end_min = min(24 * 60 - 1, start_min + block_min - 1)
    return f"{_fmt_hhmm(start_min)}-{_fmt_hhmm(end_min)}"


def generate_time_table(*, include_labels: bool = True) -> pd.DataFrame:
    """Generate a minute-grain time dimension (1 440 rows).

    Parameters
    ----------
    include_labels : bool
        Include human-readable bin labels for each bucket size
        (default True).
    """
    t_arr = np.arange(24 * 60, dtype=np.int32)
    hour = t_arr // 60
    minute = t_arr % 60
    k15 = t_arr // 15
    k30 = t_arr // 30
    k60 = t_arr // 60
    k360 = t_arr // 360
    k720 = t_arr // 720

    _bucket_names = np.array(["Night", "Morning", "Afternoon", "Evening"])
    bucket_name4 = _bucket_names[k360]

    time_text = np.char.add(
        np.char.zfill(hour.astype(str), 2),
        np.char.add(":", np.char.zfill(minute.astype(str), 2)),
    )

    data: dict = {
        "TimeKey": t_arr,
        "Hour": hour,
        "Minute": minute,
        "TimeText": time_text,
    }

    if include_labels:
        _v_label_range = np.vectorize(
            lambda k, w: _label_range(int(k) * w, w), otypes=[object]
        )
        _v_label_block = np.vectorize(
            lambda k, w: _label_block_inclusive(int(k) * w, w), otypes=[object]
        )
        data["TimeKey15"] = k15
        data["Bin15Label"] = _v_label_range(k15, 15)
        data["TimeKey30"] = k30
        data["Bin30Label"] = _v_label_range(k30, 30)
        data["TimeKey60"] = k60
        data["Bin60Label"] = _v_label_range(k60, 60)
        data["TimeKey360"] = k360
        data["Bin6hLabel"] = _v_label_block(k360, 360)
        data["TimeKey720"] = k720
        data["Bin12hLabel"] = _v_label_block(k720, 720)
        data["TimeBucketKey4"] = k360
        data["TimeBucket4"] = bucket_name4
    else:
        data["TimeKey15"] = k15
        data["TimeKey30"] = k30
        data["TimeKey60"] = k60
        data["TimeKey360"] = k360
        data["TimeKey720"] = k720
        data["TimeBucketKey4"] = k360
        data["TimeBucket4"] = bucket_name4

    df = pd.DataFrame(data)
    df["TimeSeconds"] = (hour.astype(int) * 3600 + minute.astype(int) * 60).astype(
        np.int32
    )
    df["TimeOfDay"] = df["TimeText"].astype(str) + ":00"

    int_cols = [
        "TimeKey", "Hour", "Minute",
        "TimeKey15", "TimeKey30", "TimeKey60",
        "TimeKey360", "TimeKey720", "TimeBucketKey4",
    ]
    for c in int_cols:
        if c in df.columns:
            df[c] = df[c].astype(np.int32)

    return df


# =====================================================================
# Output helpers
# =====================================================================

def _write_csv(df: pd.DataFrame, path: Path) -> Path:
    out = path / "time.csv"
    df.to_csv(out, index=False)
    return out


def _write_parquet(df: pd.DataFrame, path: Path) -> Path:
    out = path / "time.parquet"
    try:
        import pyarrow.parquet as pq
        import pyarrow as pa

        table = pa.Table.from_pandas(df, preserve_index=False)
        pq.write_table(table, out, compression="snappy")
    except ImportError:
        df.to_parquet(out, index=False, engine="auto")
    return out


# =====================================================================
# --list-columns
# =====================================================================

_BASE_COLS = [
    "TimeKey", "Hour", "Minute", "TimeText",
    "TimeKey15", "TimeKey30", "TimeKey60",
    "TimeKey360", "TimeKey720",
    "TimeBucketKey4", "TimeBucket4",
    "TimeSeconds", "TimeOfDay",
]

_LABEL_COLS = [
    "Bin15Label", "Bin30Label", "Bin60Label",
    "Bin6hLabel", "Bin12hLabel",
]


def _print_columns() -> None:
    sections = [
        ("Base (always included)", _BASE_COLS),
        ("Bin labels (default on, --no-labels to skip)", _LABEL_COLS),
    ]
    for title, cols in sections:
        print(f"\n  {title}")
        print(f"  {'=' * len(title)}")
        for c in cols:
            print(f"    {c}")


# =====================================================================
# Configuration — edit these parameters, then run:  python generate_time_table.py
# =====================================================================

if __name__ == "__main__":

    # ── Column options ────────────────────────────────────────────────
    INCLUDE_LABELS = True           # human-readable bin labels (e.g. "13:30-13:45")

    # ── Output ────────────────────────────────────────────────────────
    OUTPUT_FORMAT = "csv"           # "csv" or "parquet"
    OUTPUT_DIR = "./output"

    # ==================================================================
    # Generation (no changes needed below this line)
    # ==================================================================

    out_dir = Path(OUTPUT_DIR)
    out_dir.mkdir(parents=True, exist_ok=True)

    print("Generating time table")
    df = generate_time_table(include_labels=INCLUDE_LABELS)
    writer = _write_parquet if OUTPUT_FORMAT == "parquet" else _write_csv
    out_path = writer(df, out_dir)
    print(f"  {len(df):,} rows x {len(df.columns)} columns -> {out_path}")
