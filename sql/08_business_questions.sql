-- 08_business_questions.sql
-- Stage 8: answer QuickCart's business questions from the analytics layer.
-- The queries read the ready-made analytics tables, so each one runs in milliseconds.
-- Revenue = paid orders only (D8). Actuals only: no future-dated orders (D13).

\echo '=== Q1. How is revenue trending, month by month?'
WITH monthly AS (
    SELECT date_trunc('month', sales_date)::date AS month,
           sum(paid_orders)                      AS paid_orders,
           sum(revenue)                          AS revenue
    FROM analytics.agg_daily_sales
    GROUP BY 1
)
SELECT month,
       paid_orders,
       revenue,
       round(100.0 * (revenue - lag(revenue) OVER (ORDER BY month))
             / NULLIF(lag(revenue) OVER (ORDER BY month), 0), 1) AS growth_vs_prev_month_pct
FROM monthly
ORDER BY month;

\echo '=== Q2. Which categories make the money, and at what margin?'
SELECT category,
       sum(paid_orders)                                                AS paid_orders,
       sum(units_sold)                                                 AS units,
       sum(revenue)                                                    AS revenue,
       sum(gross_profit)                                               AS gross_profit,
       round(100.0 * sum(gross_profit) / NULLIF(sum(revenue), 0), 1)   AS margin_pct,
       round(100.0 * sum(revenue) / sum(sum(revenue)) OVER (), 1)      AS share_of_revenue_pct
FROM analytics.agg_product_performance
GROUP BY category
ORDER BY revenue DESC;

\echo '=== Q3. Who are the top 10 customers, and how concentrated is revenue?'
SELECT revenue_rank,
       customer_name,
       city,
       paid_orders,
       lifetime_revenue,
       round(100.0 * lifetime_revenue / sum(lifetime_revenue) OVER (), 1) AS share_pct,
       round(100.0 * sum(lifetime_revenue) OVER (ORDER BY revenue_rank, customer_id)
             / sum(lifetime_revenue) OVER (), 1)                         AS cumulative_pct
FROM analytics.agg_customer_value
ORDER BY revenue_rank, customer_id
LIMIT 10;

\echo '=== Q4. How healthy are payments? (money stuck in failed, pending and refunded orders)'
SELECT payment_status,
       count(*)                                                          AS orders,
       round(100.0 * count(*) / sum(count(*)) OVER (), 1)                AS pct_of_orders,
       sum(gross_amount)                                                 AS amount,
       round(100.0 * sum(gross_amount) / sum(sum(gross_amount)) OVER (), 1) AS pct_of_amount
FROM analytics.fct_orders
WHERE NOT is_future_dated
GROUP BY payment_status
ORDER BY orders DESC;

\echo '=== Q5. Which products get refunded most?'
SELECT product_name, category, orders, refund_rate_pct, revenue
FROM analytics.agg_product_performance
ORDER BY refund_rate_pct DESC NULLS LAST, revenue DESC;

\echo '=== Q6. Which cities bring the most revenue per paying customer?'
SELECT city,
       count(*)                                    AS customers,
       count(*) FILTER (WHERE paid_orders > 0)     AS paying_customers,
       sum(lifetime_revenue)                       AS revenue,
       round(sum(lifetime_revenue)
             / NULLIF(count(*) FILTER (WHERE paid_orders > 0), 0), 2) AS revenue_per_paying_customer
FROM analytics.agg_customer_value
GROUP BY city
ORDER BY revenue DESC;

\echo '=== Q7. Do customers come back? (segments by number of paid orders)'
SELECT CASE WHEN paid_orders = 0 THEN '0  never paid'
            WHEN paid_orders = 1 THEN '1  one-time'
            WHEN paid_orders <= 3 THEN '2-3 returning'
            ELSE '4+ loyal' END                                            AS segment,
       count(*)                                                            AS customers,
       sum(lifetime_revenue)                                               AS revenue,
       round(100.0 * sum(lifetime_revenue) / sum(sum(lifetime_revenue)) OVER (), 1) AS share_of_revenue_pct
FROM analytics.agg_customer_value
GROUP BY 1
ORDER BY 1;

\echo '=== Q8. When do purchases happen on the website? (top 5 hours)'
SELECT extract(hour FROM event_ts)::int AS hour_of_day,
       count(*)                         AS purchase_events
FROM clean.clickstream
WHERE event_type = 'purchase'
GROUP BY 1
ORDER BY purchase_events DESC, hour_of_day
LIMIT 5;

\echo '=== Q9. Which devices do visitors use, and how many are anonymous?'
SELECT device_type,
       sum(events)                                                AS events,
       round(100.0 * sum(events) / sum(sum(events)) OVER (), 1)   AS share_pct,
       round(100.0 * sum(anonymous_events) / sum(events), 1)      AS anonymous_pct
FROM analytics.agg_web_activity_daily
GROUP BY device_type
ORDER BY events DESC;

\echo '=== Q10. Data health: what did the pipeline hold back or flag?'
SELECT 'clickstream rows quarantined (event_id collisions)' AS check_name, count(*)::text AS value
FROM ops.clickstream_rejected
UNION ALL
SELECT 'orders dated after today (kept, flagged)', count(*)::text
FROM clean.orders WHERE is_future_dated
UNION ALL
SELECT 'paid revenue held back as future-dated', sum(line_amount)::text
FROM clean.orders WHERE is_future_dated AND payment_status = 'paid'
UNION ALL
SELECT 'events with unknown device', count(*)::text
FROM clean.clickstream WHERE device_type = 'unknown'
UNION ALL
SELECT 'anonymous events', count(*)::text
FROM clean.clickstream WHERE is_anonymous;