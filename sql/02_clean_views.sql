-- =============================================================
-- 02_clean_views.sql
-- Clean layer: views on top of the raw schema.
-- All analysis (cohorts, RFM, CLV, Power BI) reads from these
-- views, never from raw tables. See docs/decisions.md.
--
-- Run from the repository root:
--   psql -U postgres -d olist -f sql/02_clean_views.sql
-- Re-runnable: drops and recreates the clean schema.
-- =============================================================

DROP SCHEMA IF EXISTS clean CASCADE;
CREATE SCHEMA clean;


-- -------------------------------------------------------------
-- clean.orders
-- Delivered orders with a delivery date, purchased between
-- 2017-01-01 and 2018-08-31, linked to the real customer
-- (customer_unique_id), with delivery metrics.
-- Check: 96,203 orders | 93,096 customers | 6.8% late
-- -------------------------------------------------------------
CREATE VIEW clean.orders AS
SELECT o.order_id,
       c.customer_unique_id,
       c.customer_state,
       o.order_purchase_timestamp                AS purchased_at,
       o.order_purchase_timestamp::date          AS purchase_date,
       o.order_estimated_delivery_date::date     AS estimated_date,
       o.order_delivered_customer_date::date     AS delivered_date,
       o.order_delivered_customer_date::date
         - o.order_purchase_timestamp::date      AS delivery_days,
       o.order_delivered_customer_date::date
         - o.order_estimated_delivery_date::date AS days_late,
       o.order_delivered_customer_date::date
         > o.order_estimated_delivery_date::date AS is_late
FROM raw.orders o
JOIN raw.customers c ON c.customer_id = o.customer_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_purchase_timestamp >= '2017-01-01'
  AND o.order_purchase_timestamp <  '2018-09-01';


-- -------------------------------------------------------------
-- clean.order_reviews
-- One review per order: the most recent one.
-- Check: 98,673 rows = 98,673 orders (551 duplicates removed)
-- -------------------------------------------------------------
CREATE VIEW clean.order_reviews AS
WITH ranked AS (
    SELECT order_id,
           review_score,
           review_creation_date,
           ROW_NUMBER() OVER (
               PARTITION BY order_id
               ORDER BY review_creation_date DESC, review_answer_timestamp DESC
           ) AS rn
    FROM raw.order_reviews
)
SELECT order_id,
       review_score,
       review_creation_date AS reviewed_at
FROM ranked
WHERE rn = 1;


-- -------------------------------------------------------------
-- clean.order_items
-- One row per item sold, with the product category in English.
-- Falls back to the Portuguese name, then 'unknown'.
-- Check: 112,650 rows (same as raw: LEFT JOINs lose nothing)
-- -------------------------------------------------------------
CREATE VIEW clean.order_items AS
SELECT i.order_id,
       i.order_item_id,
       i.product_id,
       i.seller_id,
       COALESCE(t.product_category_name_english,
                p.product_category_name,
                'unknown')                AS category,
       i.price,
       i.freight_value                     AS freight
FROM raw.order_items i
LEFT JOIN raw.products p
       ON p.product_id = i.product_id
LEFT JOIN raw.category_translation t
       ON t.product_category_name = p.product_category_name;


-- -------------------------------------------------------------
-- clean.order_facts
-- Analysis-ready table: one row per order in clean.orders, with
-- order value (BRL), review score and the order's position in
-- the customer's purchase history (customer_order_seq).
-- Items are aggregated BEFORE joining to avoid duplicating orders.
-- Check: 96,203 orders | 95,560 with review | avg value 159.78 BRL
--        | 3,107 repeat orders (= 96,203 orders - 93,096 customers)
-- -------------------------------------------------------------
CREATE VIEW clean.order_facts AS
WITH item_totals AS (
    SELECT order_id,
           COUNT(*)     AS n_items,
           SUM(price)   AS items_value,
           SUM(freight) AS freight_value
    FROM clean.order_items
    GROUP BY order_id
)
SELECT o.order_id,
       o.customer_unique_id,
       o.customer_state,
       o.purchased_at,
       o.purchase_date,
       o.estimated_date,
       o.delivered_date,
       o.delivery_days,
       o.days_late,
       o.is_late,
       it.n_items,
       it.items_value,
       it.freight_value,
       it.items_value + it.freight_value AS order_value,
       r.review_score,
       ROW_NUMBER() OVER (
           PARTITION BY o.customer_unique_id
           ORDER BY o.purchased_at
       ) AS customer_order_seq
FROM clean.orders o
JOIN item_totals it             ON it.order_id = o.order_id
LEFT JOIN clean.order_reviews r ON r.order_id = o.order_id;
