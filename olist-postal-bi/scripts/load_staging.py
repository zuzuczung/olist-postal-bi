#!/usr/bin/env python3
"""Idempotently load unmodified Olist CSV fields into staging text tables."""

from pathlib import Path
import csv
import hashlib
import os
import uuid

import psycopg
from dotenv import load_dotenv
from psycopg import sql


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DATA_DIR = Path.home() / ".cache/kagglehub/datasets/olistbr/brazilian-ecommerce/versions/2"
FILES = {
    "olist_customers_dataset.csv": "customers",
    "olist_geolocation_dataset.csv": "geolocation",
    "olist_order_items_dataset.csv": "order_items",
    "olist_order_payments_dataset.csv": "order_payments",
    "olist_order_reviews_dataset.csv": "order_reviews",
    "olist_orders_dataset.csv": "orders",
    "olist_products_dataset.csv": "products",
    "olist_sellers_dataset.csv": "sellers",
    "product_category_name_translation.csv": "product_category_translation",
}


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    load_dotenv(PROJECT_ROOT / ".env")
    data_dir = Path(os.getenv("OLIST_DATA_DIR", DEFAULT_DATA_DIR)).expanduser().resolve()
    missing = [name for name in FILES if not (data_dir / name).exists()]
    if missing:
        raise SystemExit(f"Missing source files in {data_dir}: {', '.join(missing)}")

    dsn = os.getenv("DATABASE_URL")
    kwargs = {} if dsn else {
        "host": os.getenv("PGHOST", "127.0.0.1"),
        "port": int(os.getenv("PGPORT", "55432")),
        "dbname": os.getenv("PGDATABASE", "olist_postal_bi"),
        "user": os.getenv("PGUSER", "olist_bi"),
        "password": os.getenv("PGPASSWORD"),
    }
    run_id = uuid.uuid4()
    connection = psycopg.connect(dsn) if dsn else psycopg.connect(**kwargs)
    with connection as conn:
        with conn.cursor() as cur:
            cur.execute((PROJECT_ROOT / "sql" / "01_staging.sql").read_text())
            for filename, table in FILES.items():
                path = data_dir / filename
                with path.open(encoding="utf-8-sig", newline="") as check_handle:
                    header = next(csv.reader(check_handle))
                cur.execute(sql.SQL("TRUNCATE TABLE staging.{}").format(sql.Identifier(table)))
                copy_stmt = sql.SQL(
                    "COPY staging.{} ({}) FROM STDIN WITH "
                    "(FORMAT CSV, HEADER TRUE, NULL '__KAGGLE_NULL_SENTINEL__')"
                ).format(
                    sql.Identifier(table),
                    sql.SQL(", ").join(map(sql.Identifier, header)),
                )
                with cur.copy(copy_stmt) as copy:
                    with path.open("rb") as source:
                        while chunk := source.read(1024 * 1024):
                            copy.write(chunk)
                cur.execute(sql.SQL("SELECT count(*) FROM staging.{}").format(sql.Identifier(table)))
                row_count = cur.fetchone()[0]
                cur.execute(
                    """
                    INSERT INTO staging.load_audit
                        (run_id, source_file, target_table, row_count, file_sha256)
                    VALUES (%s, %s, %s, %s, %s)
                    """,
                    (run_id, str(path), f"staging.{table}", row_count, file_sha256(path)),
                )
                print(f"{filename} -> staging.{table}: {row_count:,} rows")
    print(f"load_run_id={run_id}")


if __name__ == "__main__":
    main()
