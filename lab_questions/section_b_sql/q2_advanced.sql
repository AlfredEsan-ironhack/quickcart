-- q2_advanced.sql
-- Section B, Q2: advanced SQL (window functions) on the REAL QuickCart data.
-- Read-only: only SELECT statements. Nothing is created, changed or added.
--
-- Revenue rule (same as the QuickCart pipeline):
--   * revenue = paid orders only                      (decision D8)
--   * "actual" sales leave out orders dated after today (decision D13)
-- To use plain gross sales instead, delete the lines that say
--   payment_status = 'paid'   and   NOT is_future_dated


\echo ''
\echo '===== Q2.1 Rank customers by total revenue ====='
-- RANK:       ties share a rank, then a gap   (1, 1, 3)
-- DENSE_RANK: ties share a rank, no gap       (1, 1, 2)
-- ROW_NUMBER: always unique                   (1, 2, 3) - customer_id breaks ties
WITH cust_rev AS (
    SELECT customer_id,
           SUM(line_amount) AS revenue
    FROM clean.orders
    WHERE payment_status = 'paid'
      AND NOT is_future_dated
    GROUP BY customer_id
)
SELECT c.customer_id,
       c.customer_name,
       r.revenue,
       RANK()       OVER (ORDER BY r.revenue DESC)                AS rnk,
       DENSE_RANK() OVER (ORDER BY r.revenue DESC)                AS dense_rnk,
       ROW_NUMBER() OVER (ORDER BY r.revenue DESC, c.customer_id) AS row_num
FROM cust_rev r
JOIN clean.customers c ON c.customer_id = r.customer_id
ORDER BY rnk, c.customer_id;


\echo ''
\echo '===== Q2.2 Running total of sales by month ====='
-- Every month between first and last sale is listed (months with no sales = 0).
-- SUM(...) OVER (ORDER BY month ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
--   = everything from the first month up to this one.
-- Check: the last running_total equals total paid actual revenue.
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
)
SELECT month,
       sales,
       SUM(sales) OVER (ORDER BY month
                        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_total
FROM monthly
ORDER BY month;

\echo '--- check: total paid actual revenue (must equal the last running_total above) ---'
SELECT SUM(line_amount) AS total_paid_actual_revenue
FROM clean.orders
WHERE payment_status = 'paid'
  AND NOT is_future_dated;


\echo ''
\echo '===== Q2.3 Highest selling product per category (by revenue) ====='
-- "Top N per group": total per product -> rank inside each category -> keep rank 1.
-- The rank is filtered OUTSIDE the CTE because WHERE runs before window functions.
-- RANK keeps ties: two products sharing first place both appear.
-- For "highest selling by units", change ORDER BY revenue DESC to ORDER BY units DESC.
WITH product_sales AS (
    SELECT p.category,
           p.product_id,
           p.product_name,
           SUM(o.line_amount) AS revenue,
           SUM(o.quantity)    AS units
    FROM clean.orders o
    JOIN clean.products p ON p.product_id = o.product_id
    WHERE o.payment_status = 'paid'
      AND NOT o.is_future_dated
    GROUP BY p.category, p.product_id, p.product_name
),
ranked AS (
    SELECT product_sales.*,
           RANK() OVER (PARTITION BY category ORDER BY revenue DESC) AS rnk
    FROM product_sales
)
SELECT category,
       product_id,
       product_name,
       revenue,
       units
FROM ranked
WHERE rnk = 1
ORDER BY category;


\echo ''
\echo '===== Q2.4 7-day rolling average sales ====='
-- calendar: one row for every day between the first and last sale.
-- LEFT JOIN + COALESCE: days with no sales count as 0.
--   (Without the calendar, missing days would make "7 rows back" stretch over weeks.)
-- Order conditions sit in the ON clause, not WHERE, so empty days are kept.
-- ROWS BETWEEN 6 PRECEDING AND CURRENT ROW = today + the 6 days before = 7 days.
-- days_in_window shows that the first 6 days only have a partial window.
WITH bounds AS (
    SELECT MIN(order_date) AS first_day,
           MAX(order_date) AS last_day
    FROM clean.orders
    WHERE payment_status = 'paid'
      AND NOT is_future_dated
),
calendar AS (
    SELECT d::date AS day
    FROM bounds,
         generate_series(bounds.first_day, bounds.last_day, INTERVAL '1 day') AS d
),
daily AS (
    SELECT cal.day,
           COALESCE(SUM(o.line_amount), 0) AS sales
    FROM calendar cal
    LEFT JOIN clean.orders o
           ON o.order_date = cal.day
          AND o.payment_status = 'paid'
          AND NOT o.is_future_dated
    GROUP BY cal.day
)
SELECT day,
       sales,
       ROUND(AVG(sales) OVER w, 2) AS rolling_7d_avg,
       COUNT(*)         OVER w     AS days_in_window
FROM daily
WINDOW w AS (ORDER BY day ROWS BETWEEN 6 PRECEDING AND CURRENT ROW)
ORDER BY day;
