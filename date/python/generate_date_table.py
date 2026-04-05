"""
Standalone Date Dimension Generator
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Generates an analytics-ready date dimension table (daily grain) for BI,
data warehousing, and analytics pipelines.

Requirements:  Python 3.9+, pandas, numpy, pyarrow (for parquet output)

Usage:
    Edit the parameters in the "Configuration" section at the bottom of
    this file, then run:

        python generate_date_table.py
"""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import numpy as np
import pandas as pd


# =====================================================================
# Constants
# =====================================================================

# Excel serial-date epoch: 1899-12-30 (intentional Lotus 1-2-3 bug).
_EXCEL_EPOCH = pd.Timestamp("1899-12-30")

# ISO week reference: Monday of ISO week 1 in year 2000.
_ISO_WEEK_REF = pd.Timestamp("2000-01-03")

# Calendar week reference: Sunday of calendar week 1 in year 2000.
_CAL_WEEK_REF = pd.Timestamp("2000-01-02")


def _format_week_date_range(start_dates: pd.Series, end_dates: pd.Series) -> pd.Series:
    """Format week date ranges as ``'Mon DD - Mon DD, YYYY'``."""
    return start_dates.dt.strftime("%b %d") + " - " + end_dates.dt.strftime("%b %d, %Y")


# =====================================================================
# Configuration dataclass
# =====================================================================

@dataclass(frozen=True)
class WeeklyFiscalConfig:
    """Weekly fiscal (4-4-5 / 4-5-4 / 5-4-4) calendar settings."""
    enabled: bool = False
    first_day_of_week: int = 0        # 0=Sun, 1=Mon, ... 6=Sat
    weekly_type: str = "Last"         # "Last" or "Nearest"
    quarter_week_type: str = "445"    # "445", "454", "544"
    type_start_fiscal_year: int = 1   # 0=start-year labeling, 1=end-year


# =====================================================================
# Helpers
# =====================================================================

def _clamp_month(m: int) -> int:
    return max(1, min(12, int(m)))


def _safe_parse_as_of(as_of_date, fallback: pd.Timestamp) -> pd.Timestamp:
    if not as_of_date:
        return fallback
    ts = pd.to_datetime(as_of_date).normalize()
    if pd.isna(ts):
        raise ValueError(f"as_of_date={as_of_date!r} parsed to NaT.")
    return ts


# =====================================================================
# Calendar columns (base + as-of offsets)
# =====================================================================

def _add_calendar_columns(df: pd.DataFrame, *, as_of: pd.Timestamp) -> pd.DataFrame:
    year = df["Date"].dt.year
    month = df["Date"].dt.month
    day = df["Date"].dt.day

    df["DateKey"] = (year * 10000 + month * 100 + day).astype(np.int64)
    df["DateSerialNumber"] = (df["Date"] - _EXCEL_EPOCH).dt.days.astype(np.int32)

    df["Year"] = year.astype(np.int32)
    df["Month"] = month.astype(np.int32)
    df["Day"] = day.astype(np.int32)
    df["Quarter"] = df["Date"].dt.quarter.astype(np.int32)

    df["MonthName"] = df["Date"].dt.strftime("%B")
    df["MonthShort"] = df["Date"].dt.strftime("%b")
    df["DayName"] = df["Date"].dt.strftime("%A")
    df["DayShort"] = df["Date"].dt.strftime("%a")
    df["DayOfYear"] = df["Date"].dt.dayofyear.astype(np.int32)

    df["MonthYear"] = df["Date"].dt.strftime("%b %Y")
    df["MonthYearKey"] = (df["Year"].astype(int) * 100 + df["Month"].astype(int)).astype(np.int32)

    df["YearQuarterKey"] = (df["Year"].astype(int) * 10 + df["Quarter"].astype(int)).astype(np.int32)
    df["QuarterYear"] = "Q" + df["Quarter"].astype(str) + " " + df["Year"].astype(str)

    df["CalendarMonthIndex"] = (df["Year"].astype(int) * 12 + df["Month"].astype(int)).astype(np.int32)
    df["CalendarQuarterIndex"] = (df["Year"].astype(int) * 4 + df["Quarter"].astype(int)).astype(np.int32)

    # DayOfWeek: 0=Sunday, 1=Monday, ... 6=Saturday
    weekday = df["Date"].dt.weekday  # 0=Mon..6=Sun
    df["DayOfWeek"] = ((weekday + 1) % 7).astype(np.int32)

    df["IsWeekend"] = df["DayOfWeek"].isin([0, 6]).astype(bool)
    df["IsBusinessDay"] = (~df["IsWeekend"]).astype(bool)

    df["MonthStartDate"] = df["Date"].dt.to_period("M").dt.start_time.dt.normalize()
    df["MonthEndDate"] = df["Date"].dt.to_period("M").dt.end_time.dt.normalize()

    qperiod = df["Date"].dt.to_period("Q")
    df["QuarterStartDate"] = qperiod.dt.start_time.dt.normalize()
    df["QuarterEndDate"] = qperiod.dt.end_time.dt.normalize()

    df["IsMonthStart"] = (df["Day"] == 1).astype(bool)
    df["IsMonthEnd"] = df["Date"].dt.is_month_end.astype(bool)
    df["IsQuarterStart"] = df["Date"].dt.is_quarter_start.astype(bool)
    df["IsQuarterEnd"] = df["Date"].dt.is_quarter_end.astype(bool)
    df["IsYearStart"] = ((df["Month"] == 1) & (df["Day"] == 1)).astype(bool)
    df["IsYearEnd"] = ((df["Month"] == 12) & (df["Day"] == 31)).astype(bool)

    df["WeekOfMonth"] = ((df["Day"] - 1) // 7 + 1).astype(np.int32)

    # Calendar week (Sunday-based)
    df["CalendarWeekStartDate"] = (df["Date"] - pd.to_timedelta(df["DayOfWeek"], unit="D")).dt.normalize()
    df["CalendarWeekEndDate"] = (df["CalendarWeekStartDate"] + pd.Timedelta(days=6)).dt.normalize()

    unique_years = df["Year"].unique()
    jan1_timestamps = pd.to_datetime(unique_years.astype(str) + "-01-01")
    jan1_sun0 = ((jan1_timestamps.weekday + 1) % 7).astype(int)
    year_to_jan1_sun0 = pd.Series(jan1_sun0, index=unique_years)
    jan1_mapped = df["Year"].map(year_to_jan1_sun0)
    df["CalendarWeekNumber"] = ((df["DayOfYear"].astype(int) + jan1_mapped - 1) // 7 + 1).astype(np.int32)

    df["CalendarWeekIndex"] = (((df["CalendarWeekStartDate"] - _CAL_WEEK_REF).dt.days) // 7).astype(np.int32)
    as_of_cal_week_start = (as_of - pd.Timedelta(days=int((as_of.weekday() + 1) % 7))).normalize()
    as_of_cal_week_index = int(((as_of_cal_week_start - _CAL_WEEK_REF).days) // 7)
    df["CalendarWeekOffset"] = (df["CalendarWeekIndex"].astype(int) - as_of_cal_week_index).astype(np.int32)

    df["CalendarWeekDateRange"] = _format_week_date_range(
        df["CalendarWeekStartDate"], df["CalendarWeekEndDate"],
    )

    # Next/Previous Business Day (strict: excludes the current date)
    biz_dates = df.loc[df["IsBusinessDay"] == 1, "Date"].to_numpy(dtype="datetime64[D]")
    date_vals = df["Date"].to_numpy(dtype="datetime64[D]")

    if biz_dates.size > 0:
        idx_next = np.searchsorted(biz_dates, date_vals, side="right")
        idx_prev = np.searchsorted(biz_dates, date_vals, side="left") - 1

        next_bd = date_vals.copy()
        prev_bd = date_vals.copy()

        ok_next = idx_next < biz_dates.size
        ok_prev = idx_prev >= 0

        next_bd[ok_next] = biz_dates[idx_next[ok_next]]
        prev_bd[ok_prev] = biz_dates[idx_prev[ok_prev]]

        df["NextBusinessDay"] = pd.to_datetime(next_bd).normalize()
        df["PreviousBusinessDay"] = pd.to_datetime(prev_bd).normalize()
    else:
        df["NextBusinessDay"] = df["Date"]
        df["PreviousBusinessDay"] = df["Date"]

    # As-of relative columns
    df["IsToday"] = (df["Date"] == as_of).astype(bool)
    df["IsCurrentYear"] = (df["Year"] == as_of.year).astype(bool)
    df["IsCurrentMonth"] = ((df["Year"] == as_of.year) & (df["Month"] == as_of.month)).astype(bool)
    current_quarter = (as_of.month - 1) // 3 + 1
    df["IsCurrentQuarter"] = ((df["Year"] == as_of.year) & (df["Quarter"] == current_quarter)).astype(bool)
    df["CurrentDayOffset"] = (df["Date"] - as_of).dt.days.astype(np.int32)

    df["YearOffset"] = (df["Year"].astype(int) - int(as_of.year)).astype(np.int32)
    as_of_cal_month_index = int(as_of.year) * 12 + int(as_of.month)
    as_of_cal_quarter_index = int(as_of.year) * 4 + int((as_of.month - 1) // 3 + 1)
    df["CalendarMonthOffset"] = (df["CalendarMonthIndex"].astype(int) - as_of_cal_month_index).astype(np.int32)
    df["CalendarQuarterOffset"] = (df["CalendarQuarterIndex"].astype(int) - as_of_cal_quarter_index).astype(np.int32)

    return df


# =====================================================================
# ISO week columns
# =====================================================================

def _add_iso_columns(df: pd.DataFrame, *, as_of: pd.Timestamp) -> pd.DataFrame:
    iso = df["Date"].dt.isocalendar()
    df["ISOWeekNumber"] = iso.week.astype(np.int32)
    df["ISOYear"] = iso.year.astype(np.int32)

    df["ISOWeekStartDate"] = (df["Date"] - pd.to_timedelta(df["Date"].dt.weekday, unit="D")).dt.normalize()
    df["ISOWeekEndDate"] = (df["ISOWeekStartDate"] + pd.Timedelta(days=6)).dt.normalize()

    df["ISOYearWeekIndex"] = (((df["ISOWeekStartDate"] - _ISO_WEEK_REF).dt.days) // 7).astype(np.int32)
    as_of_week_start = (as_of - pd.Timedelta(days=int(as_of.weekday()))).normalize()
    as_of_iso_year_week_index = int(((as_of_week_start - _ISO_WEEK_REF).days) // 7)
    df["ISOWeekOffset"] = (df["ISOYearWeekIndex"].astype(int) - as_of_iso_year_week_index).astype(np.int32)

    df["ISOWeekDateRange"] = _format_week_date_range(
        df["ISOWeekStartDate"], df["ISOWeekEndDate"],
    )

    return df


# =====================================================================
# Monthly fiscal columns
# =====================================================================

def _add_fiscal_columns(
    df: pd.DataFrame,
    *,
    fiscal_start_month: int,
    as_of: pd.Timestamp,
) -> pd.DataFrame:
    fy_start_month = _clamp_month(fiscal_start_month)

    df["FiscalYearStartYear"] = np.where(
        df["Month"] >= fy_start_month, df["Year"], df["Year"] - 1
    ).astype(np.int32)
    df["FiscalMonthNumber"] = (
        ((df["Month"].astype(int) - fy_start_month + 12) % 12) + 1
    ).astype(np.int32)
    df["FiscalQuarterNumber"] = (
        ((df["FiscalMonthNumber"] - 1) // 3) + 1
    ).astype(np.int32)

    fy_end_add = 0 if fy_start_month == 1 else 1
    fiscal_year_end = (df["FiscalYearStartYear"].astype(int) + fy_end_add).astype(np.int32)

    if fy_start_month == 1:
        df["FiscalYearRange"] = df["FiscalYearStartYear"].astype(str)
    else:
        df["FiscalYearRange"] = (
            df["FiscalYearStartYear"].astype(str) + "-" + fiscal_year_end.astype(str)
        )
    df["FiscalQuarterLabel"] = (
        "Q" + df["FiscalQuarterNumber"].astype(str) + " FY" + fiscal_year_end.astype(str)
    )
    df["FiscalMonthName"] = df["Date"].dt.strftime("%B")
    df["FiscalMonthShort"] = df["Date"].dt.strftime("%b")

    df["FiscalMonthIndex"] = (
        df["FiscalYearStartYear"].astype(int) * 12 + df["FiscalMonthNumber"].astype(int)
    ).astype(np.int32)
    df["FiscalQuarterIndex"] = (
        df["FiscalYearStartYear"].astype(int) * 4 + df["FiscalQuarterNumber"].astype(int)
    ).astype(np.int32)

    # Fiscal year start/end dates
    fy_start_years = df["FiscalYearStartYear"].astype(int).to_numpy()
    fy_start_months = np.full(len(df), fy_start_month, dtype=np.int32)
    fy_start_days = np.ones(len(df), dtype=np.int32)
    df["FiscalYearStartDate"] = pd.to_datetime(
        pd.DataFrame({"year": fy_start_years, "month": fy_start_months, "day": fy_start_days})
    ).dt.normalize()
    df["FiscalYearEndDate"] = (
        df["FiscalYearStartDate"] + pd.DateOffset(years=1) - pd.Timedelta(days=1)
    ).dt.normalize()

    # Fiscal quarter start/end dates
    fq_shift = (df["FiscalQuarterNumber"].astype(int) - 1) * 3
    fq_raw_month = df["FiscalYearStartDate"].dt.month + fq_shift
    fq_year = df["FiscalYearStartDate"].dt.year + ((fq_raw_month - 1) // 12)
    fq_month = (fq_raw_month - 1) % 12 + 1
    df["FiscalQuarterStartDate"] = pd.to_datetime(
        pd.DataFrame({"year": fq_year, "month": fq_month, "day": np.ones(len(df), dtype=np.int32)})
    ).dt.normalize()
    df["FiscalQuarterEndDate"] = (
        df["FiscalQuarterStartDate"] + pd.DateOffset(months=3) - pd.Timedelta(days=1)
    ).dt.normalize()

    df["IsFiscalYearStart"] = (df["Date"] == df["FiscalYearStartDate"]).astype(bool)
    df["IsFiscalYearEnd"] = (df["Date"] == df["FiscalYearEndDate"]).astype(bool)
    df["IsFiscalQuarterStart"] = (df["Date"] == df["FiscalQuarterStartDate"]).astype(bool)
    df["IsFiscalQuarterEnd"] = (df["Date"] == df["FiscalQuarterEndDate"]).astype(bool)

    df["FiscalYear"] = fiscal_year_end.astype(np.int32)
    df["FiscalYearLabel"] = "FY " + df["FiscalYear"].astype(str)

    # Fiscal offsets relative to as_of
    asof_mask = df["Date"] == as_of
    asof_idx = df.index[asof_mask]

    if len(asof_idx) > 0:
        _asof = df.loc[asof_idx[0]]
        as_of_fiscal_month_index = int(_asof["FiscalMonthIndex"])
        as_of_fiscal_quarter_index = int(_asof["FiscalQuarterIndex"])
        df["FiscalMonthOffset"] = (
            df["FiscalMonthIndex"].astype(int) - as_of_fiscal_month_index
        ).astype(np.int32)
        df["FiscalQuarterOffset"] = (
            df["FiscalQuarterIndex"].astype(int) - as_of_fiscal_quarter_index
        ).astype(np.int32)
    else:
        df["FiscalMonthOffset"] = np.int32(0)
        df["FiscalQuarterOffset"] = np.int32(0)

    return df


# =====================================================================
# Weekly fiscal (4-4-5) columns
# =====================================================================

def _weekday_num(date: pd.Timestamp, first_day_of_week: int) -> int:
    sun0 = (date.weekday() + 1) % 7
    pos0 = (sun0 - first_day_of_week) % 7
    return int(pos0 + 1)


def _weekly_fiscal_year_bounds(
    fw_year_number: int,
    first_fiscal_month: int,
    first_day_of_week: int,
    weekly_type: str,
    type_start_fiscal_year: int,
) -> Tuple[pd.Timestamp, pd.Timestamp]:
    first_fiscal_month = _clamp_month(first_fiscal_month)
    first_day_of_week = int(first_day_of_week) % 7
    weekly_type = str(weekly_type or "Last").strip().title()
    if weekly_type not in {"Last", "Nearest"}:
        weekly_type = "Last"

    type_start_fiscal_year = 1 if int(type_start_fiscal_year) != 0 else 0
    offset_fiscal_year = 1 if first_fiscal_month > 1 else 0

    start_fy_calendar_year = int(fw_year_number) - (
        offset_fiscal_year * type_start_fiscal_year
    )

    first_day_current = pd.Timestamp(start_fy_calendar_year, first_fiscal_month, 1)
    first_day_next = pd.Timestamp(start_fy_calendar_year + 1, first_fiscal_month, 1)

    dow_cur = _weekday_num(first_day_current, first_day_of_week)
    dow_next = _weekday_num(first_day_next, first_day_of_week)

    if weekly_type == "Last":
        offset_start_current = 1 - dow_cur
        offset_start_next = 1 - dow_next
    else:
        offset_start_current = (8 - dow_cur) if dow_cur >= 5 else (1 - dow_cur)
        offset_start_next = (8 - dow_next) if dow_next >= 5 else (1 - dow_next)

    start_of_year = (
        first_day_current + pd.Timedelta(days=int(offset_start_current))
    ).normalize()
    next_year_start = (
        first_day_next + pd.Timedelta(days=int(offset_start_next))
    ).normalize()
    end_of_year = next_year_start - pd.Timedelta(days=1)
    return start_of_year, end_of_year


def _weeks_in_periods(quarter_week_type: str) -> Tuple[int, int, int]:
    qwt = str(quarter_week_type or "445").strip()
    if qwt not in {"445", "454", "544"}:
        qwt = "445"
    if qwt == "445":
        return (4, 4, 5)
    if qwt == "454":
        return (4, 5, 4)
    return (5, 4, 4)


def _add_weekly_fiscal_columns(
    df: pd.DataFrame,
    *,
    first_fiscal_month: int,
    cfg: WeeklyFiscalConfig,
    as_of: pd.Timestamp,
) -> pd.DataFrame:
    if not cfg.enabled:
        return df

    first_fiscal_month = _clamp_month(first_fiscal_month)

    fdow = int(cfg.first_day_of_week) % 7
    weekly_type = str(cfg.weekly_type or "Last").strip().title()
    qwt = str(cfg.quarter_week_type or "445").strip()
    tsy = 1 if int(cfg.type_start_fiscal_year) != 0 else 0

    w1, w2, _w3 = _weeks_in_periods(qwt)

    start_year = int(df["Date"].dt.year.min())
    end_year = int(df["Date"].dt.year.max())
    year_span = range(start_year - 1, end_year + 2)

    bounds: Dict[int, Tuple[pd.Timestamp, pd.Timestamp]] = {}
    for y in year_span:
        s, e = _weekly_fiscal_year_bounds(y, first_fiscal_month, fdow, weekly_type, tsy)
        bounds[int(y)] = (s, e)

    # Assign FWYearNumber (vectorized)
    fw_year = np.full(len(df), -1, dtype=np.int32)
    dates = df["Date"].to_numpy(dtype="datetime64[D]")

    years_sorted = np.array(sorted(bounds.keys()), dtype=np.int32)
    starts = np.array(
        [bounds[int(y)][0].to_datetime64() for y in years_sorted],
        dtype="datetime64[D]",
    )
    ends = np.array(
        [bounds[int(y)][1].to_datetime64() for y in years_sorted],
        dtype="datetime64[D]",
    )
    pos = np.searchsorted(starts, dates, side="right") - 1
    pos_clip = np.clip(pos, 0, len(ends) - 1)
    ok = (pos >= 0) & (dates <= ends[pos_clip])
    fw_year[ok] = years_sorted[pos[ok]]

    # Fallback for dates outside all computed weekly-fiscal year boundaries
    n_fallback = int((fw_year < 0).sum())
    if n_fallback:
        print(
            f"  Warning: {n_fallback} date(s) outside weekly fiscal boundaries, "
            "using month-based fallback"
        )
        fy_start_year = np.where(
            df["Month"] >= first_fiscal_month, df["Year"], df["Year"] - 1
        ).astype(int)
        fy_end_add = 0 if first_fiscal_month == 1 else 1
        fy_end_year = (fy_start_year + fy_end_add).astype(int)
        fw_year = np.where(fw_year < 0, fy_end_year, fw_year).astype(np.int32)

    fw_year_s = pd.Series(fw_year.astype(np.int32), index=df.index, name="FWYearNumber")
    fw_year_label = "FY " + fw_year_s.astype(str)

    start_map = {y: se[0] for y, se in bounds.items()}
    end_map = {y: se[1] for y, se in bounds.items()}
    fw_start_year = fw_year_s.map(start_map).astype("datetime64[ns]")
    fw_end_year = fw_year_s.map(end_map).astype("datetime64[ns]")

    fw_day_of_year = (df["Date"] - fw_start_year).dt.days.add(1).astype(np.int32)
    fw_week = ((fw_day_of_year.astype(int) - 1) // 7 + 1).astype(np.int32)

    week = fw_week.astype(int).to_numpy()
    fw_period = np.where(week > 52, 13, (week + 3) // 4).astype(np.int32)
    fw_quarter = np.where(week > 52, 4, (week + 12) // 13).astype(np.int32)

    fw_quarter_s = pd.Series(fw_quarter, index=df.index, name="FWQuarterNumber")
    week_in_q = np.where(
        week > 52, 14, week - 13 * (fw_quarter_s.astype(int).to_numpy() - 1)
    ).astype(int)
    fw_week_in_quarter = pd.Series(
        week_in_q.astype(np.int32), index=df.index, name="FWWeekInQuarterNumber"
    )

    m_in_q = np.select(
        [week_in_q <= w1, week_in_q <= (w1 + w2)],
        [1, 2],
        default=3,
    ).astype(np.int32)
    fw_month = ((fw_quarter_s.astype(int) - 1) * 3 + m_in_q).astype(np.int32)
    fw_month_s = pd.Series(fw_month, index=df.index, name="FWMonthNumber")

    fw_year_quarter = (
        fw_year_s.astype(int) * 4 - 1 + fw_quarter_s.astype(int)
    ).astype(np.int32)
    fw_year_month = (
        fw_year_s.astype(int) * 12 - 1 + fw_month_s.astype(int)
    ).astype(np.int32)

    # Weekday number relative to first day of week (1..7)
    sun0 = (df["Date"].dt.weekday + 1) % 7
    pos0 = (sun0 - fdow) % 7
    week_day_num = (pos0 + 1).astype(np.int32)
    week_day_name_short = df["Date"].dt.strftime("%a")

    fw_start_week = (
        df["Date"] - pd.to_timedelta(week_day_num - 1, unit="D")
    ).dt.normalize()
    fw_end_week = (fw_start_week + pd.to_timedelta(6, unit="D")).dt.normalize()

    # Working day (Mon-Fri)
    is_work = df["Date"].dt.weekday.isin([0, 1, 2, 3, 4])
    is_working_day = is_work.astype(bool)
    day_type = np.where(is_work, "Working Day", "Non-Working Day")

    # Boundaries within weekly fiscal month/quarter
    tmp = pd.DataFrame(
        {
            "Date": df["Date"],
            "FWMonthIndex": fw_year_month,
            "FWQuarterIndex": fw_year_quarter,
        },
        index=df.index,
    )
    fw_start_month = tmp.groupby("FWMonthIndex")["Date"].transform("min")
    fw_end_month = tmp.groupby("FWMonthIndex")["Date"].transform("max")
    fw_day_of_month = (df["Date"] - fw_start_month).dt.days.add(1).astype(np.int32)

    fw_start_quarter = tmp.groupby("FWQuarterIndex")["Date"].transform("min")
    fw_end_quarter = tmp.groupby("FWQuarterIndex")["Date"].transform("max")
    fw_day_of_quarter = (df["Date"] - fw_start_quarter).dt.days.add(1).astype(np.int32)

    # Global increasing week index
    first_week_reference = pd.Timestamp("1900-12-30") + pd.Timedelta(days=fdow)
    fw_year_week = (
        ((df["Date"] - first_week_reference).dt.days) // 7 + 1
    ).astype(np.int32)

    # Labels
    y = fw_year_s.astype(str)
    fw_quarter_label = "FQ" + fw_quarter_s.astype(str) + " - " + y
    fw_week_label = "FW" + fw_week.astype(str).str.zfill(2) + " - " + y
    fw_week_date_range = _format_week_date_range(fw_start_week, fw_end_week)
    fw_period_label = (
        "P"
        + pd.Series(fw_period, index=df.index).astype(str).str.zfill(2)
        + " - "
        + y
    )
    fw_month_label = (
        "FM " + (fw_start_month + pd.Timedelta(days=14)).dt.strftime("%b") + " - " + y
    )
    fw_year_month_label = (
        "FM " + (fw_start_month + pd.Timedelta(days=14)).dt.strftime("%b %Y")
    )

    new_cols = pd.DataFrame(
        {
            "FWYearNumber": fw_year_s,
            "FWYearLabel": fw_year_label,
            "FWStartOfYear": fw_start_year,
            "FWEndOfYear": fw_end_year,
            "FWDayOfYear": fw_day_of_year,
            "FWWeekNumber": fw_week,
            "FWPeriodNumber": pd.Series(fw_period, index=df.index).astype(np.int32),
            "FWQuarterNumber": fw_quarter_s.astype(np.int32),
            "FWWeekInQuarterNumber": fw_week_in_quarter,
            "FWMonthNumber": fw_month_s.astype(np.int32),
            "FWQuarterIndex": fw_year_quarter,
            "FWMonthIndex": fw_year_month,
            "FWWeekDayNumber": week_day_num,
            "FWWeekDayNameShort": week_day_name_short,
            "FWStartOfWeek": fw_start_week,
            "FWEndOfWeek": fw_end_week,
            "FWIsWorkingDay": is_working_day,
            "FWDayType": day_type,
            "FWStartOfMonth": fw_start_month,
            "FWEndOfMonth": fw_end_month,
            "FWDayOfMonth": fw_day_of_month,
            "FWStartOfQuarter": fw_start_quarter,
            "FWEndOfQuarter": fw_end_quarter,
            "FWDayOfQuarter": fw_day_of_quarter,
            "FWWeekIndex": fw_year_week,
            "FWQuarterLabel": fw_quarter_label,
            "FWWeekLabel": fw_week_label,
            "FWWeekDateRange": fw_week_date_range,
            "FWPeriodLabel": fw_period_label,
            "FWMonthLabel": fw_month_label,
            "FWYearMonthLabel": fw_year_month_label,
        },
        index=df.index,
    )

    df = pd.concat([df, new_cols], axis=1)

    # Weekly fiscal offsets relative to as_of
    asof_mask = df["Date"] == as_of
    asof_idx = df.index[asof_mask]

    if len(asof_idx) > 0:
        _asof = df.loc[asof_idx[0]]
        as_of_fw_year_week_index = int(_asof["FWWeekIndex"])
        as_of_fw_year_month_index = int(_asof["FWMonthIndex"])
        as_of_fw_year_quarter_index = int(_asof["FWQuarterIndex"])

        df = df.assign(
            FWWeekOffset=(
                df["FWWeekIndex"].astype(int) - as_of_fw_year_week_index
            ).astype(np.int32),
            FWMonthOffset=(
                df["FWMonthIndex"].astype(int) - as_of_fw_year_month_index
            ).astype(np.int32),
            FWQuarterOffset=(
                df["FWQuarterIndex"].astype(int) - as_of_fw_year_quarter_index
            ).astype(np.int32),
        )
    else:
        df = df.assign(
            FWWeekOffset=np.int32(0),
            FWMonthOffset=np.int32(0),
            FWQuarterOffset=np.int32(0),
        )

    return df


# =====================================================================
# Column selector
# =====================================================================

_BASE_COLS = [
    "Date", "DateKey", "DateSerialNumber",
    "Year",
    "Quarter", "QuarterStartDate", "QuarterEndDate", "QuarterYear",
    "Month", "MonthName", "MonthShort",
    "MonthStartDate", "MonthEndDate",
    "MonthYear", "MonthYearKey",
    "YearQuarterKey",
    "CalendarMonthIndex", "CalendarQuarterIndex",
    "WeekOfMonth",
    "CalendarWeekNumber", "CalendarWeekStartDate", "CalendarWeekEndDate",
    "CalendarWeekDateRange", "CalendarWeekIndex", "CalendarWeekOffset",
    "Day", "DayName", "DayShort", "DayOfYear", "DayOfWeek",
    "IsWeekend", "IsBusinessDay",
    "NextBusinessDay", "PreviousBusinessDay",
]

_CALENDAR_COLS = [
    "IsYearStart", "IsYearEnd",
    "IsQuarterStart", "IsQuarterEnd",
    "IsMonthStart", "IsMonthEnd",
    "IsToday", "IsCurrentYear", "IsCurrentMonth", "IsCurrentQuarter",
    "CurrentDayOffset", "YearOffset", "CalendarMonthOffset", "CalendarQuarterOffset",
]

_ISO_COLS = [
    "ISOWeekNumber", "ISOYear", "ISOYearWeekIndex", "ISOWeekOffset",
    "ISOWeekStartDate", "ISOWeekEndDate", "ISOWeekDateRange",
]

_FISCAL_COLS = [
    "FiscalYearStartYear", "FiscalMonthNumber", "FiscalQuarterNumber",
    "FiscalMonthIndex", "FiscalQuarterIndex", "FiscalMonthOffset", "FiscalQuarterOffset",
    "FiscalQuarterLabel", "FiscalMonthName", "FiscalMonthShort", "FiscalYearRange",
    "FiscalYearStartDate", "FiscalYearEndDate",
    "FiscalQuarterStartDate", "FiscalQuarterEndDate",
    "IsFiscalYearStart", "IsFiscalYearEnd",
    "IsFiscalQuarterStart", "IsFiscalQuarterEnd",
    "FiscalYear", "FiscalYearLabel",
]

_WEEKLY_FISCAL_COLS = [
    "FWYearNumber", "FWYearLabel",
    "FWQuarterNumber", "FWQuarterLabel",
    "FWQuarterIndex", "FWQuarterOffset",
    "FWMonthNumber", "FWMonthLabel",
    "FWMonthIndex", "FWMonthOffset",
    "FWWeekNumber", "FWWeekLabel", "FWWeekDateRange",
    "FWWeekIndex", "FWWeekOffset",
    "FWPeriodNumber", "FWPeriodLabel",
    "FWStartOfYear", "FWEndOfYear",
    "FWStartOfQuarter", "FWEndOfQuarter",
    "FWStartOfMonth", "FWEndOfMonth",
    "FWStartOfWeek", "FWEndOfWeek",
    "FWWeekDayNumber", "FWWeekDayNameShort",
    "FWDayOfYear", "FWDayOfQuarter", "FWDayOfMonth",
    "FWIsWorkingDay", "FWDayType",
    "FWWeekInQuarterNumber", "FWYearMonthLabel",
    "WeeklyFiscalSystem",
]


def _resolve_columns(
    *,
    include_calendar: bool,
    include_iso: bool,
    include_fiscal: bool,
    include_weekly_fiscal: bool,
) -> List[str]:
    cols = list(_BASE_COLS)
    if include_calendar:
        cols += _CALENDAR_COLS
    if include_iso:
        cols += _ISO_COLS
    if include_fiscal:
        cols += _FISCAL_COLS
    if include_weekly_fiscal:
        cols += _WEEKLY_FISCAL_COLS
    # Deduplicate preserving order
    seen: set = set()
    out: List[str] = []
    for c in cols:
        if c not in seen:
            seen.add(c)
            out.append(c)
    return out


# =====================================================================
# Main generation function
# =====================================================================

def generate_date_table(
    start_date: str,
    end_date: str,
    fiscal_start_month: int = 1,
    *,
    as_of_date: Optional[str] = None,
    include_calendar: bool = True,
    include_iso: bool = False,
    include_fiscal: bool = True,
    weekly_fiscal_cfg: Optional[WeeklyFiscalConfig] = None,
) -> pd.DataFrame:
    """Generate a daily-grain date dimension table.

    Parameters
    ----------
    start_date : str
        Start of date range (ISO format, e.g. "2020-01-01").
    end_date : str
        End of date range (inclusive).
    fiscal_start_month : int
        Month the fiscal year begins (1-12).  1 = calendar year.
    as_of_date : str, optional
        Reference date for relative columns (IsToday, offsets).
        Defaults to *end_date*.
    include_calendar : bool
        Include as-of relative flags and offsets (default True).
    include_iso : bool
        Include ISO-8601 week columns (default False).
    include_fiscal : bool
        Include monthly fiscal columns (default True).
    weekly_fiscal_cfg : WeeklyFiscalConfig, optional
        Weekly fiscal (4-4-5) settings.  Pass an instance with
        ``enabled=True`` to activate.
    """
    start_ts = pd.to_datetime(start_date).normalize()
    end_ts = pd.to_datetime(end_date).normalize()
    if end_ts < start_ts:
        raise ValueError(
            f"end_date ({end_ts.date()}) must be >= start_date ({start_ts.date()})"
        )

    dates = pd.date_range(start_ts, end_ts, freq="D")
    df = pd.DataFrame({"Date": dates})

    as_of = _safe_parse_as_of(as_of_date, fallback=end_ts)
    if as_of < start_ts:
        print(f"  Warning: as_of_date {as_of.date()} before start, clamping to {start_ts.date()}")
        as_of = start_ts
    elif as_of > end_ts:
        print(f"  Warning: as_of_date {as_of.date()} after end, clamping to {end_ts.date()}")
        as_of = end_ts

    fy_start_month = _clamp_month(fiscal_start_month)
    wf_cfg = weekly_fiscal_cfg or WeeklyFiscalConfig()

    # Always run all enrichment functions; column selection trims the output.
    df = _add_calendar_columns(df, as_of=as_of)
    if include_iso:
        df = _add_iso_columns(df, as_of=as_of)
    if include_fiscal:
        df = _add_fiscal_columns(df, fiscal_start_month=fy_start_month, as_of=as_of)
    if wf_cfg.enabled:
        df = _add_weekly_fiscal_columns(
            df, first_fiscal_month=fy_start_month, cfg=wf_cfg, as_of=as_of
        )

    # Weekly fiscal system label (visible config sanity check)
    if wf_cfg.enabled:
        df["WeeklyFiscalSystem"] = (
            f"Weekly ({wf_cfg.quarter_week_type} "
            f"{str(wf_cfg.weekly_type).strip().title()})"
        )

    # Select and order columns
    target_cols = _resolve_columns(
        include_calendar=include_calendar,
        include_iso=include_iso,
        include_fiscal=include_fiscal,
        include_weekly_fiscal=wf_cfg.enabled,
    )
    available = [c for c in target_cols if c in df.columns]
    return df[available].copy()


# =====================================================================
# Output helpers
# =====================================================================

def _write_csv(df: pd.DataFrame, path: Path, name: str) -> Path:
    out = path / f"{name}.csv"
    df.to_csv(out, index=False)
    return out


def _write_parquet(df: pd.DataFrame, path: Path, name: str) -> Path:
    out = path / f"{name}.parquet"
    # Downcast date columns to date32 for smaller file size
    table = None
    try:
        import pyarrow as pa

        schema_overrides = {}
        for col in df.columns:
            if pd.api.types.is_datetime64_any_dtype(df[col]):
                schema_overrides[col] = pa.date32()

        table = pa.Table.from_pandas(df, preserve_index=False)
        if schema_overrides:
            new_fields = []
            for field in table.schema:
                if field.name in schema_overrides:
                    new_fields.append(pa.field(field.name, schema_overrides[field.name]))
                else:
                    new_fields.append(field)
            new_schema = pa.schema(new_fields)
            cols = []
            for field in new_schema:
                col = table.column(field.name)
                if field.name in schema_overrides:
                    col = col.cast(schema_overrides[field.name])
                cols.append(col)
            table = pa.table(
                {f.name: c for f, c in zip(new_schema, cols)}, schema=new_schema
            )

        import pyarrow.parquet as pq

        pq.write_table(table, out, compression="snappy")
    except ImportError:
        df.to_parquet(out, index=False, engine="auto")
    return out


# =====================================================================
# --list-columns
# =====================================================================

def _print_columns() -> None:
    sections = [
        ("Base (always included)", _BASE_COLS),
        ("Calendar (--calendar, default on)", _CALENDAR_COLS),
        ("ISO weeks (--iso)", _ISO_COLS),
        ("Fiscal (--fiscal, default on)", _FISCAL_COLS),
        ("Weekly Fiscal 4-4-5 (--weekly-fiscal)", _WEEKLY_FISCAL_COLS),
    ]
    for title, cols in sections:
        print(f"\n  {title}")
        print(f"  {'=' * len(title)}")
        for c in cols:
            print(f"    {c}")


# =====================================================================
# Configuration — edit these parameters, then run:  python generate_date_table.py
# =====================================================================

if __name__ == "__main__":

    # ── Date range ────────────────────────────────────────────────────
    START_DATE = "2020-01-01"
    END_DATE = "2025-12-31"

    # ── Reference date for relative columns (IsToday, offsets) ────────
    # Set to None to default to END_DATE.
    AS_OF_DATE = None

    # ── Fiscal year ───────────────────────────────────────────────────
    FISCAL_START_MONTH = 1          # 1-12  (1 = calendar year)

    # ── Column groups to include ──────────────────────────────────────
    INCLUDE_CALENDAR = True         # as-of relative flags & offsets
    INCLUDE_ISO = False             # ISO-8601 week columns
    INCLUDE_FISCAL = True           # monthly fiscal columns

    # ── Weekly fiscal (4-4-5) settings ────────────────────────────────
    ENABLE_WEEKLY_FISCAL = False
    FIRST_DAY_OF_WEEK = 0          # 0=Sun, 1=Mon, ... 6=Sat
    WEEKLY_TYPE = "Last"            # "Last" or "Nearest"
    QUARTER_WEEK_TYPE = "445"       # "445", "454", or "544"
    FISCAL_YEAR_LABEL = "end"       # "end" or "start"

    # ── Output ────────────────────────────────────────────────────────
    OUTPUT_FORMAT = "parquet"           # "csv" or "parquet"
    OUTPUT_DIR = "./output"

    # ==================================================================
    # Generation (no changes needed below this line)
    # ==================================================================

    out_dir = Path(OUTPUT_DIR)
    out_dir.mkdir(parents=True, exist_ok=True)
    writer = _write_parquet if OUTPUT_FORMAT == "parquet" else _write_csv

    wf_cfg = WeeklyFiscalConfig(
        enabled=ENABLE_WEEKLY_FISCAL,
        first_day_of_week=FIRST_DAY_OF_WEEK,
        weekly_type=WEEKLY_TYPE,
        quarter_week_type=QUARTER_WEEK_TYPE,
        type_start_fiscal_year=0 if FISCAL_YEAR_LABEL == "start" else 1,
    )

    print(f"Generating date table: {START_DATE} to {END_DATE}")
    df = generate_date_table(
        start_date=START_DATE,
        end_date=END_DATE,
        fiscal_start_month=FISCAL_START_MONTH,
        as_of_date=AS_OF_DATE,
        include_calendar=INCLUDE_CALENDAR,
        include_iso=INCLUDE_ISO,
        include_fiscal=INCLUDE_FISCAL,
        weekly_fiscal_cfg=wf_cfg,
    )
    out_path = writer(df, out_dir, "dates")
    print(f"  {len(df):,} rows x {len(df.columns)} columns -> {out_path}")
