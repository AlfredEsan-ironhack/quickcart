-- 04_create_clickstream_tables.sql
-- Stage 5B (part 1): the empty tables that pipeline/clean_clickstream.py fills.
-- SQL owns the shape and the rules; Python only cleans and loads the rows.

BEGIN;

DROP TABLE IF EXISTS clean.clickstream;
CREATE TABLE clean.clickstream (
    event_id        INTEGER   PRIMARY KEY,
    customer_id     INTEGER,                      -- NULL = anonymous visitor
    event_type      TEXT      NOT NULL
                    CHECK (event_type IN ('page_view', 'click', 'search',
                                          'add_to_cart', 'purchase', 'log_out')),
    page_url        TEXT,
    event_ts        TIMESTAMP NOT NULL,           -- treated as UTC (decision D10)
    device_type     TEXT      NOT NULL
                    CHECK (device_type IN ('mobile', 'desktop', 'tablet', 'unknown')),
    is_anonymous    BOOLEAN   GENERATED ALWAYS AS (customer_id IS NULL) STORED,
    _source_row_num BIGINT    NOT NULL            -- which line of raw.clickstream it came from
);

DROP TABLE IF EXISTS ops.clickstream_rejected;
CREATE TABLE ops.clickstream_rejected (
    _source_row_num BIGINT,
    event_id        TEXT,
    customer_id     TEXT,
    event_type      TEXT,
    page_url        TEXT,
    event_timestamp TEXT,
    device_type     TEXT,
    reason          TEXT        NOT NULL,
    rejected_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMIT;