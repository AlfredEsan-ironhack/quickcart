-- 02_load_raw.sql
-- Stage 4: load the four CSV files into the raw layer, exactly as received.
--   * Every column is TEXT: raw means "store it, don't interpret it".
--   * _row_num remembers each row's position in the file (tables have no order of their own).
--   * _loaded_at records when the load happened.
--   * Full reload inside one transaction: if anything fails, the old raw data stays untouched.

BEGIN;

DROP TABLE IF EXISTS raw.customers;
CREATE TABLE raw.customers (
    _row_num      BIGINT GENERATED ALWAYS AS IDENTITY,
    customer_id   TEXT,
    customer_name TEXT,
    email         TEXT,
    city          TEXT,
    signup_date   TEXT,
    _loaded_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
COPY raw.customers (customer_id, customer_name, email, city, signup_date)
FROM '/data/raw/customers.csv' WITH (FORMAT csv, HEADER true);

DROP TABLE IF EXISTS raw.products;
CREATE TABLE raw.products (
    _row_num      BIGINT GENERATED ALWAYS AS IDENTITY,
    product_id    TEXT,
    product_name  TEXT,
    category      TEXT,
    supplier_id   TEXT,
    cost_price    TEXT,
    selling_price TEXT,
    _loaded_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
COPY raw.products (product_id, product_name, category, supplier_id, cost_price, selling_price)
FROM '/data/raw/products.csv' WITH (FORMAT csv, HEADER true);

DROP TABLE IF EXISTS raw.orders;
CREATE TABLE raw.orders (
    _row_num       BIGINT GENERATED ALWAYS AS IDENTITY,
    order_id       TEXT,
    customer_id    TEXT,
    product_id     TEXT,
    order_date     TEXT,
    quantity       TEXT,
    unit_price     TEXT,
    payment_status TEXT,
    _loaded_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
COPY raw.orders (order_id, customer_id, product_id, order_date, quantity, unit_price, payment_status)
FROM '/data/raw/orders.csv' WITH (FORMAT csv, HEADER true);

DROP TABLE IF EXISTS raw.clickstream;
CREATE TABLE raw.clickstream (
    _row_num        BIGINT GENERATED ALWAYS AS IDENTITY,
    event_id        TEXT,
    customer_id     TEXT,
    event_type      TEXT,
    page_url        TEXT,
    event_timestamp TEXT,
    device_type     TEXT,
    _loaded_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
COPY raw.clickstream (event_id, customer_id, event_type, page_url, event_timestamp, device_type)
FROM '/data/raw/clickstream.csv' WITH (FORMAT csv, HEADER true);

COMMIT;

-- Reconciliation: these must match the line counts of the files minus the header
SELECT 'customers' AS table_name, count(*) AS row_count FROM raw.customers
UNION ALL SELECT 'products',    count(*) FROM raw.products
UNION ALL SELECT 'orders',      count(*) FROM raw.orders
UNION ALL SELECT 'clickstream', count(*) FROM raw.clickstream;