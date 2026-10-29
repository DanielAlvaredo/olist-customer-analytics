-- =============================================================
-- 03_cohorts.sql
-- Monthly cohort retention.
-- A cohort = customers whose FIRST delivered order was in a given
-- month. Retention in month k = % of the cohort that placed at
-- least one order k months after their first one.
--
-- Creates the analysis schema (results layer, read by Power BI).
-- Run from the repository root, after 02_clean_views.sql:
--   psql -U postgres -d olist -f sql/03_cohorts.sql
-- =============================================================

CREATE SCHEMA IF NOT EXISTS analysis;


-- -------------------------------------------------------------
-- analysis.customer_cohorts
-- One row per customer with their cohort (month of first order).
-- Check: 93,096 rows (one per customer).
-- -------------------------------------------------------------
CREATE OR REPLACE VIEW analysis.customer_cohorts AS
SELECT customer_unique_id,
       DATE_TRUNC('month', purchase_date)::date AS cohort_month
FROM clean.order_facts
WHERE customer_order_seq = 1;


-- -------------------------------------------------------------
-- analysis.cohort_retention
-- Long format: one row per (cohort, month_number), ready for a
-- Power BI heatmap.
-- Only OBSERVABLE months are included: the analysis period ends
-- in 2018-08, so e.g. the 2018-06 cohort has months 0-2 only.
-- Observable months with no returning customers show 0 (not
-- missing), thanks to the generated grid + LEFT JOIN.
-- Check: 210 rows (20 cohorts with 20, 19, ..., 1 months).
-- -------------------------------------------------------------
CREATE OR REPLACE VIEW analysis.cohort_retention AS
WITH month_numbers AS (
    -- Months between each order and the customer's first order
    SELECT o.customer_unique_id,
           c.cohort_month,
           ((EXTRACT(YEAR  FROM o.purchase_date) - EXTRACT(YEAR  FROM c.cohort_month)) * 12
           + EXTRACT(MONTH FROM o.purchase_date) - EXTRACT(MONTH FROM c.cohort_month))::int
             AS month_number
    FROM clean.order_facts o
    JOIN analysis.customer_cohorts c USING (customer_unique_id)
),
cohorts AS (
    -- Cohort size and how many months of data exist after it
    -- (2018-08 = last month of the analysis period)
    SELECT cohort_month,
           COUNT(*) AS cohort_size,
           ((2018 - EXTRACT(YEAR FROM cohort_month)) * 12
           + 8 - EXTRACT(MONTH FROM cohort_month))::int AS months_observed
    FROM analysis.customer_cohorts
    GROUP BY cohort_month
),
grid AS (
    -- Every observable (cohort, month_number) combination
    SELECT c.cohort_month,
           c.cohort_size,
           gs.month_number
    FROM cohorts c
    CROSS JOIN LATERAL generate_series(0, c.months_observed) AS gs(month_number)
),
returns AS (
    -- Distinct active customers per cohort and month
    SELECT cohort_month,
           month_number,
           COUNT(DISTINCT customer_unique_id) AS active_customers
    FROM month_numbers
    GROUP BY cohort_month, month_number
)
SELECT g.cohort_month,
       g.month_number,
       g.cohort_size,
       COALESCE(r.active_customers, 0)                                AS active_customers,
       ROUND(100.0 * COALESCE(r.active_customers, 0) / g.cohort_size, 2) AS retention_pct
FROM grid g
LEFT JOIN returns r USING (cohort_month, month_number);


-- -------------------------------------------------------------
-- Query A: retention matrix (for the README).
-- Cells that are not yet observable are NULL automatically,
-- because those rows do not exist in the view.
-- -------------------------------------------------------------
SELECT cohort_month,
       cohort_size,
       MAX(retention_pct) FILTER (WHERE month_number = 1)  AS m1,
       MAX(retention_pct) FILTER (WHERE month_number = 2)  AS m2,
       MAX(retention_pct) FILTER (WHERE month_number = 3)  AS m3,
       MAX(retention_pct) FILTER (WHERE month_number = 6)  AS m6,
       MAX(retention_pct) FILTER (WHERE month_number = 12) AS m12
FROM analysis.cohort_retention
GROUP BY cohort_month, cohort_size
ORDER BY cohort_month;


-- -------------------------------------------------------------
-- Query B: overall retention curve, weighted by cohort size.
-- For each month k, only cohorts that can be observed k months
-- later count in the denominator (avoids the censoring bias of
-- simply counting returning customers per month).
-- -------------------------------------------------------------
SELECT month_number,
       SUM(active_customers)                                  AS active_customers,
       SUM(cohort_size)                                       AS eligible_customers,
       ROUND(100.0 * SUM(active_customers) / SUM(cohort_size), 2) AS retention_pct
FROM analysis.cohort_retention
WHERE month_number BETWEEN 1 AND 12
GROUP BY month_number
ORDER BY month_number;
