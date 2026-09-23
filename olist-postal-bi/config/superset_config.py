"""Isolated local Superset configuration for the Olist postal BI project."""

from pathlib import Path
import os


PROJECT_ROOT = Path(__file__).resolve().parents[1]
RUNTIME_DIR = PROJECT_ROOT / "runtime" / "superset"
RUNTIME_DIR.mkdir(parents=True, exist_ok=True)

SECRET_KEY = os.getenv(
    "SUPERSET_SECRET_KEY",
    "change_me_before_sharing",
)
SQLALCHEMY_DATABASE_URI = f"sqlite:///{RUNTIME_DIR / 'superset.db'}"
WTF_CSRF_ENABLED = True
FEATURE_FLAGS = {
    "DASHBOARD_NATIVE_FILTERS": True,
}
ROW_LIMIT = 50000
SUPERSET_WEBSERVER_PORT = 8088
