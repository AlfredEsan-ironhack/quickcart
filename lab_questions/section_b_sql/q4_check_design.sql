-- q4_check_design.sql
-- Section B, Q4: proves the design meets the requirements by reading the
-- database catalog. Read-only. No rows are inserted anywhere.


\echo ''
\echo '===== Q4 check 1: every table and its primary key ====='
SELECT t.table_name,
       string_agg(k.column_name, ', ' ORDER BY k.ordinal_position) AS primary_key
FROM information_schema.tables t
LEFT JOIN information_schema.table_constraints tc
       ON tc.table_schema = t.table_schema
      AND tc.table_name   = t.table_name
      AND tc.constraint_type = 'PRIMARY KEY'
LEFT JOIN information_schema.key_column_usage k
       ON k.constraint_name = tc.constraint_name
      AND k.table_schema    = tc.table_schema
WHERE t.table_schema = 'lab_q4'
GROUP BY t.table_name
ORDER BY t.table_name;


\echo ''
\echo '===== Q4 check 2: every foreign key (child column -> parent table) ====='
SELECT conrelid::regclass::text AS child_table,
       pg_get_constraintdef(oid) AS foreign_key
FROM pg_constraint
WHERE contype = 'f'
  AND connamespace = 'lab_q4'::regnamespace
ORDER BY 1, 2;


\echo ''
\echo '===== Q4 check 3: every CHECK and UNIQUE rule ====='
SELECT conrelid::regclass::text AS table_name,
       CASE contype WHEN 'c' THEN 'CHECK' ELSE 'UNIQUE' END AS rule_type,
       pg_get_constraintdef(oid) AS rule
FROM pg_constraint
WHERE contype IN ('c', 'u')
  AND connamespace = 'lab_q4'::regnamespace
ORDER BY 1, 2, 3;


\echo ''
\echo '===== Q4 check 4: every index ====='
SELECT tablename, indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'lab_q4'
ORDER BY tablename, indexname;


\echo ''
\echo '===== Q4 check 5: totals ====='
SELECT (SELECT COUNT(*) FROM information_schema.tables
        WHERE table_schema = 'lab_q4')                                       AS tables,
       (SELECT COUNT(*) FROM pg_constraint
        WHERE contype = 'f' AND connamespace = 'lab_q4'::regnamespace)       AS foreign_keys,
       (SELECT COUNT(*) FROM pg_indexes WHERE schemaname = 'lab_q4')         AS indexes;


\echo ''
\echo '===== Q4 check 6: the pipeline is safe ====='
\echo '(must return 0 rows: nothing in lab_q4 depends on the pipeline tables)'
SELECT conrelid::regclass  AS lab_table,
       confrelid::regclass AS pipeline_table
FROM pg_constraint
WHERE contype = 'f'
  AND connamespace = 'lab_q4'::regnamespace
  AND confrelid IN ('clean.customers'::regclass,
                    'clean.products'::regclass,
                    'clean.orders'::regclass);
