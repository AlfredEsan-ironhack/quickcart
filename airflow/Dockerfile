# Airflow 3.3.2 on Python 3.12, plus a separate Python environment for the QuickCart code.
FROM apache/airflow:3.3.2-python3.12

# Our pipeline needs pandas 3 and psycopg 3. Installing them into Airflow's own Python
# could clash with the package versions Airflow pins, so they get their own virtual environment.
COPY requirements.txt /tmp/requirements.txt
RUN python -m venv /opt/airflow/pipeline-venv \
 && /opt/airflow/pipeline-venv/bin/pip install --no-cache-dir -r /tmp/requirements.txt