-- 05_build_analytics.sql
-- Stage 6: business-ready tables for dashboards.
--   * Star schema: dim_customer and dim_product describe WHO and WHAT;
--     fct_orders records WHAT HAPPENED (one row per order, with the money already worked out).
--   * agg_* tables are pre-calculated summaries: a dashboard reads a few hundred ready rows
--     instead of re-adding every order on every page load.
--   * Real tables, not views: the work is done once per pipeline run, not once per click.
-- Rules: revenue = paid orders only (D8). agg_* tables count actuals only, so orders dated
-- after today are left out (D13); fct_orders keeps them, flagged.

BEGIN;

DROP TABLE IF EXISTS
    analytics.dim_customer, analytics.dim_product, analytics.fct_orders,
    analytics.agg_daily_sales, analytics.agg_product_performance,
    analytics.agg_customer_value, analytics.agg_web_activity_daily;

-- Grain: one row per customer
CREATE TABLE analytics.dim_customer AS
SELECT customer_id,
       customer_name,
       email,
       city,
       signup_date,
       date_trunc('month', signup_date)::date AS signup_month
FROM clean.customers;
ALTER TABLE analytics.dim_customer ADD PRIMARY KEY (customer_id);

-- Grain: one row per product
CREATE TABLE analytics.dim_product AS
SELECT product_id,
       product_name,
       category,
       supplier_id,
       cost_price,
       selling_price,
       selling_price - cost_price                                              AS unit_margin,
       round((selling_price - cost_price) / NULLIF(selling_price, 0) * 100, 1) AS margin_pct
FROM clean.products;
ALTER TABLE analytics.dim_product ADD PRIMARY KEY (product_id);

-- Grain: one row per order
CREATE TABLE analytics.fct_orders AS
SELECT o.order_id,
       o.order_date,
       o.customer_id,
       o.product_id,
       o.quantity,
       o.unit_price,
       o.payment_status,
       o.line_amount                                                         AS gross_amount,
       o.payment_status = 'paid'                                             AS is_paid,
       CASE WHEN o.payment_status = 'paid' THEN o.line_amount ELSE 0 END     AS revenue,
       CASE WHEN o.payment_status = 'paid'
            THEN o.line_amount - o.quantity * p.cost_price ELSE 0 END        AS gross_profit,
       CASE WHEN o.payment_status = 'refunded' THEN o.line_amount ELSE 0 END AS refunded_amount,
       o.is_future_dated
FROM clean.orders o
JOIN clean.products p ON p.product_id = o.product_id;
ALTER TABLE analytics.fct_orders ADD PRIMARY KEY (order_id);

-- Grain: one row per day that had orders
CREATE TABLE analytics.agg_daily_sales AS
SELECT order_date                                                       AS sales_date,
       count(*)                                                         AS orders,
       count(*) FILTER (WHERE is_paid)                                  AS paid_orders,
       coalesce(sum(quantity) FILTER (WHERE is_paid), 0)                AS units_sold,
       sum(revenue)                                                     AS revenue,
       sum(gross_profit)                                                AS gross_profit,
       sum(refunded_amount)                                             AS refunded_amount,
       round(sum(revenue) / NULLIF(count(*) FILTER (WHERE is_paid), 0), 2) AS avg_order_value
FROM analytics.fct_orders
WHERE NOT is_future_dated
GROUP BY order_date;
ALTER TABLE analytics.agg_daily_sales ADD PRIMARY KEY (sales_date);

-- Grain: one row per product (products with no sales still appear, with zeros)
CREATE TABLE analytics.agg_product_performance AS
SELECT p.product_id,
       p.product_name,
       p.category,
       count(f.order_id)                                         AS orders,
       count(f.order_id) FILTER (WHERE f.is_paid)                AS paid_orders,
       coalesce(sum(f.quantity) FILTER (WHERE f.is_paid), 0)     AS units_sold,
       coalesce(sum(f.revenue), 0)                               AS revenue,
       coalesce(sum(f.gross_profit), 0)                          AS gross_profit,
       round(100.0 * count(f.order_id) FILTER (WHERE f.payment_status = 'refunded')
             / NULLIF(count(f.order_id), 0), 1)                  AS refund_rate_pct
FROM analytics.dim_product p
LEFT JOIN analytics.fct_orders f
       ON f.product_id = p.product_id AND NOT f.is_future_dated
GROUP BY p.product_id, p.product_name, p.category;
ALTER TABLE analytics.agg_product_performance ADD PRIMARY KEY (product_id);

-- Grain: one row per customer (customers who never paid still appear, with zeros)
CREATE TABLE analytics.agg_customer_value AS
SELECT c.customer_id,
       c.customer_name,
       c.city,
       min(f.order_date)                                         AS first_order_date,
       max(f.order_date)                                         AS last_order_date,
       count(f.order_id) FILTER (WHERE f.is_paid)                AS paid_orders,
       coalesce(sum(f.revenue), 0)                               AS lifetime_revenue,
       round(coalesce(sum(f.revenue), 0)
             / NULLIF(count(f.order_id) FILTER (WHERE f.is_paid), 0), 2) AS avg_order_value,
       rank() OVER (ORDER BY coalesce(sum(f.revenue), 0) DESC)  AS revenue_rank
FROM analytics.dim_customer c
LEFT JOIN analytics.fct_orders f
       ON f.customer_id = c.customer_id AND NOT f.is_future_dated
GROUP BY c.customer_id, c.customer_name, c.city;
ALTER TABLE analytics.agg_customer_value ADD PRIMARY KEY (customer_id);

-- Grain: one row per day + device + event type
CREATE TABLE analytics.agg_web_activity_daily AS
SELECT event_ts::date                              AS activity_date,
       device_type,
       event_type,
       count(*)                                    AS events,
       count(DISTINCT customer_id)                 AS unique_customers,
       count(*) FILTER (WHERE is_anonymous)        AS anonymous_events
FROM clean.clickstream
GROUP BY event_ts::date, device_type, event_type;
ALTER TABLE analytics.agg_web_activity_daily ADD PRIMARY KEY (activity_date, device_type, event_type);

COMMIT;

SELECT 'dim_customer' AS table_name, count(*) AS row_count FROM analytics.dim_customer
UNION ALL SELECT 'dim_product',             count(*) FROM analytics.dim_product
UNION ALL SELECT 'fct_orders',              count(*) FROM analytics.fct_orders
UNION ALL SELECT 'agg_daily_sales',         count(*) FROM analytics.agg_daily_sales
UNION ALL SELECT 'agg_product_performance', count(*) FROM analytics.agg_product_performance
UNION ALL SELECT 'agg_customer_value',      count(*) FROM analytics.agg_customer_value
UNION ALL SELECT 'agg_web_activity_daily',  count(*) FROM analytics.agg_web_activity_daily;