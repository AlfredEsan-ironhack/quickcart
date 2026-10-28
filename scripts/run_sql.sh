#!/usr/bin/env bash
# Runs one .sql file inside the QuickCart Postgres container.
# Usage: scripts/run_sql.sh sql/01_create_schemas.sql
#        scripts/run_sql.sh <<'SQL' ... SQL               (typed queries)
set -euo pipefail
docker compose exec -T postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1' < "${1:-/dev/stdin}"