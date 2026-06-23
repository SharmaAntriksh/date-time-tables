"""
SQL-vs-Python parity tests for the date dimension.

Runs dbo.usp_DateTable against a SQL Server, generates the same range with the
standalone Python generator, and asserts the two implementations produce
identical weekly-fiscal (4-4-5) columns. This is what locks the two ports
together: a future change to either one that drifts will fail here.

Requires a reachable SQL Server with usp_DateTable already deployed. The
connection comes from the PARITY_CONN env var; if no server is reachable the
tests skip (so a plain `pytest` on a dev box without SQL Server is a no-op).

    PARITY_CONN="DRIVER={ODBC Driver 18 for SQL Server};SERVER=localhost;UID=sa;\
PWD=...;DATABASE=TestDB;Encrypt=yes;TrustServerCertificate=yes"
    pytest -q date/tests/test_parity.py
"""
from __future__ import annotations

import os
import pathlib
import sys

import pandas as pd
import pytest

# Import the standalone generator from ../python.
_PY_DIR = pathlib.Path(__file__).resolve().parents[1] / "python"
sys.path.insert(0, str(_PY_DIR))
from generate_date_table import generate_date_table, WeeklyFiscalConfig  # noqa: E402

pyodbc = pytest.importorskip("pyodbc")

_CONN_STR = os.environ.get(
    "PARITY_CONN",
    "DRIVER={ODBC Driver 18 for SQL Server};SERVER=localhost;UID=sa;"
    "PWD=Test@Passw0rd!;DATABASE=TestDB;Encrypt=yes;TrustServerCertificate=yes",
)

# Each config is run through both implementations with identical parameters.
# These cover the Last / January-start / Sunday-week family across all three
# quarter patterns, plus partial-period edges and a 53-week span. Additional
# coverage (Nearest type, non-January fiscal starts, other first-day-of-week)
# is worth adding once confirmed against a live server.
_CONFIGS = [
    dict(id="445-Last-Sun", start="2021-03-10", end="2024-12-31",
         asof="2024-12-31", fy=1, fdow=0, wtype="Last", qwt="445", tsy=1),
    dict(id="454-Last-Sun", start="2019-01-01", end="2027-12-31",
         asof="2024-06-30", fy=1, fdow=0, wtype="Last", qwt="454", tsy=1),
    dict(id="544-Last-Sun-53wk", start="2015-01-01", end="2030-12-31",
         asof="2025-01-01", fy=1, fdow=0, wtype="Last", qwt="544", tsy=1),
]

_DATE_COLS = [
    "FWStartOfMonth", "FWEndOfMonth", "FWStartOfQuarter", "FWEndOfQuarter",
    "FWStartOfYear", "FWEndOfYear", "FWStartOfWeek", "FWEndOfWeek",
]
_INT_COLS = [
    "FWYearNumber", "FWDayOfYear", "FWWeekNumber", "FWPeriodNumber",
    "FWQuarterNumber", "FWWeekInQuarterNumber", "FWMonthNumber",
    "FWQuarterIndex", "FWMonthIndex", "FWWeekDayNumber", "FWDayOfMonth",
    "FWDayOfQuarter", "FWWeekIndex", "FWMonthDays", "FWQuarterDays", "FWYearDays",
]
_LABEL_COLS = ["FWMonthLabel", "FWYearMonthLabel", "FWQuarterLabel"]


@pytest.fixture(scope="module")
def conn():
    try:
        c = pyodbc.connect(_CONN_STR, autocommit=True, timeout=10)
    except pyodbc.Error as exc:  # pragma: no cover - env dependent
        # On a dev box without SQL Server, skip. In CI, PARITY_REQUIRED=1 turns an
        # unreachable server into a hard failure so the parity check can't silently
        # no-op (a green build with the suite skipped would hide SQL/Python drift).
        if os.environ.get("PARITY_REQUIRED") == "1":
            pytest.fail(f"PARITY_REQUIRED=1 but no SQL Server reachable: {exc}")
        pytest.skip(f"No SQL Server reachable for parity test: {exc}")
    yield c
    c.close()


def _sql_df(conn, cfg) -> pd.DataFrame:
    cur = conn.cursor()
    cur.execute("IF OBJECT_ID('dbo.ParityTest') IS NOT NULL DROP TABLE dbo.ParityTest;")
    cur.execute(
        "EXEC dbo.usp_DateTable @StartDate=?, @EndDate=?, @AsOfDate=?, "
        "@FiscalStartMonth=?, @IncludeISO=1, @IncludeFiscal=1, @IncludeWeeklyFiscal=1, "
        "@FirstDayOfWeek=?, @WeeklyType=?, @QuarterWeekType=?, @TypeStartFiscalYear=?, "
        "@ColumnNamingStyle='PascalCase', @OutputTable='dbo.ParityTest';",
        cfg["start"], cfg["end"], cfg["asof"], cfg["fy"], cfg["fdow"],
        cfg["wtype"], cfg["qwt"], cfg["tsy"],
    )
    cur.execute("SELECT * FROM dbo.ParityTest ORDER BY [Date];")
    cols = [d[0] for d in cur.description]
    rows = [tuple(r) for r in cur.fetchall()]
    return pd.DataFrame.from_records(rows, columns=cols)


def _py_df(cfg) -> pd.DataFrame:
    wf = WeeklyFiscalConfig(
        enabled=True, first_day_of_week=cfg["fdow"], weekly_type=cfg["wtype"],
        quarter_week_type=cfg["qwt"], type_start_fiscal_year=cfg["tsy"],
    )
    return generate_date_table(
        cfg["start"], cfg["end"], cfg["fy"], as_of_date=cfg["asof"],
        include_calendar=True, include_iso=True, include_fiscal=True,
        weekly_fiscal_cfg=wf,
    )


@pytest.mark.parametrize("cfg", _CONFIGS, ids=[c["id"] for c in _CONFIGS])
def test_sql_python_parity(conn, cfg):
    s = _sql_df(conn, cfg).set_index("Date")
    p = _py_df(cfg).set_index("Date")
    s.index = pd.to_datetime(s.index).normalize()
    p.index = pd.to_datetime(p.index).normalize()

    assert list(s.index) == list(p.index), "SQL and Python produced different date ranges"

    diffs: list[str] = []

    def _record(col, a, b):
        mism = a.ne(b)
        if mism.any():
            d = a.index[mism][0]
            diffs.append(f"{col} @ {d.date()}: sql={a.loc[d]!r} py={b.loc[d]!r}")

    for col in _DATE_COLS:
        _record(col, pd.to_datetime(s[col]).dt.normalize(), pd.to_datetime(p[col]).dt.normalize())
    for col in _INT_COLS:
        _record(col, s[col].astype("int64"), p[col].astype("int64"))
    for col in _LABEL_COLS:
        _record(col, s[col].astype(str).str.strip(), p[col].astype(str).str.strip())

    assert not diffs, (
        f"[{cfg['id']}] SQL/Python weekly-fiscal parity mismatches "
        f"({len(diffs)} total):\n  " + "\n  ".join(diffs[:25])
    )
