"""Run one .sql file against the QuickCart database and print any result tables.

Airflow uses this for every SQL step. It works from the laptop too:
    python -m pipeline.run_sql_file sql/03_clean_core.sql
"""
import sys
from pathlib import Path

from pipeline.db import get_connection


def run_sql_file(path: str) -> None:
    sql = Path(path).read_text()
    with get_connection() as conn:
        conn.autocommit = True  # the file's own BEGIN / COMMIT decide the transactions
        conn.add_notice_handler(lambda notice: print("NOTICE:", notice.message_primary))
        with conn.cursor() as cur:
            cur.execute(sql)  # runs every statement in the file, top to bottom
            while True:
                if cur.description:  # this statement returned rows, e.g. the row counts
                    print(" | ".join(col.name for col in cur.description))
                    for row in cur.fetchall():
                        print(" | ".join(str(value) for value in row))
                if not cur.nextset():
                    break
    print(f"OK: {path}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: python -m pipeline.run_sql_file <file.sql>")
    run_sql_file(sys.argv[1])