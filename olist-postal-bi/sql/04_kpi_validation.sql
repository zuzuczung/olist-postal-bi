\pset pager off
\echo 'DASHBOARD KPI RECONCILIATION'
SELECT
    count(*) AS total_orders,
    count(*) FILTER (WHERE is_delivered) AS delivered_orders,
    count(*) FILTER (WHERE is_on_time IS NOT NULL) AS on_time_denominator,
    count(*) FILTER (WHERE is_on_time) AS on_time_orders,
    round(100.0 * count(*) FILTER (WHERE is_on_time) / nullif(count(*) FILTER (WHERE is_on_time IS NOT NULL), 0), 2) AS on_time_rate_pct,
    count(*) FILTER (WHERE is_on_time = false) AS late_orders,
    round(avg(delivery_days) FILTER (WHERE is_delivered), 2) AS avg_delivery_days,
    round(avg(late_days) FILTER (WHERE is_on_time = false), 2) AS avg_late_days_among_late,
    round(sum(freight_value), 2) AS total_freight_value,
    round(avg(avg_review_score) FILTER (WHERE review_count > 0), 2) AS avg_order_review_score
FROM analytics.fact_order;

\echo 'FACT GRAIN / AGGREGATION SAFETY'
SELECT
    (SELECT count(*) FROM staging.orders) AS staging_orders,
    count(*) AS fact_rows,
    count(DISTINCT order_id) AS distinct_fact_orders,
    count(*) - count(DISTINCT order_id) AS duplicate_fact_orders,
    (SELECT round(sum(nullif(freight_value, '')::numeric), 2) FROM staging.order_items) AS staging_freight,
    round(sum(freight_value), 2) AS fact_freight
FROM analytics.fact_order;

\echo 'TOP RECEIVER STATES BY ORDER VOLUME'
SELECT receiver_state, order_count, delivered_order_count, on_time_eligible_count, late_order_count, late_rate_pct
FROM analytics.v_receiver_region_kpis
ORDER BY order_count DESC
LIMIT 10;

\echo 'REVIEW SCORE BY DELIVERY PERFORMANCE'
SELECT
    delivery_performance_status,
    count(*) AS orders,
    count(*) FILTER (WHERE review_count > 0) AS reviewed_orders,
    round(avg(avg_review_score) FILTER (WHERE review_count > 0), 2) AS avg_review_score
FROM analytics.fact_order
GROUP BY delivery_performance_status
ORDER BY orders DESC;

