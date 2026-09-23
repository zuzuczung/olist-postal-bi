\pset pager off
\echo 'MULTI-PAGE DASHBOARD RECONCILIATION'

\echo 'SERVICE QUALITY KPI'
SELECT
    count(*) FILTER (WHERE review_count > 0) AS reviewed_orders,
    round(avg(avg_review_score) FILTER (WHERE review_count > 0), 2) AS avg_review_score,
    count(*) FILTER (WHERE is_low_review) AS low_review_orders,
    round(
        100.0 * count(*) FILTER (WHERE is_low_review)
        / nullif(count(*) FILTER (WHERE is_low_review IS NOT NULL), 0),
        2
    ) AS low_review_rate_pct
FROM analytics.fact_order;

\echo 'WITHIN-STATE / INTERSTATE PERFORMANCE'
SELECT
    route_scope,
    count(*) AS orders,
    count(*) FILTER (WHERE is_on_time IS NOT NULL) AS on_time_eligible_orders,
    count(*) FILTER (WHERE is_on_time = false) AS late_orders,
    round(
        100.0 * count(*) FILTER (WHERE is_on_time = false)
        / nullif(count(*) FILTER (WHERE is_on_time IS NOT NULL), 0),
        2
    ) AS late_rate_pct
FROM analytics.fact_order
GROUP BY route_scope
ORDER BY orders DESC;

\echo 'TOP PRIMARY STATE ROUTES BY VOLUME'
SELECT
    primary_state_route,
    count(*) AS orders,
    count(*) FILTER (WHERE is_on_time = false) AS late_orders,
    round(
        100.0 * count(*) FILTER (WHERE is_on_time = false)
        / nullif(count(*) FILTER (WHERE is_on_time IS NOT NULL), 0),
        2
    ) AS late_rate_pct,
    round(avg(delivery_days) FILTER (WHERE is_delivered), 2) AS avg_delivery_days
FROM analytics.fact_order
WHERE primary_state_route <> 'Unknown route'
GROUP BY primary_state_route
HAVING count(*) FILTER (WHERE is_on_time IS NOT NULL) >= 100
ORDER BY orders DESC
LIMIT 10;

\echo 'REVIEW SCORE GROUPS'
SELECT review_score_group, count(*) AS orders
FROM analytics.fact_order
GROUP BY review_score_group
ORDER BY orders DESC;
