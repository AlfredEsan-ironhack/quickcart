-- q3_optimization.sql
-- Section B, Q3: analyse the "18-minute" query on the REAL QuickCart tables.
-- No data is created. The test index in part 4 is built inside a transaction
-- and ROLLED BACK, so clean.orders is exactly the same afterwards.
-- Do not run this while the Airflow DAG is running (part 4 briefly locks clean.orders).


\echo ''
\echo '===== Q3 part 1: how big are the real tables? ====='
SELECT 'clean.orders'    AS table_name, COUNT(*) AS row_count,
       pg_size_pretty(pg_total_relation_size('clean.orders'))    AS size_incl_indexes
FROM clean.orders
UNION ALL
SELECT 'clean.customers', COUNT(*),
       pg_size_pretty(pg_total_relation_size('clean.customers'))
FROM clean.customers;

\echo '--- indexes that already exist on clean.orders (from sql/06_indexes.sql) ---'
SELECT indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'clean'
  AND tablename  = 'orders'
ORDER BY indexname;


\echo ''
\echo '===== Q3 part 2: how selective is the WHERE filter? ====='
-- A filter that keeps a large share of the table cannot be helped much by an index.
SELECT COUNT(*)                                                    AS all_orders,
       COUNT(*) FILTER (WHERE order_date >= DATE '2025-01-01')     AS matching_orders,
       ROUND(100.0 * COUNT(*) FILTER (WHERE order_date >= DATE '2025-01-01')
             / NULLIF(COUNT(*), 0), 1)                             AS pct_matching
FROM clean.orders;


\echo ''
\echo '===== Q3 part 3: the ORIGINAL query, real plan, default settings ====='
-- Read the plan from the most indented line outwards.
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.customer_name,
       SUM(o.quantity * o.unit_price)
FROM clean.orders o
JOIN clean.customers c ON o.customer_id = c.customer_id
WHERE order_date >= '2025-01-01'
GROUP BY c.customer_name;

\echo '--- correctness check: does GROUP BY customer_name merge different customers? ---'
-- If rows_group_by_name is smaller than rows_group_by_id, revenue of different
-- people with the same name is being added together.
SELECT (SELECT COUNT(*) FROM (
            SELECT c.customer_name
            FROM clean.orders o
            JOIN clean.customers c ON c.customer_id = o.customer_id
            WHERE o.order_date >= DATE '2025-01-01'
            GROUP BY c.customer_name) a)  AS rows_group_by_name,
       (SELECT COUNT(*) FROM (
            SELECT o.customer_id
            FROM clean.orders o
            WHERE o.order_date >= DATE '2025-01-01'
            GROUP BY o.customer_id) b)    AS rows_group_by_id;

\echo '--- customer names that belong to more than one customer_id ---'
SELECT customer_name,
       COUNT(*) AS customers_with_this_name
FROM clean.customers
GROUP BY customer_name
HAVING COUNT(*) > 1
ORDER BY customers_with_this_name DESC, customer_name;


\echo ''
\echo '===== Q3 part 4: proposed index + rewritten query (rolled back afterwards) ====='
BEGIN;

-- Proposed covering index: the date filter plus every column the query needs,
-- so Postgres can answer from the index without reading the table.
CREATE INDEX lab_q3_orders_date_cover
    ON clean.orders (order_date) INCLUDE (customer_id, quantity, unit_price);

-- The real table is small, so the planner prefers reading it whole.
-- Switching sequential scans off for THIS transaction only shows the
-- index path the planner would take on a big table.
SET LOCAL enable_seqscan = off;

\echo '--- original query, index path ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.customer_name,
       SUM(o.quantity * o.unit_price)
FROM clean.orders o
JOIN clean.customers c ON o.customer_id = c.customer_id
WHERE order_date >= '2025-01-01'
GROUP BY c.customer_name;

\echo '--- rewritten query: total per customer_id FIRST, join the names AFTER ---'
EXPLAIN (ANALYZE, BUFFERS)
WITH order_totals AS (
    SELECT customer_id,
           SUM(quantity * unit_price) AS total_revenue
    FROM clean.orders
    WHERE order_date >= DATE '2025-01-01'
    GROUP BY customer_id
)
SELECT c.customer_id,
       c.customer_name,
       t.total_revenue
FROM order_totals t
JOIN clean.customers c ON c.customer_id = t.customer_id;

ROLLBACK;

\echo '--- proof the test index is gone (must return 0) ---'
SELECT COUNT(*) AS lab_indexes_left
FROM pg_indexes
WHERE indexname = 'lab_q3_orders_date_cover';


\echo ''
\echo '===== Q3 part 5: the rewritten query, real result (first 10 by revenue) ====='
WITH order_totals AS (
    SELECT customer_id,
           SUM(quantity * unit_price) AS total_revenue
    FROM clean.orders
    WHERE order_date >= DATE '2025-01-01'
    GROUP BY customer_id
)
SELECT c.customer_id,
       c.customer_name,
       t.total_revenue
FROM order_totals t
JOIN clean.customers c ON c.customer_id = t.customer_id
ORDER BY t.total_revenue DESC, c.customer_id
LIMIT 10;
