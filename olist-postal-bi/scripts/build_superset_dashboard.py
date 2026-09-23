#!/usr/bin/env python3
"""Create or update the isolated Olist Superset database, dataset, charts, and dashboard."""

from __future__ import annotations

import json
import os
import uuid
from pathlib import Path
from typing import Any
from urllib.parse import quote_plus

import requests
from dotenv import load_dotenv


PROJECT_DIR = Path(__file__).resolve().parents[1]
load_dotenv(PROJECT_DIR / ".env")
BASE_URL = os.getenv("SUPERSET_URL", "http://127.0.0.1:8088").rstrip("/")
USERNAME = os.getenv("SUPERSET_USERNAME", "admin")
PASSWORD = os.environ["SUPERSET_PASSWORD"]
DATABASE_NAME = "Olist Postal BI"
DATASET_TABLE = "fact_order"
DATASET_SCHEMA = "analytics"
DASHBOARD_TITLE = "Olist - Sản lượng & Hiệu quả giao hàng"
DASHBOARD_SLUG = "olist-postal-delivery-performance"


class SupersetClient:
    def __init__(self) -> None:
        self.session = requests.Session()
        login = self.session.post(
            f"{BASE_URL}/api/v1/security/login",
            json={"username": USERNAME, "password": PASSWORD, "provider": "db", "refresh": True},
            timeout=60,
        )
        login.raise_for_status()
        token = login.json()["access_token"]
        self.headers = {"Authorization": f"Bearer {token}"}
        csrf = self.session.get(
            f"{BASE_URL}/api/v1/security/csrf_token/", headers=self.headers, timeout=60
        )
        csrf.raise_for_status()
        self.headers["X-CSRFToken"] = csrf.json()["result"]

    def get(self, path: str) -> dict[str, Any]:
        response = self.session.get(f"{BASE_URL}{path}", headers=self.headers, timeout=60)
        response.raise_for_status()
        return response.json()

    def get_bytes(self, path: str) -> bytes:
        response = self.session.get(f"{BASE_URL}{path}", headers=self.headers, timeout=120)
        response.raise_for_status()
        return response.content

    def post(self, path: str, payload: dict[str, Any]) -> dict[str, Any]:
        response = self.session.post(
            f"{BASE_URL}{path}", headers=self.headers, json=payload, timeout=120
        )
        if not response.ok:
            raise RuntimeError(f"POST {path}: {response.status_code} {response.text}")
        return response.json()

    def put(self, path: str, payload: dict[str, Any]) -> dict[str, Any]:
        response = self.session.put(
            f"{BASE_URL}{path}", headers=self.headers, json=payload, timeout=120
        )
        if not response.ok:
            raise RuntimeError(f"PUT {path}: {response.status_code} {response.text}")
        return response.json()


def sql_metric(label: str, expression: str) -> dict[str, Any]:
    return {
        "expressionType": "SQL",
        "sqlExpression": expression,
        "column": None,
        "aggregate": None,
        "datasourceWarning": False,
        "hasCustomLabel": True,
        "label": label,
        "optionName": f"metric_{uuid.uuid4().hex[:12]}",
    }


def simple_filter(subject: str, operator: str, comparator: Any) -> dict[str, Any]:
    return {
        "expressionType": "SIMPLE",
        "subject": subject,
        "operator": operator,
        "operatorId": operator,
        "comparator": comparator,
        "clause": "WHERE",
        "sqlExpression": None,
        "filterOptionName": f"filter_{uuid.uuid4().hex[:12]}",
    }


def chart_definitions(dataset_id: int) -> list[dict[str, Any]]:
    datasource = f"{dataset_id}__table"
    common = {
        "datasource": datasource,
        "adhoc_filters": [],
        "time_range": "No filter",
        "row_limit": 10000,
    }

    def big(name: str, metric: dict[str, Any], y_format: str = "SMART_NUMBER") -> dict[str, Any]:
        return {
            "name": name,
            "viz_type": "big_number_total",
            "description": "KPI cấp đơn hàng; chịu tác động của bộ lọc dashboard.",
            "params": {
                **common,
                "viz_type": "big_number_total",
                "metric": metric,
                "header_font_size": 0.36,
                "subheader_font_size": 0.15,
                "y_axis_format": y_format,
                "show_trend_line": False,
            },
        }

    def bar(
        name: str,
        x_axis: str,
        metric: dict[str, Any],
        *,
        filters: list[dict[str, Any]] | None = None,
        row_limit: int = 50,
        y_format: str = "SMART_NUMBER",
    ) -> dict[str, Any]:
        return {
            "name": name,
            "viz_type": "echarts_timeseries_bar",
            "description": "Tổng hợp từ analytics.fact_order (một dòng cho một đơn).",
            "params": {
                **common,
                "viz_type": "echarts_timeseries_bar",
                "x_axis": x_axis,
                "metrics": [metric],
                "groupby": [],
                "adhoc_filters": filters or [],
                "row_limit": row_limit,
                "order_desc": True,
                "show_value": True,
                "show_legend": False,
                "truncate_metric": True,
                "y_axis_format": y_format,
                "x_axis_sort": "value",
                "x_axis_sort_asc": False,
                "orientation": "vertical",
                "color_scheme": "supersetColors",
            },
        }

    def line(
        name: str,
        metric: dict[str, Any],
        *,
        description: str,
        y_format: str = "SMART_NUMBER",
    ) -> dict[str, Any]:
        return {
            "name": name,
            "viz_type": "echarts_timeseries_line",
            "description": description,
            "params": {
                **common,
                "viz_type": "echarts_timeseries_line",
                "x_axis": "purchased_at",
                "time_grain_sqla": "P1M",
                "metrics": [metric],
                "groupby": [],
                "show_legend": False,
                "show_value": False,
                "truncate_metric": True,
                "x_axis_time_format": "%Y-%m",
                "y_axis_format": y_format,
                "color_scheme": "supersetColors",
                "rich_tooltip": True,
            },
        }

    return [
        big("KPI - Tổng số đơn", sql_metric("Số đơn", "COUNT(*)")),
        big(
            "KPI - Số đơn đã giao",
            sql_metric("Đã giao", "COUNT(*) FILTER (WHERE is_delivered)"),
        ),
        big(
            "KPI - Tỷ lệ giao đúng hạn",
            sql_metric(
                "Tỷ lệ đúng hạn",
                "100.0 * COUNT(*) FILTER (WHERE is_on_time) / "
                "NULLIF(COUNT(*) FILTER (WHERE is_on_time IS NOT NULL), 0)",
            ),
            ".2f",
        ),
        big(
            "KPI - Thời gian giao TB (ngày)",
            sql_metric(
                "Ngày giao TB", "AVG(delivery_days) FILTER (WHERE is_delivered)"
            ),
            ".2f",
        ),
        big(
            "KPI - Tổng phí vận chuyển",
            sql_metric("Phí vận chuyển", "SUM(freight_value)"),
            ",.2f",
        ),
        line(
            "Xu hướng sản lượng theo tháng",
            sql_metric("Số đơn", "COUNT(*)"),
            description="Số đơn theo tháng đặt hàng.",
        ),
        line(
            "Xu hướng tỷ lệ giao đúng hạn",
            sql_metric(
                "Tỷ lệ đúng hạn (%)",
                "100.0 * COUNT(*) FILTER (WHERE is_on_time) / "
                "NULLIF(COUNT(*) FILTER (WHERE is_on_time IS NOT NULL), 0)",
            ),
            description="Tỷ lệ đúng hạn theo tháng; mẫu số chỉ gồm đơn đủ điều kiện SLA.",
            y_format=".2f",
        ),
        big(
            "KPI - Số đơn giao trễ",
            sql_metric("Giao trễ", "COUNT(*) FILTER (WHERE is_on_time = false)"),
        ),
        big(
            "KPI - Số ngày trễ TB",
            sql_metric("Ngày trễ TB", "AVG(late_days) FILTER (WHERE is_on_time = false)"),
            ".2f",
        ),
        bar(
            "Cơ cấu trạng thái đơn hàng",
            "order_status",
            sql_metric("Số đơn", "COUNT(*)"),
            row_limit=10,
        ),
        bar(
            "Tỷ lệ giao trễ theo bang nhận",
            "receiver_state",
            sql_metric(
                "Tỷ lệ trễ (%)",
                "100.0 * COUNT(*) FILTER (WHERE is_on_time = false) / "
                "NULLIF(COUNT(*) FILTER (WHERE is_on_time IS NOT NULL), 0)",
            ),
            row_limit=27,
            y_format=".2f",
        ),
        {
            "name": "Phân bố thời gian giao hàng",
            "viz_type": "histogram_v2",
            "description": "Phân bố số ngày từ lúc đặt đến lúc giao của đơn đã giao.",
            "params": {
                **common,
                "viz_type": "histogram_v2",
                "column": "delivery_days",
                "groupby": [],
                "bins": 20,
                "normalize": False,
                "cumulative": False,
                "adhoc_filters": [simple_filter("is_delivered", "==", True)],
                "show_value": False,
                "show_legend": False,
                "x_axis_title": "Số ngày giao",
                "y_axis_title": "Số đơn",
                "color_scheme": "supersetColors",
            },
        },
        bar(
            "Nhóm số ngày trễ",
            "late_day_bucket",
            sql_metric("Số đơn", "COUNT(*)"),
            filters=[simple_filter("late_day_bucket", "!=", "Not eligible")],
            row_limit=10,
        ),
        line(
            "Xu hướng thời gian giao trung bình",
            sql_metric("Ngày giao TB", "AVG(delivery_days) FILTER (WHERE is_delivered)"),
            description="Số ngày trung bình từ đặt đến giao theo tháng đặt hàng.",
            y_format=".2f",
        ),
        bar(
            "Điểm đánh giá theo tình trạng giao hàng",
            "delivery_performance_status",
            sql_metric("Điểm đánh giá TB", "AVG(avg_review_score)"),
            filters=[simple_filter("review_count", ">", 0)],
            row_limit=10,
            y_format=".2f",
        ),
        bar(
            "Sản lượng theo vùng nhận",
            "receiver_macro_region",
            sql_metric("Số đơn", "COUNT(*)"),
            row_limit=10,
        ),
        bar(
            "Sản lượng theo vùng gửi chính",
            "primary_sender_macro_region",
            sql_metric("Số đơn", "COUNT(*)"),
            row_limit=10,
        ),
        bar(
            "Sản lượng theo bang gửi chính",
            "primary_sender_state",
            sql_metric("Số đơn", "COUNT(*)"),
            row_limit=27,
        ),
        bar(
            "Top tuyến bang gửi - nhận theo sản lượng",
            "primary_state_route",
            sql_metric("Số đơn", "COUNT(*)"),
            filters=[simple_filter("primary_state_route", "!=", "Unknown route")],
            row_limit=20,
        ),
        bar(
            "Tỷ lệ trễ theo tuyến trọng yếu",
            "primary_state_route",
            sql_metric(
                "Tỷ lệ trễ (%)",
                "CASE WHEN COUNT(*) FILTER (WHERE is_on_time IS NOT NULL) >= 100 "
                "THEN 100.0 * COUNT(*) FILTER (WHERE is_on_time = false) / "
                "NULLIF(COUNT(*) FILTER (WHERE is_on_time IS NOT NULL), 0) END",
            ),
            filters=[simple_filter("primary_state_route", "!=", "Unknown route")],
            row_limit=20,
            y_format=".2f",
        ),
        bar(
            "Hiệu quả nội bang và liên bang",
            "route_scope",
            sql_metric(
                "Tỷ lệ trễ (%)",
                "100.0 * COUNT(*) FILTER (WHERE is_on_time = false) / "
                "NULLIF(COUNT(*) FILTER (WHERE is_on_time IS NOT NULL), 0)",
            ),
            filters=[simple_filter("route_scope", "!=", "Unknown")],
            row_limit=5,
            y_format=".2f",
        ),
        big(
            "KPI - Điểm đánh giá trung bình",
            sql_metric("Điểm đánh giá TB", "AVG(avg_review_score) FILTER (WHERE review_count > 0)"),
            ".2f",
        ),
        big(
            "KPI - Tỷ lệ đánh giá thấp",
            sql_metric(
                "Đánh giá thấp (%)",
                "100.0 * COUNT(*) FILTER (WHERE is_low_review) / "
                "NULLIF(COUNT(*) FILTER (WHERE is_low_review IS NOT NULL), 0)",
            ),
            ".2f",
        ),
        bar(
            "Cơ cấu nhóm điểm đánh giá",
            "review_score_group",
            sql_metric("Số đơn", "COUNT(*)"),
            filters=[simple_filter("review_score_group", "!=", "No review")],
            row_limit=5,
        ),
        bar(
            "Điểm đánh giá theo nhóm ngày trễ",
            "late_day_bucket",
            sql_metric("Điểm đánh giá TB", "AVG(avg_review_score)"),
            filters=[simple_filter("review_count", ">", 0)],
            row_limit=10,
            y_format=".2f",
        ),
        bar(
            "Tỷ lệ đánh giá thấp theo tình trạng giao",
            "delivery_performance_status",
            sql_metric(
                "Đánh giá thấp (%)",
                "100.0 * COUNT(*) FILTER (WHERE is_low_review) / "
                "NULLIF(COUNT(*) FILTER (WHERE is_low_review IS NOT NULL), 0)",
            ),
            row_limit=10,
            y_format=".2f",
        ),
        bar(
            "Tỷ lệ đánh giá thấp theo bang nhận",
            "receiver_state",
            sql_metric(
                "Đánh giá thấp (%)",
                "CASE WHEN COUNT(*) FILTER (WHERE is_low_review IS NOT NULL) >= 100 "
                "THEN 100.0 * COUNT(*) FILTER (WHERE is_low_review) / "
                "NULLIF(COUNT(*) FILTER (WHERE is_low_review IS NOT NULL), 0) END",
            ),
            row_limit=27,
            y_format=".2f",
        ),
    ]


def find_result(items: dict[str, Any], field: str, value: Any) -> dict[str, Any] | None:
    return next((row for row in items.get("result", []) if row.get(field) == value), None)


def ensure_database(client: SupersetClient) -> int:
    existing = find_result(client.get("/api/v1/database/?q=(page_size:100)"), "database_name", DATABASE_NAME)
    if existing:
        return int(existing["id"])
    payload = {
        "database_name": DATABASE_NAME,
        "sqlalchemy_uri": os.getenv(
            "SUPERSET_DATABASE_URI",
            "postgresql+psycopg2://{user}:{password}@{host}:{port}/{database}".format(
                user=quote_plus(os.environ["PGUSER"]),
                password=quote_plus(os.environ["PGPASSWORD"]),
                host=os.environ["PGHOST"],
                port=os.environ["PGPORT"],
                database=os.environ["PGDATABASE"],
            ),
        ),
        "expose_in_sqllab": True,
        "allow_run_async": False,
        "allow_dml": False,
        "extra": "{}",
    }
    return int(client.post("/api/v1/database/", payload)["id"])


def ensure_dataset(client: SupersetClient, database_id: int) -> int:
    existing = find_result(client.get("/api/v1/dataset/?q=(page_size:100)"), "table_name", DATASET_TABLE)
    if existing and existing.get("schema") == DATASET_SCHEMA:
        return int(existing["id"])
    payload = {
        "database": database_id,
        "schema": DATASET_SCHEMA,
        "table_name": DATASET_TABLE,
        "owners": [1],
    }
    result = client.post("/api/v1/dataset/", payload)
    return int(result.get("id") or result["data"]["id"])


def refresh_dataset(client: SupersetClient, dataset_id: int) -> None:
    detail = client.get(f"/api/v1/dataset/{dataset_id}")["result"]
    column_names = {column["column_name"] for column in detail.get("columns", [])}
    required = {"primary_state_route", "route_scope", "review_score_group", "is_low_review"}
    if not required.issubset(column_names):
        client.put(f"/api/v1/dataset/{dataset_id}/refresh", {})


def ensure_dashboard(client: SupersetClient) -> int:
    existing = find_result(client.get("/api/v1/dashboard/?q=(page_size:100)"), "slug", DASHBOARD_SLUG)
    base_payload = {
        "dashboard_title": DASHBOARD_TITLE,
        "slug": DASHBOARD_SLUG,
        "published": True,
        "owners": [1],
        "position_json": "{}",
        "json_metadata": json.dumps({"native_filter_configuration": []}),
    }
    if existing:
        dashboard_id = int(existing["id"])
        client.put(f"/api/v1/dashboard/{dashboard_id}", base_payload)
        return dashboard_id
    return int(client.post("/api/v1/dashboard/", base_payload)["id"])


def ensure_charts(
    client: SupersetClient, dataset_id: int, dashboard_id: int
) -> list[dict[str, Any]]:
    existing_rows = client.get("/api/v1/chart/?q=(page_size:100)").get("result", [])
    existing_by_name = {row["slice_name"]: row for row in existing_rows}
    charts: list[dict[str, Any]] = []
    for definition in chart_definitions(dataset_id):
        payload = {
            "slice_name": definition["name"],
            "description": definition["description"],
            "viz_type": definition["viz_type"],
            "datasource_id": dataset_id,
            "datasource_type": "table",
            "owners": [1],
            "dashboards": [dashboard_id],
            "params": json.dumps(definition["params"], ensure_ascii=False),
            "query_context": None,
        }
        existing = existing_by_name.get(definition["name"])
        if existing:
            chart_id = int(existing["id"])
            client.put(f"/api/v1/chart/{chart_id}", payload)
        else:
            chart_id = int(client.post("/api/v1/chart/", payload)["id"])
        detail = client.get(f"/api/v1/chart/{chart_id}")["result"]
        charts.append({"id": chart_id, "uuid": detail["uuid"], "name": definition["name"]})
        print(f"chart {chart_id}: {definition['name']}")
    return charts


def dashboard_position(charts: list[dict[str, Any]]) -> dict[str, Any]:
    chart_by_name = {chart["name"]: chart for chart in charts}
    pages = [
        (
            "Tổng quan điều hành",
            [
                [
                    ("KPI - Tổng số đơn", 2, 22),
                    ("KPI - Số đơn đã giao", 2, 22),
                    ("KPI - Tỷ lệ giao đúng hạn", 2, 22),
                    ("KPI - Thời gian giao TB (ngày)", 3, 22),
                    ("KPI - Tổng phí vận chuyển", 3, 22),
                ],
                [
                    ("Xu hướng sản lượng theo tháng", 7, 48),
                    ("Xu hướng tỷ lệ giao đúng hạn", 5, 48),
                ],
            ],
        ),
        (
            "Hiệu quả giao hàng",
            [
                [
                    ("KPI - Số đơn giao trễ", 6, 22),
                    ("KPI - Số ngày trễ TB", 6, 22),
                ],
                [
                    ("Cơ cấu trạng thái đơn hàng", 6, 44),
                    ("Nhóm số ngày trễ", 6, 44),
                ],
                [
                    ("Phân bố thời gian giao hàng", 6, 48),
                    ("Xu hướng thời gian giao trung bình", 6, 48),
                ],
            ],
        ),
        (
            "Mạng lưới gửi–nhận",
            [
                [
                    ("Sản lượng theo vùng nhận", 4, 42),
                    ("Sản lượng theo vùng gửi chính", 4, 42),
                    ("Hiệu quả nội bang và liên bang", 4, 42),
                ],
                [
                    ("Tỷ lệ giao trễ theo bang nhận", 6, 48),
                    ("Sản lượng theo bang gửi chính", 6, 48),
                ],
                [
                    ("Top tuyến bang gửi - nhận theo sản lượng", 6, 52),
                    ("Tỷ lệ trễ theo tuyến trọng yếu", 6, 52),
                ],
            ],
        ),
        (
            "Chất lượng dịch vụ",
            [
                [
                    ("KPI - Điểm đánh giá trung bình", 6, 22),
                    ("KPI - Tỷ lệ đánh giá thấp", 6, 22),
                ],
                [
                    ("Cơ cấu nhóm điểm đánh giá", 6, 44),
                    ("Điểm đánh giá theo tình trạng giao hàng", 6, 44),
                ],
                [
                    ("Điểm đánh giá theo nhóm ngày trễ", 6, 48),
                    ("Tỷ lệ đánh giá thấp theo tình trạng giao", 6, 48),
                ],
                [
                    ("Tỷ lệ đánh giá thấp theo bang nhận", 12, 48),
                ],
            ],
        ),
    ]
    layout: dict[str, Any] = {
        "DASHBOARD_VERSION_KEY": "v2",
        "ROOT_ID": {"id": "ROOT_ID", "type": "ROOT", "children": ["TABS-ROOT"]},
        "TABS-ROOT": {
            "id": "TABS-ROOT",
            "type": "TABS",
            "children": [],
            "parents": ["ROOT_ID"],
            "meta": {},
        },
        "HEADER_ID": {
            "id": "HEADER_ID",
            "type": "HEADER",
            "meta": {"text": DASHBOARD_TITLE},
        },
    }
    for page_number, (page_title, rows) in enumerate(pages, start=1):
        tab_id = f"TAB-{page_number}"
        layout["TABS-ROOT"]["children"].append(tab_id)
        layout[tab_id] = {
            "id": tab_id,
            "type": "TAB",
            "children": [],
            "parents": ["ROOT_ID", "TABS-ROOT"],
            "meta": {"text": page_title, "defaultText": page_title},
        }
        for row_number, row in enumerate(rows, start=1):
            row_id = f"ROW-{page_number}-{row_number}"
            layout[tab_id]["children"].append(row_id)
            layout[row_id] = {
                "id": row_id,
                "type": "ROW",
                "children": [],
                "parents": ["ROOT_ID", "TABS-ROOT", tab_id],
                "meta": {"background": "BACKGROUND_TRANSPARENT"},
            }
            for chart_name, width, height in row:
                chart = chart_by_name[chart_name]
                chart_node = f"CHART-{chart['id']}"
                layout[row_id]["children"].append(chart_node)
                layout[chart_node] = {
                    "id": chart_node,
                    "type": "CHART",
                    "children": [],
                    "parents": ["ROOT_ID", "TABS-ROOT", tab_id, row_id],
                    "meta": {
                        "chartId": chart["id"],
                        "height": height,
                        "width": width,
                        "sliceName": chart["name"],
                        "uuid": chart["uuid"],
                    },
                }
    return layout


def native_filter(
    filter_id: str, name: str, filter_type: str, column: str, dataset_id: int
) -> dict[str, Any]:
    control_values = {"enableEmptyFilter": False}
    if filter_type == "filter_select":
        control_values.update(
            {"multiSelect": True, "searchAllOptions": True, "inverseSelection": False}
        )
    return {
        "id": filter_id,
        "controlValues": control_values,
        "name": name,
        "filterType": filter_type,
        "targets": [{"column": {"name": column}, "datasetId": dataset_id}],
        "defaultDataMask": {"extraFormData": {}, "filterState": {}, "ownState": {}},
        "cascadeParentIds": [],
        "scope": {"rootPath": ["ROOT_ID"], "excluded": []},
        "type": "NATIVE_FILTER",
        "description": "",
    }


def update_dashboard(
    client: SupersetClient,
    dashboard_id: int,
    dataset_id: int,
    charts: list[dict[str, Any]],
) -> None:
    metadata = {
        "timed_refresh_immune_slices": [],
        "expanded_slices": {},
        "refresh_frequency": 0,
        "default_filters": "{}",
        "color_scheme": "supersetColors",
        "label_colors": {},
        "shared_label_colors": {},
        "map_label_colors": {},
        "cross_filters_enabled": True,
        "native_filter_configuration": [
            native_filter("NATIVE_FILTER-time", "Thời gian đặt hàng", "filter_time", "purchased_at", dataset_id),
            native_filter("NATIVE_FILTER-receiver-region", "Vùng nhận", "filter_select", "receiver_macro_region", dataset_id),
            native_filter("NATIVE_FILTER-receiver-state", "Bang nhận", "filter_select", "receiver_state", dataset_id),
            native_filter("NATIVE_FILTER-sender-region", "Vùng gửi chính", "filter_select", "primary_sender_macro_region", dataset_id),
        ],
    }
    payload = {
        "dashboard_title": DASHBOARD_TITLE,
        "slug": DASHBOARD_SLUG,
        "published": True,
        "owners": [1],
        "position_json": json.dumps(dashboard_position(charts), ensure_ascii=False),
        "json_metadata": json.dumps(metadata, ensure_ascii=False),
        "css": """
.dashboard-component-chart-holder { border-radius: 8px; }
.dashboard-header .dashboard-component-header { font-weight: 650; }
""".strip(),
    }
    client.put(f"/api/v1/dashboard/{dashboard_id}", payload)


def main() -> None:
    client = SupersetClient()
    database_id = ensure_database(client)
    dataset_id = ensure_dataset(client, database_id)
    refresh_dataset(client, dataset_id)
    dashboard_id = ensure_dashboard(client)
    charts = ensure_charts(client, dataset_id, dashboard_id)
    update_dashboard(client, dashboard_id, dataset_id, charts)
    artifact_dir = Path(__file__).resolve().parents[1] / "artifacts"
    artifact_dir.mkdir(parents=True, exist_ok=True)
    export_path = artifact_dir / "olist_superset_dashboard_export.zip"
    export_path.write_bytes(client.get_bytes(f"/api/v1/dashboard/export/?q=!({dashboard_id})"))
    print(f"database_id={database_id}")
    print(f"dataset_id={dataset_id}")
    print(f"dashboard_id={dashboard_id}")
    print(f"dashboard_url={BASE_URL}/superset/dashboard/{DASHBOARD_SLUG}/")
    print(f"dashboard_export={export_path}")


if __name__ == "__main__":
    main()
