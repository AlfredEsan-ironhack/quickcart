-- 07_performance_demo.sql
-- Stage 7: PROVE the performance fixes on a table big enough to matter.
-- Our real orders table has 500 rows, which is too small to show any difference,
-- so we build a 2-million-row copy with the same shape, measure, fix, and measure again.
-- Not part of the daily pipeline. Run it once and keep the output as evidence.

\echo '=== Building ops.perf_orders: 2,000,000 synthetic orders ...'
SELECT setseed(0.42);   -- same "random" data every time, so results are repeatable
DROP TABLE IF EXISTS ops.perf_orders, ops.perf_orders_text, ops.perf_daily_sales;
CREATE TABLE ops.perf_orders AS
SELECT row_number() OVER (ORDER BY order_date)::int AS order_id, *
FROM (
    SELECT 1 + floor(random() * 200000)::int                    AS customer_id,
           101 + floor(random() * 10)::int                      AS product_id,
           DATE '2024-01-01' + floor(random() * 1000)::int      AS order_date,
           1 + floor(random() * 5)::int                         AS quantity,
           (ARRAY[89, 149, 249, 349, 499, 599, 799, 1299, 1999, 2499])
               [1 + floor(random() * 10)::int]::numeric(10,2)   AS unit_price
    FROM generate_series(1, 2000000)
) AS fake
ORDER BY order_date;   -- real orders arrive day by day, so store them in date order too
ANALYZE ops.perf_orders;

\echo ''
\echo '=== TEST 1: one customer''s orders (a customer-support screen) - NO index'
EXPLAIN (ANALYZE, COSTS OFF) SELECT * FROM ops.perf_orders WHERE customer_id = 4242;

\echo '=== TEST 2: one week of sales (a weekly report) - NO index'
EXPLAIN (ANALYZE, COSTS OFF)
SELECT order_date, sum(quantity * unit_price) FROM ops.perf_orders
WHERE order_date BETWEEN DATE '2025-03-01' AND DATE '2025-03-07' GROUP BY order_date;

\echo '=== FIX: add indexes on the columns we filter by'
CREATE INDEX idx_perf_customer ON ops.perf_orders (customer_id);
CREATE INDEX idx_perf_date     ON ops.perf_orders (order_date);
ANALYZE ops.perf_orders;

\echo '=== TEST 1 again - WITH index'
EXPLAIN (ANALYZE, COSTS OFF) SELECT * FROM ops.perf_orders WHERE customer_id = 4242;

\echo '=== TEST 2 again - WITH index'
EXPLAIN (ANALYZE, COSTS OFF)
SELECT order_date, sum(quantity * unit_price) FROM ops.perf_orders
WHERE order_date BETWEEN DATE '2025-03-01' AND DATE '2025-03-07' GROUP BY order_date;

\echo ''
\echo '=== TEST 3: a dashboard showing revenue for every day - calculated live from 2M rows'
EXPLAIN (ANALYZE, COSTS OFF)
SELECT order_date, sum(quantity * unit_price) AS revenue FROM ops.perf_orders GROUP BY order_date;

\echo '=== FIX: pre-aggregate once (this is what our agg_daily_sales table does)'
CREATE TABLE ops.perf_daily_sales AS
SELECT order_date, sum(quantity * unit_price) AS revenue FROM ops.perf_orders GROUP BY order_date;
ALTER TABLE ops.perf_daily_sales ADD PRIMARY KEY (order_date);
ANALYZE ops.perf_daily_sales;

\echo '=== TEST 3 again - the dashboard reads the ready-made summary'
EXPLAIN (ANALYZE, COSTS OFF) SELECT order_date, revenue FROM ops.perf_daily_sales;

\echo ''
\echo '=== TEST 4: storage - the same 2M rows stored as text (like raw) vs proper types (like clean)'
CREATE TABLE ops.perf_orders_text AS
SELECT order_id::text, customer_id::text, product_id::text,
       order_date::text, quantity::text, unit_price::text
FROM ops.perf_orders;
SELECT 'stored as TEXT'        AS version, pg_size_pretty(pg_table_size('ops.perf_orders_text')) AS size
UNION ALL
SELECT 'stored as real types', pg_size_pretty(pg_table_size('ops.perf_orders'));

\echo '=== Cleaning up the demo tables'
DROP TABLE ops.perf_orders, ops.perf_orders_text, ops.perf_daily_sales;