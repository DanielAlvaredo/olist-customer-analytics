-- =============================================================
-- 00_schema.sql
-- Creates the raw layer: one table per Olist CSV, loaded as-is.
-- Column names are kept identical to the source files (including
-- Olist's typos, e.g. "lenght") so loading is a 1:1 copy.
-- Renaming and cleaning happen later, in the clean layer (02_*).
-- Re-runnable: drops and recreates the raw schema.
-- =============================================================

DROP SCHEMA IF EXISTS raw CASCADE;
CREATE SCHEMA raw;

-- Customers: customer_id is per ORDER; customer_unique_id is the real person.
CREATE TABLE raw.customers (
    customer_id              TEXT PRIMARY KEY,
    customer_unique_id       TEXT NOT NULL,
    customer_zip_code_prefix TEXT,
    customer_city            TEXT,
    customer_state           CHAR(2)
);

CREATE TABLE raw.sellers (
    seller_id              TEXT PRIMARY KEY,
    seller_zip_code_prefix TEXT,
    seller_city            TEXT,
    seller_state           CHAR(2)
);

CREATE TABLE raw.products (
    product_id                 TEXT PRIMARY KEY,
    product_category_name      TEXT,
    product_name_lenght        INT,
    product_description_lenght INT,
    product_photos_qty         INT,
    product_weight_g           INT,
    product_length_cm          INT,
    product_height_cm          INT,
    product_width_cm           INT
);

CREATE TABLE raw.category_translation (
    product_category_name         TEXT PRIMARY KEY,
    product_category_name_english TEXT
);

CREATE TABLE raw.orders (
    order_id                      TEXT PRIMARY KEY,
    customer_id                   TEXT NOT NULL,
    order_status                  TEXT,
    order_purchase_timestamp      TIMESTAMP,
    order_approved_at             TIMESTAMP,
    order_delivered_carrier_date  TIMESTAMP,
    order_delivered_customer_date TIMESTAMP,
    order_estimated_delivery_date TIMESTAMP
);

CREATE TABLE raw.order_items (
    order_id            TEXT,
    order_item_id       INT,
    product_id          TEXT,
    seller_id           TEXT,
    shipping_limit_date TIMESTAMP,
    price               NUMERIC(10,2),
    freight_value       NUMERIC(10,2),
    PRIMARY KEY (order_id, order_item_id)
);

CREATE TABLE raw.order_payments (
    order_id             TEXT,
    payment_sequential   INT,
    payment_type         TEXT,
    payment_installments INT,
    payment_value        NUMERIC(10,2),
    PRIMARY KEY (order_id, payment_sequential)
);

-- No primary key on purpose: review_id is NOT unique in the source data.
-- This is a known data-quality issue, documented in docs/.
CREATE TABLE raw.order_reviews (
    review_id               TEXT,
    order_id                TEXT,
    review_score            SMALLINT,
    review_comment_title    TEXT,
    review_comment_message  TEXT,
    review_creation_date    TIMESTAMP,
    review_answer_timestamp TIMESTAMP
);

-- Many rows per zip prefix; no key. Only needed if we map customers.
CREATE TABLE raw.geolocation (
    geolocation_zip_code_prefix TEXT,
    geolocation_lat             DOUBLE PRECISION,
    geolocation_lng             DOUBLE PRECISION,
    geolocation_city            TEXT,
    geolocation_state           CHAR(2)
);
