-- ============================================================
-- vw_cancellation_rate_by_category
-- Order-level cancellation rate per product category
-- ============================================================
CREATE OR REPLACE VIEW public.vw_cancellation_rate_by_category AS
WITH cte AS (
    SELECT o.order_id,
        o.order_status,
        oi.order_item_id,
        oi.product_id,
        COALESCE(p.product_category_name, 'Other'::text) AS product_category_name
    FROM olist_orders_dataset o
    JOIN olist_order_items_dataset oi ON o.order_id = oi.order_id
    JOIN olist_products_dataset p ON oi.product_id = p.product_id
)
SELECT product_category_name,
    count(DISTINCT order_id) FILTER (WHERE order_status = 'canceled'::text) AS canceled_orders,
    count(DISTINCT order_id) AS total_orders,
    round(100.0 * count(DISTINCT order_id) FILTER (WHERE order_status = 'canceled'::text)::numeric / count(DISTINCT order_id)::numeric, 2) AS cancellation_rate
FROM cte
GROUP BY product_category_name
ORDER BY cancellation_rate DESC;

-- ============================================================
-- vw_customer_order_frequency
-- Number of orders placed per unique customer
-- ============================================================
CREATE OR REPLACE VIEW public.vw_customer_order_frequency AS
SELECT customer_unique_id,
    count(customer_id) AS orders
FROM olist_customers_dataset
GROUP BY customer_unique_id
ORDER BY orders DESC;

-- ============================================================
-- vw_installment_behavior
-- Distribution of orders by installment count bucket
-- ============================================================
CREATE OR REPLACE VIEW public.vw_installment_behavior AS
WITH bucketed AS (
    SELECT
        CASE
            WHEN payment_installments = 1 THEN '1'
            WHEN payment_installments BETWEEN 2 AND 3 THEN '2-3'
            WHEN payment_installments BETWEEN 4 AND 6 THEN '4-6'
            WHEN payment_installments BETWEEN 7 AND 12 THEN '7-12'
            ELSE '13+'
        END AS installment_bucket
    FROM olist_order_payments_dataset
    WHERE payment_value > 0 AND payment_installments > 0
)
SELECT installment_bucket,
    count(*) AS payment_count,
    100.0 * count(*)::numeric / sum(count(*)) OVER () AS share_pct
FROM bucketed
GROUP BY installment_bucket
ORDER BY CASE installment_bucket
    WHEN '1' THEN 1
    WHEN '2-3' THEN 2
    WHEN '4-6' THEN 3
    WHEN '7-12' THEN 4
    ELSE 5
END;

-- ============================================================
-- vw_late_delivery_rate_by_category
-- Late delivery rate per product category
-- ============================================================
CREATE OR REPLACE VIEW public.vw_late_delivery_rate_by_category AS
WITH base AS (
    SELECT oi.order_id,
        oi.product_id,
        COALESCE(p.product_category_name, 'Other'::text) AS product_category_name,
        o.order_delivered_customer_date,
        o.order_estimated_delivery_date
    FROM olist_order_items_dataset oi
    JOIN olist_products_dataset p ON oi.product_id = p.product_id
    JOIN olist_orders_dataset o ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
)
SELECT product_category_name,
    count(*) AS total_delivered_items,
    count(*) FILTER (WHERE order_delivered_customer_date IS NOT NULL
        AND order_estimated_delivery_date IS NOT NULL
        AND order_delivered_customer_date > order_estimated_delivery_date) AS late_items,
    round(100.0 * count(*) FILTER (WHERE order_delivered_customer_date IS NOT NULL
        AND order_estimated_delivery_date IS NOT NULL
        AND order_delivered_customer_date > order_estimated_delivery_date)::numeric / count(*)::numeric, 2) AS late_delivery_rate
FROM base
GROUP BY product_category_name
ORDER BY late_delivery_rate DESC;

-- ============================================================
-- vw_order_items_by_category
-- Clean vs failed item counts per product category
-- ============================================================
CREATE OR REPLACE VIEW public.vw_order_items_by_category AS
WITH cte1 AS (
    SELECT oi.order_id,
        oi.order_item_id,
        oi.product_id,
        COALESCE(p.product_category_name, 'Other'::text) AS product_category_name
    FROM olist_order_items_dataset oi
    JOIN olist_products_dataset p ON oi.product_id = p.product_id
),
cte2 AS (
    SELECT o.order_id,
        o.order_status,
        cte1.order_item_id,
        cte1.product_id,
        cte1.product_category_name
    FROM olist_orders_dataset o
    JOIN cte1 ON o.order_id = cte1.order_id
)
SELECT product_category_name,
    count(*) FILTER (WHERE order_status NOT IN ('canceled', 'unavailable')) AS clean_orders,
    count(*) FILTER (WHERE order_status IN ('canceled', 'unavailable')) AS fail_orders
FROM cte2
GROUP BY product_category_name
ORDER BY clean_orders DESC;

-- ============================================================
-- vw_payment_type_usage_share
-- Transaction count share by payment type
-- ============================================================
CREATE OR REPLACE VIEW public.vw_payment_type_usage_share AS
SELECT payment_type,
    count(*) AS payment_count,
    100.0 * count(*)::numeric / sum(count(*)) OVER () AS share_pct
FROM olist_order_payments_dataset
WHERE payment_value > 0
GROUP BY payment_type
ORDER BY payment_count DESC;

-- ============================================================
-- vw_payment_type_value_share
-- Total payment value share by payment type
-- ============================================================
CREATE OR REPLACE VIEW public.vw_payment_type_value_share AS
SELECT payment_type,
    sum(payment_value) AS total_payment_value,
    100.0 * sum(payment_value) / sum(sum(payment_value)) OVER () AS value_share_pct
FROM olist_order_payments_dataset
GROUP BY payment_type
ORDER BY total_payment_value DESC;

-- ============================================================
-- vw_repeat_purchase_category_composition
-- Share of repeat purchase items by product category
-- ============================================================
CREATE OR REPLACE VIEW public.vw_repeat_purchase_category_composition AS
WITH valid_orders AS (
    SELECT o.order_id,
        c.customer_unique_id,
        o.order_purchase_timestamp,
        row_number() OVER (PARTITION BY c.customer_unique_id ORDER BY o.order_purchase_timestamp) AS rn
    FROM olist_orders_dataset o
    JOIN olist_customers_dataset c ON o.customer_id = c.customer_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
),
repeat_orders AS (
    SELECT order_id
    FROM valid_orders
    WHERE rn > 1
),
base AS (
    SELECT COALESCE(p.product_category_name, 'Other'::text) AS product_category_name,
        ro.order_id
    FROM repeat_orders ro
    JOIN olist_order_items_dataset oi ON ro.order_id = oi.order_id
    JOIN olist_products_dataset p ON oi.product_id = p.product_id
)
SELECT product_category_name,
    count(*) AS repeat_items,
    100.0 * count(*)::numeric / sum(count(*)) OVER () AS share_pct
FROM base
GROUP BY product_category_name
ORDER BY repeat_items DESC;

-- ============================================================
-- vw_review_score_by_category
-- Review score breakdown by product category (item-level attribution)
-- ============================================================
CREATE OR REPLACE VIEW public.vw_review_score_by_category AS
WITH review_clean AS (
    SELECT order_id,
        review_score,
        row_number() OVER (PARTITION BY order_id ORDER BY review_answer_timestamp DESC) AS rn
    FROM olist_order_reviews_dataset
),
category_orders AS (
    SELECT oi.order_id,
        COALESCE(p.product_category_name, 'Other'::text) AS product_category_name
    FROM olist_order_items_dataset oi
    JOIN olist_products_dataset p ON oi.product_id = p.product_id
),
base AS (
    SELECT co.product_category_name,
        rc.review_score
    FROM category_orders co
    JOIN olist_orders_dataset o ON co.order_id = o.order_id
    JOIN review_clean rc ON co.order_id = rc.order_id
    WHERE o.order_status = 'delivered'
    AND rc.rn = 1
)
SELECT product_category_name,
    count(*) FILTER (WHERE review_score = 1) AS score_1,
    count(*) FILTER (WHERE review_score = 2) AS score_2,
    count(*) FILTER (WHERE review_score = 3) AS score_3,
    count(*) FILTER (WHERE review_score = 4) AS score_4,
    count(*) FILTER (WHERE review_score = 5) AS score_5,
    count(*) AS total_reviews
FROM base
GROUP BY product_category_name
ORDER BY total_reviews DESC;

-- ============================================================
-- vw_review_score_by_delivery_bucket
-- Review score breakdown by delivery timeliness bucket
-- ============================================================
CREATE OR REPLACE VIEW public.vw_review_score_by_delivery_bucket AS
WITH cte AS (
    SELECT order_id,
        review_score,
        row_number() OVER (PARTITION BY order_id ORDER BY review_answer_timestamp::timestamp DESC) AS rn
    FROM olist_order_reviews_dataset
),
base AS (
    SELECT order_id,
        order_delivered_customer_date::timestamp AS order_delivered_customer_date,
        order_estimated_delivery_date::timestamp AS order_estimated_delivery_date,
        EXTRACT(days FROM order_delivered_customer_date::timestamp - order_estimated_delivery_date::timestamp) AS delay_days
    FROM olist_orders_dataset
    WHERE order_status = 'delivered'
),
review_clean AS (
    SELECT order_id, review_score
    FROM cte
    WHERE rn = 1
),
bucketed AS (
    SELECT base.order_id,
        review_clean.review_score,
        CASE
            WHEN base.delay_days <= -2 THEN 'Very Early'
            WHEN base.delay_days = -1 THEN 'Early'
            WHEN base.delay_days = 0 THEN 'On-time'
            WHEN base.delay_days = 1 THEN 'Late'
            ELSE 'Very Late'
        END AS delivery_bucket
    FROM base
    JOIN review_clean ON base.order_id = review_clean.order_id
)
SELECT delivery_bucket,
    count(*) FILTER (WHERE review_score = 1) AS score_1,
    count(*) FILTER (WHERE review_score = 2) AS score_2,
    count(*) FILTER (WHERE review_score = 3) AS score_3,
    count(*) FILTER (WHERE review_score = 4) AS score_4,
    count(*) FILTER (WHERE review_score = 5) AS score_5
FROM bucketed
GROUP BY delivery_bucket
ORDER BY CASE delivery_bucket
    WHEN 'Very Early' THEN 1
    WHEN 'Early' THEN 2
    WHEN 'On-time' THEN 3
    WHEN 'Late' THEN 4
    ELSE 5
END;

-- ============================================================
-- vw_review_score_distribution
-- Overall distribution of review scores for delivered orders
-- ============================================================
CREATE OR REPLACE VIEW public.vw_review_score_distribution AS
WITH review_clean AS (
    SELECT r.order_id,
        r.review_score,
        row_number() OVER (PARTITION BY r.order_id ORDER BY r.review_answer_timestamp DESC) AS rn
    FROM olist_order_reviews_dataset r
),
base AS (
    SELECT rc.order_id,
        rc.review_score
    FROM review_clean rc
    JOIN olist_orders_dataset o ON rc.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    AND rc.rn = 1
)
SELECT review_score,
    count(*) AS total_orders
FROM base
GROUP BY review_score
ORDER BY review_score;

-- ============================================================
-- vw_seller_concentration
-- Item volume and clean revenue per seller
-- ============================================================
CREATE OR REPLACE VIEW public.vw_seller_concentration AS
SELECT oi.seller_id,
    count(*) FILTER (WHERE o.order_status NOT IN ('canceled', 'unavailable')) AS successful_items,
    count(*) FILTER (WHERE o.order_status IN ('canceled', 'unavailable')) AS failed_items,
    sum(oi.price) FILTER (WHERE o.order_status NOT IN ('canceled', 'unavailable')) AS clean_revenue
FROM olist_order_items_dataset oi
JOIN olist_orders_dataset o ON oi.order_id = o.order_id
GROUP BY oi.seller_id;

-- ============================================================
-- vw_seller_delay_rate
-- Late delivery rate per seller at item level
-- ============================================================
CREATE OR REPLACE VIEW public.vw_seller_delay_rate AS
WITH base AS (
    SELECT oi.order_id,
        oi.seller_id,
        o.order_delivered_customer_date,
        o.order_estimated_delivery_date
    FROM olist_order_items_dataset oi
    JOIN olist_orders_dataset o ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
)
SELECT seller_id,
    count(*) AS total_items,
    count(*) FILTER (WHERE order_delivered_customer_date IS NOT NULL
        AND order_estimated_delivery_date IS NOT NULL
        AND order_delivered_customer_date > order_estimated_delivery_date) AS late_items,
    100.0 * count(*) FILTER (WHERE order_delivered_customer_date IS NOT NULL
        AND order_estimated_delivery_date IS NOT NULL
        AND order_delivered_customer_date > order_estimated_delivery_date)::numeric / count(*)::numeric AS late_delivery_rate
FROM base
GROUP BY seller_id
ORDER BY late_delivery_rate DESC;

-- ============================================================
-- vw_survey_response_time_vs_review
-- Review score breakdown by time taken to submit review after delivery
-- ============================================================
CREATE OR REPLACE VIEW public.vw_survey_response_time_vs_review AS
WITH base AS (
    SELECT r.order_id,
        r.review_score,
        r.review_answer_timestamp::date - o.order_delivered_customer_date::date AS response_days
    FROM olist_order_reviews_dataset r
    JOIN olist_orders_dataset o ON r.order_id = o.order_id
    WHERE o.order_status = 'delivered'
),
bucketed AS (
    SELECT order_id,
        review_score,
        response_days,
        CASE
            WHEN response_days = 0 THEN 'Same Day'
            WHEN response_days = 1 THEN 'Next Day'
            WHEN response_days BETWEEN 2 AND 3 THEN '2-3 Days'
            WHEN response_days BETWEEN 4 AND 7 THEN '4-7 Days'
            ELSE '7+ Days'
        END AS time_bucket
    FROM base
)
SELECT time_bucket,
    count(*) FILTER (WHERE review_score = 1) AS score_1,
    count(*) FILTER (WHERE review_score = 2) AS score_2,
    count(*) FILTER (WHERE review_score = 3) AS score_3,
    count(*) FILTER (WHERE review_score = 4) AS score_4,
    count(*) FILTER (WHERE review_score = 5) AS score_5
FROM bucketed
GROUP BY time_bucket
ORDER BY CASE time_bucket
    WHEN 'Same Day' THEN 1
    WHEN 'Next Day' THEN 2
    WHEN '2-3 Days' THEN 3
    WHEN '4-7 Days' THEN 4
    ELSE 5
END;
