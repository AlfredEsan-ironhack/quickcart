"""Quality gate: the pipeline only counts as successful if every check passes.

Each check is a SQL query that counts PROBLEMS. 0 problems = pass.
Run from the project root:   python -m pipeline.quality_checks
"""
from pipeline.db import get_connection

MAX_REJECTED_SHARE = 0.05  # raise the alarm if more than 5% of clickstream rows get quarantined

CHECKS = {
    "clickstream: every raw row is either clean or rejected": """
        SELECT abs((SELECT count(*) FROM raw.clickstream)
                 - (SELECT count(*) FROM clean.clickstream)
                 - (SELECT count(*) FROM ops.clickstream_rejected))""",
    "orders: no rows lost between raw and clean": """
        SELECT abs((SELECT count(*) FROM raw.orders) - (SELECT count(*) FROM clean.orders))""",
    "clickstream: no events for unknown customers (D11)": """
        SELECT count(*) FROM clean.clickstream c
        WHERE c.customer_id IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM clean.customers k WHERE k.customer_id = c.customer_id)""",
    "analytics: one fact row per clean order": """
        SELECT abs((SELECT count(*) FROM analytics.fct_orders) - (SELECT count(*) FROM clean.orders))""",
    "analytics: daily revenue adds up to clean paid orders": """
        SELECT abs(coalesce((SELECT sum(revenue) FROM analytics.agg_daily_sales), 0)
                 - coalesce((SELECT sum(line_amount) FROM clean.orders
                             WHERE payment_status = 'paid' AND NOT is_future_dated), 0))""",
    "analytics: dashboard tables are not empty": """
        SELECT ((SELECT count(*) FROM analytics.agg_daily_sales) = 0
             OR (SELECT count(*) FROM analytics.agg_customer_value) = 0
             OR (SELECT count(*) FROM analytics.agg_web_activity_daily) = 0)::int""",
    f"clickstream: quarantined share at most {MAX_REJECTED_SHARE:.0%}": f"""
        SELECT ((SELECT count(*) FROM ops.clickstream_rejected)::numeric
                / NULLIF((SELECT count(*) FROM raw.clickstream), 0) > {MAX_REJECTED_SHARE})::int""",
}


def main() -> None:
    failed = []
    with get_connection() as conn, conn.cursor() as cur:
        for name, sql in CHECKS.items():
            cur.execute(sql)
            problems = cur.fetchone()[0]
            passed = problems == 0  # None (e.g. an empty table) counts as a failure too
            print(f"{'PASS' if passed else 'FAIL'}  {name}   (problems: {problems})")
            if not passed:
                failed.append(name)
    if failed:
        raise SystemExit(f"{len(failed)} quality check(s) FAILED: {failed}")
    print(f"All {len(CHECKS)} quality checks passed.")


if __name__ == "__main__":
    main()