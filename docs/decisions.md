# Decision log

Analytical and data-cleaning decisions taken during the project, with the reason behind each one.

| # | Decision | Reason |
|---|----------|--------|
| 1 | Use `customer_unique_id` (not `customer_id`) to identify customers. | In Olist, `customer_id` is generated for every order, so it cannot track repeat purchases. 99,441 `customer_id`s map to 96,096 real customers. |
| 2 | Keep only orders with status `delivered` for delay, retention and CLV analysis. | They are ~97% of all orders and the only ones where delivery time and a complete purchase can be measured. Using one definition of "purchase" keeps all analyses consistent. |
| 3 | Exclude the 8 delivered orders with no `order_delivered_customer_date` from delay analysis. | Delay cannot be computed without a delivery date; the volume is negligible. |
| 4 | An order is "late" if it is delivered on a later **day** than the estimated delivery date (dates compared without time). | From the customer's point of view, an order promised for Tuesday that arrives on Tuesday is on time, whatever the hour. Comparing full timestamps would overstate lateness. |
| 5 | No primary key on `raw.order_reviews`. | `review_id` is not unique in the source data, and some orders have more than one review. Deduplication is handled in the clean layer. |
| 6 | No foreign key from `raw.products` to `raw.category_translation`. | Some product categories have no English translation. Missing translations are handled in the clean layer. |
| 7 | Analysis period: orders purchased from 2017-01-01 to 2018-08-31. | The months before and after have very few orders (and late-2018 orders are mostly undelivered), which would distort monthly cohorts. Removes 267 orders; the late-delivery rate stays at 6.8%. |
| 8 | When an order has several reviews, keep the most recent one. | It reflects the customer's final opinion. Removes 551 duplicate reviews (one review per order). |
| 9 | Order value = items price + freight, in Brazilian reais (BRL). | It is what the customer actually paid, so it is the right basis for revenue and CLV. Currency is not converted. |
| 10 | Product category: English name, else Portuguese name, else `unknown`. | Using `LEFT JOIN` + `COALESCE` keeps every item sold, even without a translation or category, instead of silently dropping rows. |
