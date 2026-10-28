"""QuickCart daily pipeline: CSV files -> raw -> clean -> analytics -> quality gate.

Every task runs one of the project's own scripts, so this file holds no business logic.
It only decides the ORDER of the steps, WHEN they run, and what happens when one FAILS.
"""
import os
from datetime import timedelta

import pendulum
from airflow.providers.standard.operators.bash import BashOperator
from airflow.sdk import DAG

# Where the project and its Python live inside the Airflow container (overridable for testing)
PROJECT = os.environ.get("QUICKCART_HOME", "/opt/quickcart")
PYTHON = os.environ.get("PIPELINE_PYTHON", "/opt/airflow/pipeline-venv/bin/python")


def run_sql(task_id: str, sql_file: str) -> BashOperator:
    return BashOperator(
        task_id=task_id,
        bash_command=f"cd {PROJECT} && {PYTHON} -m pipeline.run_sql_file sql/{sql_file}",
    )


def run_python(task_id: str, module: str) -> BashOperator:
    return BashOperator(
        task_id=task_id,
        bash_command=f"cd {PROJECT} && {PYTHON} -m pipeline.{module}",
    )


with DAG(
    dag_id="quickcart_pipeline",
    description="Rebuild the QuickCart data platform from the raw CSV files",
    schedule="0 6 * * *",  # every day at 06:00, before anyone opens a dashboard
    start_date=pendulum.datetime(2026, 10, 1, tz="Europe/Amsterdam"),
    catchup=False,  # don't go back and run every missed day since start_date
    max_active_runs=1,  # full rebuilds must never overlap
    default_args={
        "owner": "data-engineering",
        "retries": 2,  # a temporary hiccup (database restarting) fixes itself
        "retry_delay": timedelta(minutes=1),
    },
    tags=["quickcart", "elt"],
    doc_md=__doc__,
) as dag:
    create_schemas = run_sql("create_schemas", "01_create_schemas.sql")
    load_raw = run_sql("load_raw", "02_load_raw.sql")
    clean_core = run_sql("clean_core", "03_clean_core.sql")
    prepare_clickstream = run_sql("prepare_clickstream_tables", "04_create_clickstream_tables.sql")
    clean_clickstream = run_python("clean_clickstream", "clean_clickstream")
    build_analytics = run_sql("build_analytics", "05_build_analytics.sql")
    create_indexes = run_sql("create_indexes", "06_indexes.sql")
    quality_checks = run_python("quality_checks", "quality_checks")

    # Fan out after the raw load (the two cleaning paths don't depend on each other),
    # then fan back in: analytics needs BOTH clean paths to be finished.
    create_schemas >> load_raw >> [clean_core, prepare_clickstream]
    prepare_clickstream >> clean_clickstream
    [clean_core, clean_clickstream] >> build_analytics >> create_indexes >> quality_checks