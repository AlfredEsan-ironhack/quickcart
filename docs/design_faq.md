# QuickCart: design questions and answers

Short answers to the questions a reviewer, teacher or interviewer is most likely to ask.

## The data layers

**Why is the raw layer all TEXT?**
Raw must be an exact copy of what arrived. If we converted types while loading, one bad value
(like `"7.0"` or `" purchase "`) would crash the load and we'd never see it. We convert later,
in the clean layer, where we control what happens to bad values.

**Why keep a raw layer at all?**
It's the safety net. If a cleaning rule turns out to be wrong, we fix the rule and rebuild
clean and analytics from raw in seconds, without asking anyone for the files again.

**Why `_row_num`?**
A database table has no built-in order. To apply "keep the first row per event_id" we have to
record each row's position in the file ourselves.

**Is this ETL or ELT?**
Mostly ELT: data is loaded first (raw), then transformed inside the database with SQL. The
clickstream is the exception: its messy logic is easier in pandas, so that step reads from raw,
transforms in Python and loads the result back (an ETL-style step inside an ELT platform).
Choosing the tool per problem is the point.

## Cleaning decisions

**Why quarantine the 37 rows instead of deleting them?**
They share an `event_id` with another row but are completely different events (different
customer, type and time), so they aren't duplicates. The source broke its own ID promise.
Quarantine keeps `event_id` usable as a unique key *and* keeps the evidence for the source team.

**How do you know `03/03/2025` is day/month and not month/day?**
The data proves it: in the slash dates the first number goes up to 31 and the second only up
to 7. Read as month/day, only 303 of 691 would even be valid dates.

**Why flag future-dated orders instead of removing them?**
181 of 500 orders (36%) are dated after today, and 322,845 of paid revenue depends on them.
Deleting that much data is a business decision, not a technical one. So they're kept and
flagged, and the "actuals" dashboard tables leave them out until the business confirms the rule.

**What counts as revenue?**
Paid orders only. Pending, failed and refunded amounts are reported separately. The rule lives
in one place (`fct_orders.revenue`), so every dashboard uses the same definition.

## Modelling

**What is a star schema?**
Dimension tables describe who and what (`dim_customer`, `dim_product`). A fact table records
what happened, with the measures already worked out (`fct_orders`: revenue, profit, refunds).
Drawn out, the fact sits in the middle with the dimensions around it.

**What is "grain"?**
What one row means: `fct_orders` is one row per order, `agg_daily_sales` one row per day.
Mixing grains (for example, joining daily totals to individual orders) is the most common
cause of wrong dashboard numbers. Primary keys on each table enforce the grain.

**Why tables and not views for analytics?**
A view recalculates every time someone opens it, which keeps the dashboards slow. A view would
also block the nightly rebuild, because Postgres won't drop a table that a view depends on.

**Why is the `NOT is_future_dated` condition in the `ON` clause and not in `WHERE`?**
With a LEFT JOIN, a condition in `WHERE` throws away the rows that had no match, which quietly
turns it into an inner join. Products and customers with no sales would vanish from the report.
In `ON`, they stay, with zeros.

## Reliability

**What does idempotent mean here?**
Running a step twice gives the same result as running it once. Every step is a full rebuild
(`DROP` + `CREATE`, or `TRUNCATE` + reload) or uses `IF NOT EXISTS`. That's what makes
Airflow's automatic retries safe: a retry never creates duplicates.

**Why wrap steps in transactions?**
All or nothing. If loading `orders.csv` fails, the customers loaded a second earlier are rolled
back too, so raw still holds the last good load and dashboards never see a half-finished state.

**What happens when a task fails?**
Airflow retries it twice, one minute apart. If it still fails, the task turns red, every
downstream task is marked `upstream_failed`, and nothing after it runs, so bad data never
reaches the dashboards. Fix the cause, then **Clear** the task in the UI to rerun from there.

**What does the quality gate check?**
Seven checks that count problems: row reconciliation (raw = clean + rejected), no lost orders,
no events for unknown customers, one fact row per order, revenue adding up across layers,
non-empty dashboard tables, and a maximum quarantine share of 5%. Any problem fails the run.

## Performance

**Why didn't Postgres index the foreign keys automatically?**
Postgres only indexes primary keys and UNIQUE columns. Foreign-key columns like
`orders.customer_id` need their own index, or every join reads the whole table.

**What is a partial index?**
An index on only some rows: `idx_orders_paid_date` covers paid orders only, because revenue
questions only look at those. It's smaller, so it's faster.

**Does column order matter in `(event_type, event_ts)`?**
Yes. It works like a phone book sorted by surname, then first name: it helps
"purchases in March", but not "everything in March" (time alone).

**How did you prove the speed-ups?**
500 orders is too small to measure, so `sql/07` builds a 2-million-row copy, measures with
`EXPLAIN ANALYZE`, applies each fix and measures again. Customer lookup: 145 ms → 0.56 ms.
Daily dashboard: 331 ms → 0.46 ms.

## Platform

**Why a separate Python environment inside the Airflow image?**
The pipeline uses pandas 3 and psycopg 3. Installing them into Airflow's own Python could
clash with the versions Airflow pins. A separate virtual environment isolates them.

**Why a separate database for Airflow?**
Airflow's bookkeeping (runs, task states) has nothing to do with business data. Keeping them
apart means the warehouse can be rebuilt or reset without touching the orchestrator, and the
other way round.

**How are secrets handled?**
Passwords live in `.env`, which is in `.gitignore` and never committed. `.env.example` shows
which settings are needed. The password is generated randomly, and ports are bound to
`127.0.0.1` so only the laptop can connect.

## Airflow questions from the course labs

**What is a DAG?**
A Directed Acyclic Graph: tasks connected by arrows that always point forward and never loop
back. In Airflow, it describes which steps run, in what order, and when.

**Scheduler vs executor?**
The scheduler decides *what* should run and *when* (checking schedules and dependencies). The
executor decides *how* tasks actually run. Here it's the `LocalExecutor`, which runs tasks as
processes on the same machine and can run independent tasks in parallel.

**What does `catchup=False` do?**
Without it, Airflow would go back and create a run for every missed day since `start_date`.
With it, only the most recent run is scheduled.

**What is an operator?**
A template for one kind of task. `BashOperator` runs a shell command. Every task in this DAG is
a BashOperator that runs one project script.

**What does the cron expression `0 6 * * *` mean?**
Minute 0, hour 6, every day of the month, every month, every day of the week: every day at 06:00.

**How are task dependencies set?**
With `>>`: `load_raw >> [clean_core, prepare_clickstream]` fans out into two parallel paths,
and `[clean_core, clean_clickstream] >> build_analytics` waits for both before continuing.
