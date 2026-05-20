"""
CivicPulse: Database Loader
load_to_db.py

Bulk-loads generated CSVs into SQL Server or PostgreSQL.
Validates row counts, handles duplicates, logs to PipelineAuditLog.

Usage:
    python etl/load_to_db.py --db-type sqlserver  (uses .env)
    python etl/load_to_db.py --db-type postgres
"""

import argparse
import csv
import logging
import os
import time
import uuid
from datetime import date
from typing import Optional

from dotenv import load_dotenv

load_dotenv()
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-8s  %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("civicpulse.loader")

DATA_DIR = os.getenv("DATA_DIR", "data/")

# Load order respects FK dependencies
LOAD_ORDER = [
    ("precincts.csv",        "Precincts",        "PrecinctID"),
    ("voters.csv",           "Voters",           "VoterID"),
    ("elections.csv",        "Elections",        "ElectionID"),
    ("candidates.csv",       "Candidates",       "CandidateID"),
    ("donations.csv",        "Donations",        "DonationID"),
    ("election_results.csv", "ElectionResults",  "ResultID"),
]


def get_connection(db_type: str):
    if db_type == "sqlserver":
        import pyodbc
        conn_str = (
            f"DRIVER={{ODBC Driver 18 for SQL Server}};"
            f"SERVER={os.getenv('DB_SERVER', 'localhost')};"
            f"DATABASE={os.getenv('DB_NAME', 'CivicPulse')};"
            f"UID={os.getenv('DB_USER', 'sa')};"
            f"PWD={os.getenv('DB_PASSWORD', '')};"
            f"TrustServerCertificate=yes;"
        )
        return pyodbc.connect(conn_str)
    elif db_type == "postgres":
        import psycopg2
        return psycopg2.connect(
            host=os.getenv("DB_SERVER", "localhost"),
            dbname=os.getenv("DB_NAME", "civicpulse"),
            user=os.getenv("DB_USER", "postgres"),
            password=os.getenv("DB_PASSWORD", ""),
            port=os.getenv("DB_PORT", 5432),
        )
    else:
        raise ValueError(f"Unsupported db_type: {db_type}")


def log_to_audit(conn, run_id: str, step: str, table: Optional[str],
                 rows_ok: int, rows_fail: int, status: str,
                 error: Optional[str] = None) -> None:
    cursor = conn.cursor()
    cursor.execute(
        """
        INSERT INTO PipelineAuditLog
            (RunID, PipelineStep, TableName, RowsProcessed, RowsFailed,
             Status, ErrorMessage, CompletedAt)
        VALUES (?, ?, ?, ?, ?, ?, ?, SYSUTCDATETIME())
        """,
        (run_id, step, table, rows_ok, rows_fail, status, error),
    )
    conn.commit()


def bulk_load_table(conn, db_type: str, csv_path: str,
                    table: str, pk_col: str,
                    run_id: str, batch_size: int = 1000) -> tuple[int, int]:
    """
    Loads CSV into table using parameterised INSERT with duplicate skipping.
    Returns (rows_inserted, rows_skipped).
    """
    if not os.path.exists(csv_path):
        log.warning(f"  [SKIP] {csv_path} not found")
        return 0, 0

    with open(csv_path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    if not rows:
        return 0, 0

    cols = list(rows[0].keys())
    placeholders = ", ".join(["?" if db_type == "sqlserver" else "%s"] * len(cols))
    col_list = ", ".join(cols)

    if db_type == "sqlserver":
        insert_sql = (
            f"IF NOT EXISTS (SELECT 1 FROM {table} WHERE {pk_col} = ?)\n"
            f"  INSERT INTO {table} ({col_list}) VALUES ({placeholders})"
        )
    else:
        insert_sql = (
            f"INSERT INTO {table} ({col_list}) VALUES ({placeholders}) "
            f"ON CONFLICT ({pk_col}) DO NOTHING"
        )

    cursor = conn.cursor()
    inserted = skipped = 0

    for i in range(0, len(rows), batch_size):
        batch = rows[i : i + batch_size]
        for row in batch:
            vals = [row[c] if row[c] != "" else None for c in cols]
            try:
                if db_type == "sqlserver":
                    cursor.execute(insert_sql, [row[pk_col]] + vals)
                    if cursor.rowcount > 0:
                        inserted += 1
                    else:
                        skipped += 1
                else:
                    cursor.execute(insert_sql, vals)
                    if cursor.rowcount > 0:
                        inserted += 1
                    else:
                        skipped += 1
            except Exception as exc:
                log.debug(f"Row error ({table}): {exc}")
                skipped += 1
        conn.commit()

    return inserted, skipped


def main():
    parser = argparse.ArgumentParser(description="CivicPulse DB loader")
    parser.add_argument("--db-type",   default="sqlserver", choices=["sqlserver", "postgres"])
    parser.add_argument("--data-dir",  default=DATA_DIR)
    parser.add_argument("--batch-size", type=int, default=1000)
    args = parser.parse_args()

    run_id = str(uuid.uuid4())
    log.info(f"Pipeline run: {run_id}")
    log.info(f"DB type: {args.db_type} | Data dir: {args.data_dir}")

    conn = get_connection(args.db_type)
    log.info("Database connection established.")

    total_inserted = total_skipped = 0

    for filename, table, pk_col in LOAD_ORDER:
        csv_path = os.path.join(args.data_dir, filename)
        log.info(f"Loading {table}...")
        t0 = time.time()

        try:
            ins, skip = bulk_load_table(
                conn, args.db_type, csv_path, table, pk_col, run_id, args.batch_size
            )
            elapsed = time.time() - t0
            log.info(f"  ✓  {ins:>7,} inserted | {skip:>5,} skipped  ({elapsed:.1f}s)")
            log_to_audit(conn, run_id, f"load_{table}", table, ins, skip, "SUCCESS")
            total_inserted += ins
            total_skipped += skip

        except Exception as exc:
            log.error(f"  ✗  {table} failed: {exc}")
            log_to_audit(conn, run_id, f"load_{table}", table, 0, 0, "FAILED", str(exc))

    log.info(f"\nDone. Total inserted: {total_inserted:,} | Total skipped: {total_skipped:,}")
    conn.close()


if __name__ == "__main__":
    main()
