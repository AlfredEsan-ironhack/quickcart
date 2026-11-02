# Lab questions

Solutions to course lab questions. They are **not** part of the QuickCart pipeline:
Airflow never runs anything in this folder. They only use the real QuickCart data
already loaded and cleaned in PostgreSQL.

## Section B: SQL engineering

Run everything from the project root:

```bash
bash lab_questions/section_b_sql/run_all.sh
```

Results are saved in `lab_questions/section_b_sql/outputs/`.

| File | Question | What it touches |
|---|---|---|
| `q1_intermediate.sql` | Q1: top customers, month-over-month growth, consecutive months, products never ordered, category share | Reads `clean.*` only |
| `q2_advanced.sql` | Q2: ranking, running total, top product per category, 7-day rolling average | Reads `clean.*` only |
| `q3_optimization.sql` | Q3: bottlenecks, indexes, execution plans for the slow query | Reads `clean.*`; the test index is rolled back |
| `q4_database_design.sql` | Q4: shipment tracking, inventory, support tickets | Creates schema `lab_q4` only |
| `q4_check_design.sql` | Q4: lists every table, primary key, foreign key, rule and index | Reads `lab_q4` only |
| `q4_teardown.sql` | Removes `lab_q4` | `lab_q4` only |

## Data used

Only the real QuickCart data in `clean.customers`, `clean.products` and `clean.orders`.
No generated or sample rows are used anywhere. The Q4 tables are created empty,
except for copies of the real customers, products and orders that their
foreign keys point to.

## Revenue rule

Same as the pipeline: paid orders only (D8), and orders dated after today are
left out of actual sales (D13).
