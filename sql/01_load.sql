-- =============================================================
-- 01_load.sql
-- Loads the Olist CSVs into the raw schema, adds foreign keys
-- and prints row counts as a sanity check.
--
-- Run from the REPOSITORY ROOT (paths are relative to it):
--   psql -U postgres -d olist -f sql/01_load.sql
-- CSVs are expected in data/raw/ (unzipped Kaggle download).
-- =============================================================

\set ON_ERROR_STOP on
\encoding UTF8

TRUNCATE raw.customers, raw.sellers, raw.products, raw.category_translation,
         raw.orders, raw.order_items, raw.order_payments,
         raw.order_reviews, raw.geolocation;

-- Parent tables first, then tables that reference them.
\copy raw.customers            FROM 'data/raw/olist_customers_dataset.csv'          WITH (FORMAT csv, HEADER true)
\copy raw.sellers              FROM 'data/raw/olist_sellers_dataset.csv'            WITH (FORMAT csv, HEADER true)
\copy raw.products             FROM 'data/raw/olist_products_dataset.csv'           WITH (FORMAT csv, HEADER true)
\copy raw.category_translation FROM 'data/raw/product_category_name_translation.csv' WITH (FORMAT csv, HEADER true)
\copy raw.orders               FROM 'data/raw/olist_orders_dataset.csv'             WITH (FORMAT csv, HEADER true)
\copy raw.order_items          FROM 'data/raw/olist_order_items_dataset.csv'        WITH (FORMAT csv, HEADER true)
\copy raw.order_payments       FROM 'data/raw/olist_order_payments_dataset.csv'     WITH (FORMAT csv, HEADER true)
\copy raw.order_reviews        FROM 'data/raw/olist_order_reviews_dataset.csv'      WITH (FORMAT csv, HEADER true)
\copy raw.geolocation          FROM 'data/raw/olist_geolocation_dataset.csv'        WITH (FORMAT csv, HEADER true)

-- Foreign keys are added AFTER loading: faster, and if one fails
-- the data is already in and the error points to a real data issue.
-- (No FK from products to category_translation: some categories
--  have no English translation. We handle that in the clean layer.)
ALTER TABLE raw.orders
    ADD CONSTRAINT fk_orders_customer FOREIGN KEY (customer_id) REFERENCES raw.customers;
ALTER TABLE raw.order_items
    ADD CONSTRAINT fk_items_order   FOREIGN KEY (order_id)   REFERENCES raw.orders,
    ADD CONSTRAINT fk_items_product FOREIGN KEY (product_id) REFERENCES raw.products,
    ADD CONSTRAINT fk_items_seller  FOREIGN KEY (seller_id)  REFERENCES raw.sellers;
ALTER TABLE raw.order_payments
    ADD CONSTRAINT fk_payments_order FOREIGN KEY (order_id) REFERENCES raw.orders;
ALTER TABLE raw.order_reviews
    ADD CONSTRAINT fk_reviews_order FOREIGN KEY (order_id) REFERENCES raw.orders;

-- Indexes on the columns we will join and group by most.
CREATE INDEX ON raw.customers (customer_unique_id);
CREATE INDEX ON raw.orders (customer_id);
CREATE INDEX ON raw.orders (order_purchase_timestamp);
CREATE INDEX ON raw.order_reviews (order_id);

ANALYZE;

-- Sanity check: compare with the row counts listed on Kaggle.
SELECT 'customers' AS table_name, COUNT(*) AS n_rows FROM raw.customers
UNION ALL SELECT 'sellers',              COUNT(*) FROM raw.sellers
UNION ALL SELECT 'products',             COUNT(*) FROM raw.products
UNION ALL SELECT 'category_translation', COUNT(*) FROM raw.category_translation
UNION ALL SELECT 'orders',               COUNT(*) FROM raw.orders
UNION ALL SELECT 'order_items',          COUNT(*) FROM raw.order_items
UNION ALL SELECT 'order_payments',       COUNT(*) FROM raw.order_payments
UNION ALL SELECT 'order_reviews',        COUNT(*) FROM raw.order_reviews
UNION ALL SELECT 'geolocation',          COUNT(*) FROM raw.geolocation
ORDER BY table_name;
