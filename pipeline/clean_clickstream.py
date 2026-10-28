"""Stage 5B: clean the clickstream with pandas.

Reads raw.clickstream, fixes the formatting mess, quarantines rows we can't trust,
then writes clean.clickstream and ops.clickstream_rejected.

Run from the project root:   python -m pipeline.clean_clickstream
"""
import io

import pandas as pd

from pipeline.db import get_connection
from pipeline.transforms import (
    VALID_EVENT_TYPES,
    clean_device_type,
    clean_event_type,
    parse_event_timestamps,
)

RAW_COLUMNS = ["event_id", "customer_id", "event_type", "page_url", "event_timestamp", "device_type"]


def read_raw(conn) -> pd.DataFrame:
    with conn.cursor() as cur:
        cur.execute(
            f"SELECT _row_num, {', '.join(RAW_COLUMNS)} FROM raw.clickstream ORDER BY _row_num"
        )
        return pd.DataFrame(cur.fetchall(), columns=["_source_row_num", *RAW_COLUMNS])


def transform(raw: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    df = raw.copy()
    event_id = pd.to_numeric(df["event_id"], errors="coerce").astype("Int64")
    customer_id = pd.to_numeric(df["customer_id"], errors="coerce").astype("Int64")  # "7.0" -> 7
    event_type = clean_event_type(df["event_type"])
    device_type = clean_device_type(df["device_type"])
    event_ts = parse_event_timestamps(df["event_timestamp"])

    # Every row we can't trust gets a reason. The first problem found wins.
    reason = pd.Series(pd.NA, index=df.index, dtype="string")
    reason[event_id.isna()] = "bad_event_id"
    reason[reason.isna() & ~event_type.isin(VALID_EVENT_TYPES)] = "unknown_event_type"
    reason[reason.isna() & event_ts.isna()] = "bad_timestamp"
    # D5: an event_id used more than once -> keep the first in file order, quarantine the rest
    still_ok = reason.isna()
    repeats = event_id[still_ok].duplicated(keep="first")
    reason[repeats[repeats].index] = "event_id_collision"

    ok = reason.isna()
    clean = pd.DataFrame({
        "event_id": event_id[ok],
        "customer_id": customer_id[ok],
        "event_type": event_type[ok],
        "page_url": df["page_url"][ok].str.strip(),
        "event_ts": event_ts[ok],
        "device_type": device_type[ok],
        "_source_row_num": df["_source_row_num"][ok],
    })
    rejected = df.loc[~ok, ["_source_row_num", *RAW_COLUMNS]].assign(reason=reason[~ok])

    # Reconciliation: every raw row must end up in exactly one place
    if len(clean) + len(rejected) != len(raw):
        raise ValueError(f"rows went missing: {len(raw)} in, {len(clean) + len(rejected)} out")
    return clean, rejected


def copy_frame(cur, table: str, frame: pd.DataFrame) -> None:
    # Bulk load: pandas writes the rows as CSV text, Postgres COPY reads it in one go.
    buffer = io.StringIO()
    frame.to_csv(buffer, index=False, header=False)
    columns = ", ".join(frame.columns)
    with cur.copy(f"COPY {table} ({columns}) FROM STDIN WITH (FORMAT csv)") as copy:
        copy.write(buffer.getvalue())


def main() -> None:
    with get_connection() as conn:          # one transaction: commit at the end, or roll back on error
        raw = read_raw(conn)
        clean, rejected = transform(raw)
        with conn.cursor() as cur:
            cur.execute("TRUNCATE clean.clickstream, ops.clickstream_rejected")
            copy_frame(cur, "clean.clickstream", clean)
            copy_frame(cur, "ops.clickstream_rejected", rejected)

    print(f"raw rows: {len(raw)}  ->  clean: {len(clean)}  |  rejected: {len(rejected)}")
    if len(rejected):
        print(rejected["reason"].value_counts().to_string())


if __name__ == "__main__":
    main()