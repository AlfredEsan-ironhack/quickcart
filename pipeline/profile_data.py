"""Stage 2: look at the raw data BEFORE designing anything.

Read-only. This script changes nothing; it only prints what it finds.
"""
from pathlib import Path

import pandas as pd

RAW_DIR = Path("data/raw")
TABLES = ["customers", "orders", "products", "clickstream"]

# The three timestamp styles I found in clickstream.csv
TS_FORMATS = {
    "ISO with space   2025-02-05 08:29:38": "%Y-%m-%d %H:%M:%S",
    "ISO with T and Z 2025-04-27T00:54:10Z": "%Y-%m-%dT%H:%M:%SZ",
    "day/month/year   03/03/2025 18:50": "%d/%m/%Y %H:%M",
}
EVENT_FIXES = {"clik": "click", "serach": "search", "pageview": "page_view", "logout": "log_out"}


def load(name: str) -> pd.DataFrame:
    # dtype=str keeps every value exactly as written in the file,
    # so pandas can't quietly "fix" the things we want to see.
    return pd.read_csv(RAW_DIR / f"{name}.csv", dtype=str)


def banner(title: str) -> None:
    print("\n" + "=" * 72)
    print(title)
    print("=" * 72)


def normalise_event_type(s: pd.Series) -> pd.Series:
    s = s.str.strip().str.lower().str.replace(r"[\s-]+", "_", regex=True)
    return s.replace(EVENT_FIXES)


def normalise_device(s: pd.Series) -> pd.Series:
    return s.str.strip().str.lower()


def parse_timestamps(ts: pd.Series) -> pd.Series:
    parsed = pd.Series(pd.NaT, index=ts.index, dtype="datetime64[ns]")
    for fmt in TS_FORMATS.values():
        parsed = parsed.fillna(pd.to_datetime(ts, format=fmt, errors="coerce"))
    return parsed


def basics(name: str, df: pd.DataFrame) -> None:
    banner(f"1. BASICS: {name}")
    print(f"rows: {len(df)}   columns: {list(df.columns)}")
    nulls = df.isna().sum()
    print("missing values per column:")
    print(nulls[nulls > 0].to_string() if nulls.any() else "  none")
    print(f"fully identical rows: {df.duplicated().sum()}")


def keys_and_links(t: dict) -> None:
    banner("2. KEYS AND LINKS BETWEEN TABLES")
    customers, orders, products, clicks = (t[n] for n in TABLES)
    print("repeated customer_id:", customers["customer_id"].duplicated().sum())
    print("repeated order_id:   ", orders["order_id"].duplicated().sum())
    print("repeated product_id: ", products["product_id"].duplicated().sum())
    print("repeated event_id:   ", clicks["event_id"].duplicated().sum())

    print("orders with a customer that does not exist:",
          (~orders["customer_id"].isin(customers["customer_id"])).sum())
    print("orders with a product that does not exist: ",
          (~orders["product_id"].isin(products["product_id"])).sum())

    print("\nclickstream customer_id as written in the file:",
          clicks["customer_id"].dropna().head(3).tolist())
    # "7.0" is text and will never equal "7", so convert to a whole number first
    click_ids = pd.to_numeric(clicks["customer_id"]).dropna().astype(int).astype(str)
    print("clicks with a customer that does not exist:",
          (~click_ids.isin(customers["customer_id"])).sum())
    print("clicks with no customer at all (anonymous):", clicks["customer_id"].isna().sum())


def categories(t: dict) -> None:
    banner("3. CATEGORY COLUMNS")
    print("orders.payment_status:")
    print(t["orders"]["payment_status"].value_counts(dropna=False).to_string())

    clicks = t["clickstream"]
    raw = clicks["event_type"]
    print(f"\nclickstream.event_type has {raw.nunique()} different spellings:")
    print(sorted(raw.unique()))
    print("\n...after strip + lowercase + fixing typos:")
    print(normalise_event_type(raw).value_counts().to_string())

    print("\nclickstream.device_type, raw spellings:", sorted(clicks["device_type"].dropna().unique()))
    print("after cleaning:")
    print(normalise_device(clicks["device_type"]).value_counts(dropna=False).to_string())


def dates(t: dict) -> None:
    banner("4. DATES")
    od = pd.to_datetime(t["orders"]["order_date"])
    today = pd.Timestamp.today().normalize()
    print(f"order_date range: {od.min().date()} -> {od.max().date()}")
    print(f"orders dated after today ({today.date()}): {(od > today).sum()} of {len(od)}")

    ts = t["clickstream"]["event_timestamp"]
    print("\nclickstream.event_timestamp, rows matching each style:")
    for label, fmt in TS_FORMATS.items():
        print(f"  {pd.to_datetime(ts, format=fmt, errors='coerce').notna().sum():>5}  {label}")
    parsed = parse_timestamps(ts)
    print(f"parsed with those 3 styles: {parsed.notna().sum()} of {len(ts)}")
    print(f"clickstream covers: {parsed.min()} -> {parsed.max()}")

    # Is 04/06/2025 the 4th of June or the 6th of April?  Let the data answer.
    as_dmy = pd.to_datetime(ts, format="%d/%m/%Y %H:%M", errors="coerce").notna().sum()
    as_mdy = pd.to_datetime(ts, format="%m/%d/%Y %H:%M", errors="coerce").notna().sum()
    print(f"\nslash dates readable as day/month: {as_dmy}  |  as month/day: {as_mdy}")


def money(t: dict) -> None:
    banner("5. NUMBERS THAT SHOULD MAKE SENSE")
    orders, products = t["orders"], t["products"]
    qty = pd.to_numeric(orders["quantity"])
    price = pd.to_numeric(orders["unit_price"])
    print("orders with quantity <= 0:", (qty <= 0).sum(), "| unit_price <= 0:", (price <= 0).sum())

    merged = orders.merge(products, on="product_id")
    differs = pd.to_numeric(merged["unit_price"]) != pd.to_numeric(merged["selling_price"])
    print("orders where unit_price differs from the product's selling_price:", differs.sum())
    below_cost = pd.to_numeric(products["selling_price"]) < pd.to_numeric(products["cost_price"])
    print("products selling below cost:", below_cost.sum())


def event_id_collisions(clicks: pd.DataFrame) -> None:
    banner("6. ARE THE REPEATED event_ids REAL DUPLICATES?")
    shared = clicks[clicks["event_id"].duplicated(keep=False)].copy()
    print(f"{len(shared)} rows share {shared['event_id'].nunique()} event_ids. First few:")
    print(shared.sort_values("event_id").head(6).to_string(index=False))

    # Compare everything except event_id, after cleaning the formatting noise
    shared["event_type"] = normalise_event_type(shared["event_type"])
    shared["device_type"] = normalise_device(shared["device_type"])
    shared["event_timestamp"] = parse_timestamps(shared["event_timestamp"])
    other_cols = ["customer_id", "event_type", "page_url", "event_timestamp", "device_type"]
    same = shared.duplicated(other_cols, keep=False).sum()
    print(f"\nrows that are identical in EVERY other column once cleaned: {same}")


def main() -> None:
    t = {name: load(name) for name in TABLES}
    for name, df in t.items():
        basics(name, df)
    keys_and_links(t)
    categories(t)
    dates(t)
    money(t)
    event_id_collisions(t["clickstream"])


if __name__ == "__main__":
    main()