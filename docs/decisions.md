# QuickCart: data decisions

Findings from `pipeline/profile_data.py` (Stage 2) and what we do about them.

| # | Finding | Decision |
|---|---|---|
| D1 | clickstream.event_type has 25 spellings of 6 events | Strip, lowercase, join words with `_`, fix typos (clik, serach, pageview, logout) |
| D2 | device_type has mixed case and 424 blanks | Lowercase; blanks become `unknown` |
| D3 | Timestamps come in 3 styles | Parse each style explicitly. Slash dates are day/month/year (only 303 of 691 can be read as month/day) |
| D4 | clickstream customer_id is written as "7.0"; 60 are blank | Convert to whole numbers; blank = anonymous visitor, row kept |
| D5 | 37 extra rows reuse an event_id but are different events | Keep the first row per event_id in clean; move the rest to ops with reason `event_id_collision`. Nothing is deleted |
| D6 | 83 blank page_url | Keep the row; page_url stays empty (NULL) |
| D7 | 181 of 500 orders are dated after today | Keep them and add an `is_future_dated` flag. OPEN: ask teacher |
| D8 | What counts as revenue | Paid orders only. Refunds tracked separately |
| D9 | Clickstream covers Jan to Jul 2025; most orders fall outside that window | Don't match purchase events to orders; analyse them separately || D10 | Timestamps carry no time zone (only the `Z` style says UTC) | Treat all clickstream times as UTC |
| D11 | Event logs are large; anonymous visitors have no customer | No foreign key on clean.clickstream.customer_id; links are checked in the quality step (Stage 9) |
| D12 | Raw must stay a faithful copy | Raw tables are all TEXT plus `_row_num` and `_loaded_at`; nothing is ever edited in raw |
