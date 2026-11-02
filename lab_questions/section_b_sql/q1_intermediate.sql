-- q1_intermediate.sql
-- Section B, Q1: intermediate SQL on the REAL QuickCart data (clean layer).
-- Read-only: only SELECT statements. Nothing is created, changed or added.
--
-- Revenue rule (same as the QuickCart pipeline):
--   * revenue = paid orders only                      (decision D8)
--   * "actual" sales leave out orders dated after today (decision D13)
--   * line_amount = quantity * unit_price (a generated column on clean.orders)
-- To use plain gross sales instead, delete the lines that say
--   payment_status = 'paid'   and   NOT is_future_dated


\echo ''
\echo '===== Q1.1 Top 10 customers by revenue ====='
-- Group by customer_id, not by name: two different customers can share a name.
-- The second ORDER BY column is a tie-breaker so the result is the same every run.
SELECT c.customer_id,
       c.customer_name,
       c.city,
       SUM(o.line_amount) AS revenue,
       COUNT(*)           AS paid_orders
FROM clean.orders o
JOIN clean.customers c ON c.customer_id = o.customer_id
WHERE o.payment_status = 'paid'
  AND NOT o.is_future_dated
GROUP BY c.customer_id, c.customer_name, c.city
ORDER BY revenue DESC, c.customer_id
LIMIT 10;


\echo ''
\echo '===== Q1.2 Month-over-month sales growth ====='
-- months: one row for EVERY month between the first and last sale,
--         so a month with no sales shows as 0 instead of disappearing
--         (otherwise LAG would compare with the wrong month).
-- LAG(sales): the previous month's sales.
-- NULLIF(prev_sales, 0): avoids dividing by zero.
WITH paid AS (
    SELECT order_date, line_amount
    FROM clean.orders
    WHERE payment_status = 'paid'
      AND NOT is_future_dated
),
months AS (
    SELECT generate_series(date_trunc('month', MIN(order_date)),
                           date_trunc('month', MAX(order_date)),
                           INTERVAL '1 month')::date AS month
    FROM paid
),
monthly AS (
    SELECT m.month,
           COALESCE(SUM(p.line_amount), 0) AS sales
    FROM months m
    LEFT JOIN paid p ON date_trunc('month', p.order_date)::date = m.month
    GROUP BY m.month
),
with_prev AS (
    SELECT month,
           sales,
           LAG(sales) OVER (ORDER BY month) AS prev_sales
    FROM monthly
)
SELECT month,
       sales,
       prev_sales,
       ROUND(100.0 * (sales - prev_sales) / NULLIF(prev_sales, 0), 2) AS mom_growth_pct
FROM with_prev
ORDER BY month;


\echo ''
\echo '===== Q1.3 Customers who ordered in consecutive months ====='
-- Step 1: one row per customer per month they ordered in (DISTINCT).
-- Step 2: LAG per customer (PARTITION BY) = the previous month they were active.
-- Step 3: previous active month + 1 month = this month  -> the two months touch.
-- "Ordered" = any order that is not future-dated, whatever its payment status.
WITH customer_months AS (
    SELECT DISTINCT customer_id,
           date_trunc('month', order_date)::date AS month
    FROM clean.orders
    WHERE NOT is_future_dated
),
with_prev AS (
    SELECT customer_id,
           month,
           LAG(month) OVER (PARTITION BY customer_id ORDER BY month) AS prev_month
    FROM customer_months
)
SELECT c.customer_id,
       c.customer_name,
       COUNT(*)     AS consecutive_month_pairs,
       MIN(w.month) AS first_consecutive_month
FROM with_prev w
JOIN clean.customers c ON c.customer_id = w.customer_id
WHERE (w.prev_month + INTERVAL '1 month')::date = w.month
GROUP BY c.customer_id, c.customer_name
ORDER BY consecutive_month_pairs DESC, c.customer_id;


\echo ''
\echo '===== Q1.4 Products never ordered ====='
-- NOT EXISTS: "is there any order for this product?" (0 rows = every product was ordered).
-- Do not use NOT IN here: one NULL in the subquery makes NOT IN return nothing.
SELECT p.product_id,
       p.product_name,
       p.category
FROM clean.products p
WHERE NOT EXISTS (
    SELECT 1
    FROM clean.orders o
    WHERE o.product_id = p.product_id
)
ORDER BY p.product_id;


\echo ''
\echo '===== Q1.4b Products with no paid, actual sale ====='
-- Stricter version: ordered maybe, but never actually paid for.
SELECT p.product_id,
       p.product_name,
       p.category
FROM clean.products p
WHERE NOT EXISTS (
    SELECT 1
    FROM clean.orders o
    WHERE o.product_id = p.product_id
      AND o.payment_status = 'paid'
      AND NOT o.is_future_dated
)
ORDER BY p.product_id;


\echo ''
\echo '===== Q1.5 Revenue contribution % by category ====='
-- Inner SUM = revenue per category.
-- SUM(SUM(...)) OVER () = the grand total, shown on every row.
-- Category / grand total * 100 = share. The shares add up to 100.
SELECT p.category,
       SUM(o.line_amount) AS revenue,
       ROUND(100.0 * SUM(o.line_amount)
             / SUM(SUM(o.line_amount)) OVER (), 2) AS pct_of_total
FROM clean.orders o
JOIN clean.products p ON p.product_id = o.product_id
WHERE o.payment_status = 'paid'
  AND NOT o.is_future_dated
GROUP BY p.category
ORDER BY pct_of_total DESC;
