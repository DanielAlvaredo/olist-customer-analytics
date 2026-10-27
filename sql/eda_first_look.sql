-- =============================================================
-- eda_first_look.sql
-- First exploratory queries on the raw layer.
-- Goal: understand customers, order statuses and delivery delays
-- before building the clean layer.
-- Results noted in comments were obtained on the Kaggle dataset.
-- =============================================================


-- -------------------------------------------------------------
-- 1. Orders vs. real customers
-- customer_id is generated per ORDER; customer_unique_id is the person.
-- Result: 99,441 customer_ids vs 96,096 unique customers.
-- -------------------------------------------------------------
SELECT COUNT(DISTINCT customer_id)        AS customer_ids,
       COUNT(DISTINCT customer_unique_id) AS unique_customers
FROM raw.customers;


-- -------------------------------------------------------------
-- 2. Repeat purchase rate
-- Result: 3.12% of customers placed more than one order.
-- Note: includes all order statuses (cancelled too); will be
-- recomputed on delivered orders in the clean layer.
-- -------------------------------------------------------------
WITH orders_per_customer AS (
    SELECT customer_unique_id,
           COUNT(*) AS n_orders
    FROM raw.customers
    GROUP BY customer_unique_id
)
SELECT COUNT(*)                                                  AS customers,
       SUM(CASE WHEN n_orders > 1 THEN 1 ELSE 0 END)             AS repeat_customers,
       ROUND(100.0 * AVG(CASE WHEN n_orders > 1 THEN 1 ELSE 0 END), 2) AS pct_repeat
FROM orders_per_customer;


-- -------------------------------------------------------------
-- 3. Orders by status
-- Result: ~97% of orders are 'delivered'. Only these are used
-- for delay, retention and CLV analysis.
-- -------------------------------------------------------------
SELECT order_status,
       COUNT(*) AS n_orders
FROM raw.orders
GROUP BY order_status
ORDER BY n_orders DESC;


-- -------------------------------------------------------------
-- 4. Data quality: delivered orders without a delivery date
-- Result: 96,478 delivered, 96,470 with date -> 8 missing (excluded).
-- -------------------------------------------------------------
SELECT COUNT(*)                             AS delivered,
       COUNT(order_delivered_customer_date) AS with_delivery_date
FROM raw.orders
WHERE order_status = 'delivered';


-- -------------------------------------------------------------
-- 5. Share of late deliveries
-- Late = delivered on a later DAY than the estimated date.
-- Result: 6.8% of delivered orders arrive late.
-- -------------------------------------------------------------
SELECT COUNT(*) AS delivered,
       SUM(CASE WHEN order_delivered_customer_date::date
                   > order_estimated_delivery_date::date
                THEN 1 ELSE 0 END) AS late,
       ROUND(100.0 * AVG(CASE WHEN order_delivered_customer_date::date
                                 > order_estimated_delivery_date::date
                              THEN 1 ELSE 0 END), 1) AS pct_late
FROM raw.orders
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NOT NULL;


-- -------------------------------------------------------------
-- 6. Review score: on time vs. late
-- Result: 4.29 on time vs 2.27 late (-2 stars, -47%).
-- Note: a few orders have more than one review; handled later.
-- -------------------------------------------------------------
SELECT CASE WHEN o.order_delivered_customer_date::date
               > o.order_estimated_delivery_date::date
            THEN 'late' ELSE 'on time' END AS delivery,
       COUNT(*)                      AS n_reviews,
       ROUND(AVG(r.review_score), 2) AS avg_score
FROM raw.orders o
JOIN raw.order_reviews r ON r.order_id = o.order_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
GROUP BY delivery;


-- -------------------------------------------------------------
-- 7. Review score by days of delay
-- Result: on time 4.29 | 1-3 days 3.29 | 4-7 days 2.10 |
--         8-14 days 1.68 | 15+ days 1.72
-- The first days of delay cost the most; above ~1 week scores
-- hit the floor of the 1-5 scale.
-- -------------------------------------------------------------
WITH delivered AS (
    SELECT o.order_delivered_customer_date::date
         - o.order_estimated_delivery_date::date AS days_late,
           r.review_score
    FROM raw.orders o
    JOIN raw.order_reviews r ON r.order_id = o.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
)
SELECT CASE
         WHEN days_late <= 0  THEN 'on time'
         WHEN days_late <= 3  THEN '1-3 days'
         WHEN days_late <= 7  THEN '4-7 days'
         WHEN days_late <= 14 THEN '8-14 days'
         ELSE '15+ days'
       END AS delay_bucket,
       COUNT(*)                    AS n_reviews,
       ROUND(AVG(review_score), 2) AS avg_score
FROM delivered
GROUP BY delay_bucket
ORDER BY MIN(days_late);
