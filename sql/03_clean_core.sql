-- 03_clean_core.sql
-- Stage 5A: typed, trustworthy versions of customers, products and orders.
--   * Real data types (INTEGER, DATE, NUMERIC) instead of text
--   * PRIMARY KEY: the database itself refuses a second row with the same ID
--   * FOREIGN KEY (REFERENCES): an order must point at a customer and product that exist
--   * CHECK: impossible values (quantity 0, unknown status) are refused
--   * DISTINCT ON: one row per ID even if a future file repeats an ID (latest row in the file wins)
-- Full rebuild inside one transaction: all three tables succeed together or not at all.

BEGIN;

DROP TABLE IF EXISTS clean.orders, clean.customers, clean.products;

CREATE TABLE clean.customers (
    customer_id   INTEGER PRIMARY KEY,
    customer_name TEXT    NOT NULL,
    email         TEXT    NOT NULL UNIQUE,
    city          TEXT    NOT NULL,
    signup_date   DATE    NOT NULL
);

INSERT INTO clean.customers (customer_id, customer_name, email, city, signup_date)
SELECT DISTINCT ON (customer_id::INTEGER)
       customer_id::INTEGER,
       trim(customer_name),
       lower(trim(email)),
       initcap(trim(city)),
       signup_date::DATE
FROM raw.customers
ORDER BY customer_id::INTEGER, _row_num DESC;

CREATE TABLE clean.products (
    product_id    INTEGER       PRIMARY KEY,
    product_name  TEXT          NOT NULL,
    category      TEXT          NOT NULL,
    supplier_id   INTEGER       NOT NULL,
    cost_price    NUMERIC(10,2) NOT NULL CHECK (cost_price >= 0),
    selling_price NUMERIC(10,2) NOT NULL CHECK (selling_price >= 0)
);

INSERT INTO clean.products (product_id, product_name, category, supplier_id, cost_price, selling_price)
SELECT DISTINCT ON (product_id::INTEGER)
       product_id::INTEGER,
       trim(product_name),
       trim(category),
       supplier_id::INTEGER,
       cost_price::NUMERIC(10,2),
       selling_price::NUMERIC(10,2)
FROM raw.products
ORDER BY product_id::INTEGER, _row_num DESC;

CREATE TABLE clean.orders (
    order_id        INTEGER       PRIMARY KEY,
    customer_id     INTEGER       NOT NULL REFERENCES clean.customers (customer_id),
    product_id      INTEGER       NOT NULL REFERENCES clean.products (product_id),
    order_date      DATE          NOT NULL,
    quantity        INTEGER       NOT NULL CHECK (quantity > 0),
    unit_price      NUMERIC(10,2) NOT NULL CHECK (unit_price >= 0),
    payment_status  TEXT          NOT NULL
                    CHECK (payment_status IN ('paid', 'pending', 'failed', 'refunded')),
    line_amount     NUMERIC(12,2) GENERATED ALWAYS AS (quantity * unit_price) STORED,
    is_future_dated BOOLEAN       NOT NULL
);

INSERT INTO clean.orders (order_id, customer_id, product_id, order_date,
                          quantity, unit_price, payment_status, is_future_dated)
SELECT DISTINCT ON (order_id::INTEGER)
       order_id::INTEGER,
       customer_id::INTEGER,
       product_id::INTEGER,
       order_date::DATE,
       quantity::INTEGER,
       unit_price::NUMERIC(10,2),
       lower(trim(payment_status)),
       order_date::DATE > CURRENT_DATE
FROM raw.orders
ORDER BY order_id::INTEGER, _row_num DESC;

COMMIT;

SELECT 'customers' AS table_name, count(*) AS row_count FROM clean.customers
UNION ALL SELECT 'products', count(*) FROM clean.products
UNION ALL SELECT 'orders',   count(*) FROM clean.orders
UNION ALL SELECT 'orders dated after today', count(*) FROM clean.orders WHERE is_future_dated;