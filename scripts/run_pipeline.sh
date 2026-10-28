#!/usr/bin/env bash
# Runs the whole QuickCart pipeline from the laptop, in the same order as the Airflow DAG.
# Usage (from the project folder, with .venv active):   scripts/run_pipeline.sh
set -euo pipefail
cd "$(dirname "$0")/.."

python -m pipeline.run_sql_file sql/01_create_schemas.sql
python -m pipeline.run_sql_file sql/02_load_raw.sql
python -m pipeline.run_sql_file sql/03_clean_core.sql
python -m pipeline.run_sql_file sql/04_create_clickstream_tables.sql
python -m pipeline.clean_clickstream
python -m pipeline.run_sql_file sql/05_build_analytics.sql
python -m pipeline.run_sql_file sql/06_indexes.sql
python -m pipeline.quality_checks