-- =============================================================
-- 04_rfm.sql
-- RFM segmentation, adapted to a low-repeat business.
--
-- Standard RFM scores R, F and M from 1 to 5. In Olist, 97.85% of
-- customers have a single purchase occasion, so a 1-5 F score
-- would not discriminate. Instead:
--   R  = quintile of days since last purchase (5 = most recent)
--   M  = quintile of total spend in BRL         (5 = highest)
--   F  = binary: genuine repeat customer or not (decision 13)
-- Reference date: 2018-09-01 (day after the analysis period).
--
-- Run from the repository root, after 02_clean_views.sql:
--   psql -U postgres -d olist -f sql/04_rfm.sql
-- =============================================================

CREATE SCHEMA IF NOT EXISTS analysis;


-- -------------------------------------------------------------
-- analysis.customer_rfm
-- One row per customer with RFM metrics, scores and segment.
-- Score boundaries (days / BRL):
--   R5: 3-94 | R4: 94-179 | R3: 179-270 | R2: 270-383 | R1: 383-604
--   M1: <55  | M2: 55-87  | M3: 87-133  | M4: 133-208 | M5: 208+
-- Check: 93,096 customers | median recency 221 days
--        | avg spend 165.12 BRL vs median 107.78 (right-skewed)
-- -------------------------------------------------------------
CREATE OR REPLACE VIEW analysis.customer_rfm AS
WITH rfm AS (
    SELECT customer_unique_id,
           DATE '2018-09-01' - MAX(purchase_date) AS recency_days,
           MAX(purchase_occasion_seq)            AS frequency,
           SUM(order_value)                      AS monetary
    FROM clean.order_facts
    GROUP BY customer_unique_id
),
scored AS (
    SELECT *,
           NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,
           NTILE(5) OVER (ORDER BY monetary)          AS m_score,
           frequency > 1                              AS is_repeat
    FROM rfm
)
SELECT customer_unique_id,
       recency_days,
       frequency,
       monetary,
       r_score,
       m_score,
       is_repeat,
       -- The order of the WHEN clauses IS the segmentation logic:
       -- repeat customers first, then one-time customers by R and M.
       CASE
         WHEN is_repeat AND r_score >= 4    THEN '1. Loyal active'
         WHEN is_repeat                     THEN '2. Loyal at risk'
         WHEN r_score >= 4 AND m_score >= 4 THEN '3. New high-value'
         WHEN r_score >= 4                  THEN '4. New low-value'
         WHEN r_score >= 2 AND m_score >= 4 THEN '5. High-value slipping'
         WHEN r_score >= 2                  THEN '6. Fading'
         ELSE '7. Lost'
       END AS segment
FROM scored;


-- -------------------------------------------------------------
-- Segment summary: share of customers vs share of revenue.
-- Result:
--   segment                 customers  %cust  %rev   avg BRL
--   1. Loyal active             1,056    1.1    2.3   327.86
--   2. Loyal at risk              949    1.0    1.9   313.20
--   3. New high-value          14,504   15.6   28.5   302.46
--   4. New low-value           21,678   23.3   10.3    72.92
--   5. High-value slipping     14,192   15.2   27.2   294.95
--   6. Fading                  22,303   24.0   10.5    72.57
--   7. Lost                    18,414   19.8   19.2   160.54
-- Repeat customers (1+2): 2.1% of customers, 4.2% of revenue.
-- One-time high spenders (3+5): 31% of customers, 56% of revenue.
-- -------------------------------------------------------------
SELECT segment,
       COUNT(*)                                                    AS customers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)          AS pct_customers,
       ROUND(100.0 * SUM(monetary) / SUM(SUM(monetary)) OVER (), 1) AS pct_revenue,
       ROUND(AVG(monetary), 2)                                     AS avg_monetary
FROM analysis.customer_rfm
GROUP BY segment
ORDER BY segment;
