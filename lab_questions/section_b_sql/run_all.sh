#!/usr/bin/env bash
# Runs every Section B answer against the real QuickCart database
# and saves each result in lab_questions/section_b_sql/outputs/.
#
# Run from the QuickCart project root (the folder with docker-compose.yml):
#     bash lab_questions/section_b_sql/run_all.sh
set -euo pipefail

DIR="lab_questions/section_b_sql"

if [ ! -x scripts/run_sql.sh ]; then
    echo "Run this from the QuickCart project root (scripts/run_sql.sh not found)." >&2
    exit 1
fi

mkdir -p "$DIR/outputs"

for name in q1_intermediate q2_advanced q3_optimization q4_database_design q4_check_design; do
    echo ""
    echo ">>>>>>>>>> $name"
    scripts/run_sql.sh "$DIR/$name.sql" 2>&1 | tee "$DIR/outputs/$name.txt"
done

echo ""
echo "Done. Results saved in $DIR/outputs/"
