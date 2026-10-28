-- 01_create_schemas.sql
-- Creates the four layers of the QuickCart platform.
-- Safe to run again and again: IF NOT EXISTS skips anything already there.

CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS clean;
CREATE SCHEMA IF NOT EXISTS analytics;
CREATE SCHEMA IF NOT EXISTS ops;

COMMENT ON SCHEMA raw       IS 'Files loaded exactly as received, all text. Never edited.';
COMMENT ON SCHEMA clean     IS 'Typed, standardised, de-duplicated tables.';
COMMENT ON SCHEMA analytics IS 'Business-ready tables and views for dashboards.';
COMMENT ON SCHEMA ops       IS 'Pipeline bookkeeping: rejected rows, run logs, checks.';