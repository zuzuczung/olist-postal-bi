BEGIN;

DROP SCHEMA IF EXISTS analytics CASCADE;
CREATE SCHEMA analytics;

CREATE TABLE analytics.dim_date AS
WITH bounds AS (
    SELECT
        min(nullif(order_purchase_timestamp, '')::date) AS min_date,
        max(GREATEST(
            nullif(order_purchase_timestamp, '')::date,
            nullif(order_delivered_customer_date, '')::date,
            nullif(order_estimated_delivery_date, '')::date
        )) AS max_date
    FROM staging.orders
)
SELECT
    to_char(d::date, 'YYYYMMDD')::integer AS date_key,
    d::date AS date_day,
    extract(year FROM d)::smallint AS year,
    extract(quarter FROM d)::smallint AS quarter,
    extract(month FROM d)::smallint AS month_number,
    to_char(d, 'YYYY-MM') AS year_month,
    date_trunc('month', d)::date AS month_start,
    trim(to_char(d, 'Month')) AS month_name,
    extract(isodow FROM d)::smallint AS iso_day_of_week,
    trim(to_char(d, 'Day')) AS day_name,
    extract(isodow FROM d) IN (6, 7) AS is_weekend
FROM bounds
CROSS JOIN LATERAL generate_series(min_date, max_date, interval '1 day') d;
ALTER TABLE analytics.dim_date ADD PRIMARY KEY (date_key);
CREATE UNIQUE INDEX dim_date_day_uq ON analytics.dim_date (date_day);

CREATE TABLE analytics.dim_region AS
WITH states AS (
    SELECT customer_state AS state_code, customer_city AS city FROM staging.customers
    UNION
    SELECT seller_state, seller_city FROM staging.sellers
)
SELECT
    row_number() OVER (ORDER BY state_code, city)::integer AS region_key,
    state_code,
    city,
    CASE
        WHEN state_code IN ('AC','AP','AM','PA','RO','RR','TO') THEN 'North'
        WHEN state_code IN ('AL','BA','CE','MA','PB','PE','PI','RN','SE') THEN 'Northeast'
        WHEN state_code IN ('DF','GO','MT','MS') THEN 'Central-West'
        WHEN state_code IN ('ES','MG','RJ','SP') THEN 'Southeast'
        WHEN state_code IN ('PR','RS','SC') THEN 'South'
        ELSE 'Unknown'
    END AS macro_region
FROM states
WHERE nullif(state_code, '') IS NOT NULL AND nullif(city, '') IS NOT NULL;
ALTER TABLE analytics.dim_region ADD PRIMARY KEY (region_key);
CREATE UNIQUE INDEX dim_region_state_city_uq ON analytics.dim_region (state_code, city);

CREATE TABLE analytics.order_sender_region_bridge AS
WITH state_detail AS (
    SELECT
        i.order_id,
        s.seller_state AS sender_state,
        count(*)::integer AS item_count,
        count(DISTINCT i.seller_id)::integer AS seller_count,
        sum(nullif(i.freight_value, '')::numeric(14,2)) AS freight_value
    FROM staging.order_items i
    LEFT JOIN staging.sellers s USING (seller_id)
    GROUP BY i.order_id, s.seller_state
), weighted AS (
    SELECT
        *,
        count(*) OVER (PARTITION BY order_id)::integer AS sender_state_count
    FROM state_detail
)
SELECT
    order_id,
    sender_state,
    item_count,
    seller_count,
    freight_value,
    sender_state_count,
    1.0::numeric / sender_state_count AS allocated_order_weight
FROM weighted;
CREATE INDEX order_sender_region_bridge_order_idx ON analytics.order_sender_region_bridge(order_id);
CREATE INDEX order_sender_region_bridge_state_idx ON analytics.order_sender_region_bridge(sender_state);

CREATE TABLE analytics.fact_order AS
WITH orders_typed AS (
    SELECT
        order_id,
        customer_id,
        order_status,
        nullif(order_purchase_timestamp, '')::timestamp AS purchased_at,
        nullif(order_approved_at, '')::timestamp AS approved_at,
        nullif(order_delivered_carrier_date, '')::timestamp AS carrier_handoff_at,
        nullif(order_delivered_customer_date, '')::timestamp AS delivered_at,
        nullif(order_estimated_delivery_date, '')::timestamp AS estimated_delivery_at
    FROM staging.orders
), item_order AS (
    SELECT
        order_id,
        count(*)::integer AS item_count,
        count(DISTINCT seller_id)::integer AS seller_count,
        sum(nullif(price, '')::numeric(14,2)) AS product_value,
        sum(nullif(freight_value, '')::numeric(14,2)) AS freight_value
    FROM staging.order_items
    GROUP BY order_id
), sender_ranked AS (
    SELECT
        b.*,
        row_number() OVER (
            PARTITION BY b.order_id
            ORDER BY b.item_count DESC, b.freight_value DESC NULLS LAST, b.sender_state NULLS LAST
        ) AS state_rank
    FROM analytics.order_sender_region_bridge b
), review_ranked AS (
    SELECT
        order_id,
        nullif(review_score, '')::numeric(4,2) AS review_score,
        row_number() OVER (
            PARTITION BY order_id
            ORDER BY nullif(review_answer_timestamp, '')::timestamp DESC NULLS LAST, review_id DESC
        ) AS recency_rank
    FROM staging.order_reviews
), review_order AS (
    SELECT
        order_id,
        count(*)::integer AS review_count,
        avg(review_score)::numeric(4,2) AS avg_review_score,
        max(review_score) FILTER (WHERE recency_rank = 1)::numeric(4,2) AS latest_review_score
    FROM review_ranked
    GROUP BY order_id
)
SELECT
    o.order_id,
    o.customer_id,
    c.customer_unique_id,
    o.order_status,
    o.purchased_at,
    o.approved_at,
    o.carrier_handoff_at,
    o.delivered_at,
    o.estimated_delivery_at,
    to_char(o.purchased_at::date, 'YYYYMMDD')::integer AS purchase_date_key,
    CASE WHEN o.delivered_at IS NOT NULL THEN to_char(o.delivered_at::date, 'YYYYMMDD')::integer END AS delivery_date_key,
    CASE WHEN o.estimated_delivery_at IS NOT NULL THEN to_char(o.estimated_delivery_at::date, 'YYYYMMDD')::integer END AS estimated_delivery_date_key,
    c.customer_zip_code_prefix AS receiver_zip_prefix,
    c.customer_city AS receiver_city,
    c.customer_state AS receiver_state,
    CASE
        WHEN c.customer_state IN ('AC','AP','AM','PA','RO','RR','TO') THEN 'North'
        WHEN c.customer_state IN ('AL','BA','CE','MA','PB','PE','PI','RN','SE') THEN 'Northeast'
        WHEN c.customer_state IN ('DF','GO','MT','MS') THEN 'Central-West'
        WHEN c.customer_state IN ('ES','MG','RJ','SP') THEN 'Southeast'
        WHEN c.customer_state IN ('PR','RS','SC') THEN 'South'
        ELSE 'Unknown'
    END AS receiver_macro_region,
    sr.sender_state AS primary_sender_state,
    CASE
        WHEN sr.sender_state IN ('AC','AP','AM','PA','RO','RR','TO') THEN 'North'
        WHEN sr.sender_state IN ('AL','BA','CE','MA','PB','PE','PI','RN','SE') THEN 'Northeast'
        WHEN sr.sender_state IN ('DF','GO','MT','MS') THEN 'Central-West'
        WHEN sr.sender_state IN ('ES','MG','RJ','SP') THEN 'Southeast'
        WHEN sr.sender_state IN ('PR','RS','SC') THEN 'South'
        ELSE 'Unknown'
    END AS primary_sender_macro_region,
    CASE
        WHEN nullif(sr.sender_state, '') IS NULL OR nullif(c.customer_state, '') IS NULL THEN 'Unknown route'
        ELSE sr.sender_state || ' → ' || c.customer_state
    END AS primary_state_route,
    CASE
        WHEN nullif(sr.sender_state, '') IS NULL OR nullif(c.customer_state, '') IS NULL THEN 'Unknown'
        WHEN sr.sender_state = c.customer_state THEN 'Within-state'
        ELSE 'Interstate'
    END AS route_scope,
    coalesce(sr.sender_state_count, 0) AS sender_state_count,
    coalesce(sr.sender_state_count, 0) > 1 AS is_multi_sender_state,
    coalesce(io.seller_count, 0) AS seller_count,
    coalesce(io.item_count, 0) AS item_count,
    io.product_value,
    io.freight_value,
    coalesce(ro.review_count, 0) AS review_count,
    ro.avg_review_score,
    ro.latest_review_score,
    CASE
        WHEN ro.avg_review_score IS NULL THEN 'No review'
        WHEN ro.avg_review_score <= 2 THEN 'Low (1-2)'
        WHEN ro.avg_review_score < 4 THEN 'Neutral (3)'
        ELSE 'Positive (4-5)'
    END AS review_score_group,
    CASE WHEN ro.avg_review_score IS NOT NULL THEN ro.avg_review_score <= 2 END AS is_low_review,
    true AS is_order,
    (o.order_status = 'delivered' AND o.delivered_at IS NOT NULL) AS is_delivered,
    CASE
        WHEN o.order_status = 'delivered' AND o.delivered_at IS NOT NULL AND o.estimated_delivery_at IS NOT NULL
        THEN o.delivered_at::date <= o.estimated_delivery_at::date
    END AS is_on_time,
    CASE
        WHEN o.order_status = 'delivered' AND o.delivered_at IS NOT NULL
        THEN round((extract(epoch FROM (o.delivered_at - o.purchased_at)) / 86400.0)::numeric, 2)
    END AS delivery_days,
    CASE
        WHEN o.order_status = 'delivered' AND o.delivered_at IS NOT NULL AND o.estimated_delivery_at IS NOT NULL
        THEN o.delivered_at::date - o.estimated_delivery_at::date
    END AS delivery_vs_estimated_days,
    CASE
        WHEN o.order_status = 'delivered' AND o.delivered_at IS NOT NULL AND o.estimated_delivery_at IS NOT NULL
        THEN greatest(o.delivered_at::date - o.estimated_delivery_at::date, 0)
    END AS late_days,
    CASE
        WHEN o.order_status IN ('canceled', 'unavailable') THEN 'Canceled/unavailable'
        WHEN o.order_status <> 'delivered' THEN 'Not delivered'
        WHEN o.delivered_at IS NULL THEN 'Delivered status, missing actual time'
        WHEN o.estimated_delivery_at IS NULL THEN 'Delivered, missing estimate'
        WHEN o.delivered_at::date <= o.estimated_delivery_at::date THEN 'Delivered on time'
        ELSE 'Delivered late'
    END AS delivery_performance_status,
    CASE
        WHEN o.order_status <> 'delivered' OR o.delivered_at IS NULL OR o.estimated_delivery_at IS NULL THEN 'Not eligible'
        WHEN o.delivered_at::date <= o.estimated_delivery_at::date THEN 'On time'
        WHEN o.delivered_at::date - o.estimated_delivery_at::date BETWEEN 1 AND 3 THEN 'Late 1-3 days'
        WHEN o.delivered_at::date - o.estimated_delivery_at::date BETWEEN 4 AND 7 THEN 'Late 4-7 days'
        WHEN o.delivered_at::date - o.estimated_delivery_at::date BETWEEN 8 AND 14 THEN 'Late 8-14 days'
        ELSE 'Late 15+ days'
    END AS late_day_bucket
FROM orders_typed o
LEFT JOIN staging.customers c USING (customer_id)
LEFT JOIN item_order io USING (order_id)
LEFT JOIN sender_ranked sr ON sr.order_id = o.order_id AND sr.state_rank = 1
LEFT JOIN review_order ro ON ro.order_id = o.order_id;

ALTER TABLE analytics.fact_order ADD PRIMARY KEY (order_id);
CREATE INDEX fact_order_purchased_idx ON analytics.fact_order(purchased_at);
CREATE INDEX fact_order_receiver_state_idx ON analytics.fact_order(receiver_state);
CREATE INDEX fact_order_sender_state_idx ON analytics.fact_order(primary_sender_state);
CREATE INDEX fact_order_route_idx ON analytics.fact_order(primary_state_route);
CREATE INDEX fact_order_performance_idx ON analytics.fact_order(delivery_performance_status);

ALTER TABLE analytics.fact_order
    ADD CONSTRAINT fact_order_purchase_date_fk FOREIGN KEY (purchase_date_key) REFERENCES analytics.dim_date(date_key),
    ADD CONSTRAINT fact_order_delivery_date_fk FOREIGN KEY (delivery_date_key) REFERENCES analytics.dim_date(date_key),
    ADD CONSTRAINT fact_order_estimated_date_fk FOREIGN KEY (estimated_delivery_date_key) REFERENCES analytics.dim_date(date_key);

CREATE VIEW analytics.v_order_analysis AS
SELECT * FROM analytics.fact_order;

CREATE VIEW analytics.v_monthly_kpis AS
SELECT
    date_trunc('month', purchased_at)::date AS month_start,
    count(*) AS order_count,
    count(*) FILTER (WHERE is_delivered) AS delivered_order_count,
    count(*) FILTER (WHERE is_on_time IS NOT NULL) AS on_time_eligible_count,
    count(*) FILTER (WHERE is_on_time) AS on_time_order_count,
    round(100.0 * count(*) FILTER (WHERE is_on_time) / nullif(count(*) FILTER (WHERE is_on_time IS NOT NULL), 0), 2) AS on_time_rate_pct,
    round(avg(delivery_days) FILTER (WHERE is_delivered), 2) AS avg_delivery_days,
    sum(freight_value) AS freight_value
FROM analytics.fact_order
GROUP BY 1;

CREATE VIEW analytics.v_receiver_region_kpis AS
SELECT
    receiver_state,
    receiver_macro_region,
    count(*) AS order_count,
    count(*) FILTER (WHERE is_delivered) AS delivered_order_count,
    count(*) FILTER (WHERE is_on_time IS NOT NULL) AS on_time_eligible_count,
    count(*) FILTER (WHERE is_on_time = false) AS late_order_count,
    round(100.0 * count(*) FILTER (WHERE is_on_time = false) / nullif(count(*) FILTER (WHERE is_on_time IS NOT NULL), 0), 2) AS late_rate_pct,
    round(avg(delivery_days) FILTER (WHERE is_delivered), 2) AS avg_delivery_days,
    sum(freight_value) AS freight_value,
    round(avg(avg_review_score), 2) AS avg_review_score
FROM analytics.fact_order
GROUP BY receiver_state, receiver_macro_region;

CREATE VIEW analytics.v_sender_region_volume AS
SELECT
    b.sender_state,
    CASE
        WHEN b.sender_state IN ('AC','AP','AM','PA','RO','RR','TO') THEN 'North'
        WHEN b.sender_state IN ('AL','BA','CE','MA','PB','PE','PI','RN','SE') THEN 'Northeast'
        WHEN b.sender_state IN ('DF','GO','MT','MS') THEN 'Central-West'
        WHEN b.sender_state IN ('ES','MG','RJ','SP') THEN 'Southeast'
        WHEN b.sender_state IN ('PR','RS','SC') THEN 'South'
        ELSE 'Unknown'
    END AS sender_macro_region,
    sum(b.allocated_order_weight) AS allocated_order_volume,
    sum(b.item_count) AS item_count,
    sum(b.freight_value) AS freight_value
FROM analytics.order_sender_region_bridge b
GROUP BY b.sender_state;

GRANT USAGE ON SCHEMA analytics, staging TO olist_bi;
GRANT SELECT ON ALL TABLES IN SCHEMA analytics, staging TO olist_bi;

COMMIT;
