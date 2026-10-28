-- 06_indexes.sql
-- Stage 7: indexes for the questions dashboards and analysts ask most.
--   * Postgres indexes PRIMARY KEYs and UNIQUE columns by itself, but NOT foreign keys.
--     Joins and filters on customer_id / product_id need their own index.
--   * Clean and analytics tables are rebuilt every run, which removes their indexes,
--     so this script always runs right after them. IF NOT EXISTS makes it safe to repeat.

-- clean layer
CREATE INDEX IF NOT EXISTS idx_orders_customer  ON clean.orders (customer_id);
CREATE INDEX IF NOT EXISTS idx_orders_product   ON clean.orders (product_id);
CREATE INDEX IF NOT EXISTS idx_orders_date      ON clean.orders (order_date);
-- partial index: only paid orders, because revenue questions only ever look at those
CREATE INDEX IF NOT EXISTS idx_orders_paid_date ON clean.orders (order_date)
    WHERE payment_status = 'paid';
CREATE INDEX IF NOT EXISTS idx_clicks_customer  ON clean.clickstream (customer_id);
CREATE INDEX IF NOT EXISTS idx_clicks_type_ts   ON clean.clickstream (event_type, event_ts);

-- analytics layer
CREATE INDEX IF NOT EXISTS idx_fct_date     ON analytics.fct_orders (order_date);
CREATE INDEX IF NOT EXISTS idx_fct_customer ON analytics.fct_orders (customer_id);
CREATE INDEX IF NOT EXISTS idx_fct_product  ON analytics.fct_orders (product_id);

-- Refresh the statistics the query planner uses to choose between scanning and using an index
ANALYZE;

SELECT schemaname AS schema, tablename AS table_name, indexname AS index_name
FROM pg_indexes
WHERE schemaname IN ('clean', 'analytics')
ORDER BY schemaname, tablename, indexname;