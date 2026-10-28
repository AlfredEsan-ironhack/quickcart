"""Cleaning rules for the clickstream (decisions D1 to D3 in docs/decisions.md)."""
import pandas as pd

# The three timestamp styles found in Stage 2. Slash dates are day/month/year.
TS_FORMATS = ["%Y-%m-%d %H:%M:%S", "%Y-%m-%dT%H:%M:%SZ", "%d/%m/%Y %H:%M"]

EVENT_FIXES = {"clik": "click", "serach": "search", "pageview": "page_view", "logout": "log_out"}
VALID_EVENT_TYPES = {"page_view", "click", "search", "add_to_cart", "purchase", "log_out"}


def clean_event_type(s: pd.Series) -> pd.Series:
    # " Add To-Cart " -> "add_to_cart", then fix the known typos
    s = s.str.strip().str.lower().str.replace(r"[\s-]+", "_", regex=True)
    return s.replace(EVENT_FIXES)


def clean_device_type(s: pd.Series) -> pd.Series:
    # "MOBILE" -> "mobile"; blank -> "unknown" so dashboards can still group it
    return s.str.strip().str.lower().fillna("unknown")


def parse_event_timestamps(ts: pd.Series) -> pd.Series:
    # Try each known style; a row gets whichever style fits it. Anything else stays NaT.
    parsed = pd.Series(pd.NaT, index=ts.index, dtype="datetime64[ns]")
    for fmt in TS_FORMATS:
        parsed = parsed.fillna(pd.to_datetime(ts, format=fmt, errors="coerce"))
    return parsed