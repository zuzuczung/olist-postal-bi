\pset pager off
\echo 'ROW COUNTS'
SELECT * FROM (
    SELECT 'customers' AS table_name, count(*) AS row_count FROM staging.customers UNION ALL
    SELECT 'geolocation', count(*) FROM staging.geolocation UNION ALL
    SELECT 'order_items', count(*) FROM staging.order_items UNION ALL
    SELECT 'order_payments', count(*) FROM staging.order_payments UNION ALL
    SELECT 'order_reviews', count(*) FROM staging.order_reviews UNION ALL
    SELECT 'orders', count(*) FROM staging.orders UNION ALL
    SELECT 'products', count(*) FROM staging.products UNION ALL
    SELECT 'sellers', count(*) FROM staging.sellers UNION ALL
    SELECT 'product_category_translation', count(*) FROM staging.product_category_translation
) q ORDER BY table_name;

\echo 'DUPLICATE BUSINESS KEYS (extra rows beyond first)'
SELECT * FROM (
    SELECT 'customers.customer_id' AS key_name, count(*) - count(DISTINCT customer_id) AS duplicate_rows FROM staging.customers UNION ALL
    SELECT 'orders.order_id', count(*) - count(DISTINCT order_id) FROM staging.orders UNION ALL
    SELECT 'products.product_id', count(*) - count(DISTINCT product_id) FROM staging.products UNION ALL
    SELECT 'sellers.seller_id', count(*) - count(DISTINCT seller_id) FROM staging.sellers UNION ALL
    SELECT 'order_items.(order_id,order_item_id)', count(*) - count(DISTINCT (order_id, order_item_id)) FROM staging.order_items UNION ALL
    SELECT 'order_payments.(order_id,payment_sequential)', count(*) - count(DISTINCT (order_id, payment_sequential)) FROM staging.order_payments UNION ALL
    SELECT 'order_reviews.review_id', count(*) - count(DISTINCT review_id) FROM staging.order_reviews
) q ORDER BY key_name;

\echo 'UNMATCHED FOREIGN KEYS'
SELECT * FROM (
    SELECT 'orders -> customers' AS relationship, count(*) AS unmatched_rows
    FROM staging.orders o LEFT JOIN staging.customers c USING (customer_id) WHERE c.customer_id IS NULL
    UNION ALL
    SELECT 'order_items -> orders', count(*) FROM staging.order_items i LEFT JOIN staging.orders o USING (order_id) WHERE o.order_id IS NULL
    UNION ALL
    SELECT 'order_items -> sellers', count(*) FROM staging.order_items i LEFT JOIN staging.sellers s USING (seller_id) WHERE s.seller_id IS NULL
    UNION ALL
    SELECT 'order_items -> products', count(*) FROM staging.order_items i LEFT JOIN staging.products p USING (product_id) WHERE p.product_id IS NULL
    UNION ALL
    SELECT 'order_reviews -> orders', count(*) FROM staging.order_reviews r LEFT JOIN staging.orders o USING (order_id) WHERE o.order_id IS NULL
    UNION ALL
    SELECT 'order_payments -> orders', count(*) FROM staging.order_payments p LEFT JOIN staging.orders o USING (order_id) WHERE o.order_id IS NULL
) q ORDER BY relationship;

\echo 'ORDER STATUS DISTRIBUTION'
SELECT order_status, count(*) AS orders
FROM staging.orders
GROUP BY order_status
ORDER BY orders DESC, order_status;

\echo 'MISSING VALUES IN KEY BUSINESS FIELDS'
SELECT * FROM (
    SELECT 'orders.customer_id' AS field, count(*) FILTER (WHERE nullif(customer_id, '') IS NULL) AS missing FROM staging.orders UNION ALL
    SELECT 'orders.purchase_timestamp', count(*) FILTER (WHERE nullif(order_purchase_timestamp, '') IS NULL) FROM staging.orders UNION ALL
    SELECT 'orders.approved_at', count(*) FILTER (WHERE nullif(order_approved_at, '') IS NULL) FROM staging.orders UNION ALL
    SELECT 'orders.carrier_date', count(*) FILTER (WHERE nullif(order_delivered_carrier_date, '') IS NULL) FROM staging.orders UNION ALL
    SELECT 'orders.customer_delivery_date', count(*) FILTER (WHERE nullif(order_delivered_customer_date, '') IS NULL) FROM staging.orders UNION ALL
    SELECT 'orders.estimated_delivery_date', count(*) FILTER (WHERE nullif(order_estimated_delivery_date, '') IS NULL) FROM staging.orders UNION ALL
    SELECT 'order_items.freight_value', count(*) FILTER (WHERE nullif(freight_value, '') IS NULL) FROM staging.order_items UNION ALL
    SELECT 'reviews.review_score', count(*) FILTER (WHERE nullif(review_score, '') IS NULL) FROM staging.order_reviews UNION ALL
    SELECT 'customers.customer_state', count(*) FILTER (WHERE nullif(customer_state, '') IS NULL) FROM staging.customers UNION ALL
    SELECT 'sellers.seller_state', count(*) FILTER (WHERE nullif(seller_state, '') IS NULL) FROM staging.sellers
) q ORDER BY field;

\echo 'TIMESTAMP ANOMALIES'
WITH o AS (
    SELECT
        nullif(order_approved_at, '')::timestamp AS approved_at,
        nullif(order_purchase_timestamp, '')::timestamp AS purchased_at,
        nullif(order_delivered_carrier_date, '')::timestamp AS carrier_at,
        nullif(order_delivered_customer_date, '')::timestamp AS delivered_at,
        nullif(order_estimated_delivery_date, '')::timestamp AS estimated_at,
        order_status
    FROM staging.orders
)
SELECT * FROM (
    SELECT 'approved before purchase' AS anomaly, count(*) FILTER (WHERE approved_at < purchased_at) AS rows FROM o UNION ALL
    SELECT 'carrier handoff before purchase', count(*) FILTER (WHERE carrier_at < purchased_at) FROM o UNION ALL
    SELECT 'carrier handoff before approval', count(*) FILTER (WHERE carrier_at < approved_at) FROM o UNION ALL
    SELECT 'customer delivery before purchase', count(*) FILTER (WHERE delivered_at < purchased_at) FROM o UNION ALL
    SELECT 'customer delivery before carrier handoff', count(*) FILTER (WHERE delivered_at < carrier_at) FROM o UNION ALL
    SELECT 'estimated delivery before purchase', count(*) FILTER (WHERE estimated_at < purchased_at) FROM o UNION ALL
    SELECT 'delivered status missing actual delivery', count(*) FILTER (WHERE order_status = 'delivered' AND delivered_at IS NULL) FROM o UNION ALL
    SELECT 'non-delivered status with actual delivery', count(*) FILTER (WHERE order_status <> 'delivered' AND delivered_at IS NOT NULL) FROM o
) q ORDER BY anomaly;

\echo 'ORDERS WITH MULTIPLE REVIEWS / SELLERS / SENDER STATES'
SELECT
    (SELECT count(*) FROM (SELECT order_id FROM staging.order_reviews GROUP BY order_id HAVING count(*) > 1) x) AS orders_with_multiple_reviews,
    (SELECT count(*) FROM (SELECT order_id FROM staging.order_items GROUP BY order_id HAVING count(DISTINCT seller_id) > 1) x) AS orders_with_multiple_sellers,
    (SELECT count(*) FROM (
        SELECT i.order_id
        FROM staging.order_items i JOIN staging.sellers s USING (seller_id)
        GROUP BY i.order_id HAVING count(DISTINCT s.seller_state) > 1
    ) x) AS orders_with_multiple_sender_states;

