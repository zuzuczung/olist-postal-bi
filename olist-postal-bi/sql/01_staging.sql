CREATE SCHEMA IF NOT EXISTS staging;

CREATE TABLE IF NOT EXISTS staging.customers (
    customer_id text,
    customer_unique_id text,
    customer_zip_code_prefix text,
    customer_city text,
    customer_state text
);

CREATE TABLE IF NOT EXISTS staging.geolocation (
    geolocation_zip_code_prefix text,
    geolocation_lat text,
    geolocation_lng text,
    geolocation_city text,
    geolocation_state text
);

CREATE TABLE IF NOT EXISTS staging.order_items (
    order_id text,
    order_item_id text,
    product_id text,
    seller_id text,
    shipping_limit_date text,
    price text,
    freight_value text
);

CREATE TABLE IF NOT EXISTS staging.order_payments (
    order_id text,
    payment_sequential text,
    payment_type text,
    payment_installments text,
    payment_value text
);

CREATE TABLE IF NOT EXISTS staging.order_reviews (
    review_id text,
    order_id text,
    review_score text,
    review_comment_title text,
    review_comment_message text,
    review_creation_date text,
    review_answer_timestamp text
);

CREATE TABLE IF NOT EXISTS staging.orders (
    order_id text,
    customer_id text,
    order_status text,
    order_purchase_timestamp text,
    order_approved_at text,
    order_delivered_carrier_date text,
    order_delivered_customer_date text,
    order_estimated_delivery_date text
);

CREATE TABLE IF NOT EXISTS staging.products (
    product_id text,
    product_category_name text,
    product_name_lenght text,
    product_description_lenght text,
    product_photos_qty text,
    product_weight_g text,
    product_length_cm text,
    product_height_cm text,
    product_width_cm text
);

CREATE TABLE IF NOT EXISTS staging.sellers (
    seller_id text,
    seller_zip_code_prefix text,
    seller_city text,
    seller_state text
);

CREATE TABLE IF NOT EXISTS staging.product_category_translation (
    product_category_name text,
    product_category_name_english text
);

CREATE TABLE IF NOT EXISTS staging.load_audit (
    load_audit_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    run_id uuid NOT NULL,
    loaded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    source_file text NOT NULL,
    target_table text NOT NULL,
    row_count bigint NOT NULL,
    file_sha256 text NOT NULL
);

