"""One place that knows how to connect to the QuickCart database."""
import os
from pathlib import Path

import psycopg

ENV_FILE = Path(__file__).resolve().parent.parent / ".env"


def _load_env_file() -> None:
    # Copy KEY=VALUE lines from .env into the environment,
    # without overwriting anything that is already set (Airflow will set its own).
    if not ENV_FILE.exists():
        return
    for line in ENV_FILE.read_text().splitlines():
        if "=" in line and not line.startswith("#"):
            key, value = line.split("=", 1)
            os.environ.setdefault(key.strip(), value.strip())


def get_connection() -> psycopg.Connection:
    _load_env_file()
    return psycopg.connect(
        host=os.getenv("DB_HOST", "localhost"),
        port=os.getenv("DB_PORT", "5433"),
        user=os.environ["POSTGRES_USER"],
        password=os.environ["POSTGRES_PASSWORD"],
        dbname=os.environ["POSTGRES_DB"],
    )