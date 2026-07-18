# olist-ecommerce-analysis

An end-to-end data analytics project on the Olist Brazilian E-Commerce dataset — from raw CSVs to a full Power BI report.

## Overview

This project uses the [Olist Brazilian E-Commerce dataset](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) — real order data from Olist's marketplace, roughly 100,000 orders placed between 2016 and 2018. The goal wasn't just to make some charts off a clean CSV — it's the full pipeline: raw data into PostgreSQL, profiling and validating it in Python, building out dimension and fact tables in SQL, and then a 7-page Power BI report on top of that, using only native aggregations and a couple of rate measures.

Almost every decision below — what counts as "clean," what got excluded, why a table isn't connected a certain way — came out of actually digging into the data's problems, not from following a set tutorial structure.

---

## Tech Stack

| Layer | Tool |
|---|---|
| Database | PostgreSQL |
| Data Loading & Validation | Python (pandas, SQLAlchemy, psycopg2) |
| Analytical Logic | SQL (subqueries, window functions, filtered aggregates) |
| Data Modeling | Dimension and fact tables + 1 supplementary view, built as SQL views (one table doesn't cleanly fit either label — see Phase 4) |
| Business Intelligence | Power BI Desktop (Import mode) |
| Version Control | GitHub |

---

## Dataset

**Source:** Kaggle — Olist Brazilian E-Commerce Public Dataset
**Tables:** 9 tables, ~100,000 orders
**Date Range:** September 2016 – October 2018
**Note:** September 2016 and October 2018 are partial months, so trend charts treat them with caution.

### Tables

| Table | Description |
|---|---|
| olist_customers_dataset | Customer IDs and location |
| olist_orders_dataset | Order lifecycle and timestamps |
| olist_order_items_dataset | Item-level order data |
| olist_order_payments_dataset | Payment methods and values |
| olist_order_reviews_dataset | Customer review scores and timestamps |
| olist_products_dataset | Product metadata and dimensions |
| olist_sellers_dataset | Seller location data |
| olist_geolocation_dataset | Zip code coordinates (profiled, excluded from the model — see below) |
| product_category_name_translation | Portuguese to English category name mapping |

---

## Phase 1 — Data Loading

All 9 CSVs were loaded into PostgreSQL with Python and SQLAlchemy:

```python
df.to_sql(table_name, engine, if_exists='replace', index=False)
```

Before doing any analysis, every table got profiled — column types, row counts, null counts, and unique value counts — so problems would show up early instead of surfacing halfway through a chart.

---

## Phase 2 — Data Quality & Validation

Every data quality issue below was checked, documented, and handled on purpose — nothing was silently dropped just because it was inconvenient.

### Key Data Quality Issues Found

| Issue | Detail |
|---|---|
| Delivered orders with null dates | 14 null `approved_at`, 2 null carrier date, 8 null customer delivery date |
| Review ID not a unique key | 789 `review_id`s mapped to multiple `order_id`s; 547 `order_id`s with multiple `review_id`s; 649 rows affected by both |
| Payment value = 0 | 9 rows — 3 explained as `not_defined` payment type, 6 unexplained; flagged, not deleted |
| Payment installments = 0 | Found on real, non-zero-value payments — data quality issue, not excluded |
| Payment sequential gaps | 80 orders with non-contiguous `payment_sequential` numbering — checked the revenue impact (0.06–0.08%), negligible, so kept |
| 1 product with all fields null | Only `product_id` present |
| 610 products missing metadata | No category name, name length, description length, or photo count |
| 4 products with weight = 0 | All in `cama_mesa_banho`, near-identical dimensions — possibly duplicate listings, not confirmed |
| 1 delivered order with no payment | Confirmed via order ID, excluded from payment-level analysis |
| 775 orders with no items | 603 unavailable, 164 canceled, 5 created, 2 invoiced, 1 shipped — delivered orders unaffected |
| Category translation mismatch | 73 unique categories in products vs 71 in translation table — 623 products affected total: 610 had no category at all, plus 13 more whose category exists but has no English translation (from 2 category names missing in the translation table) |
| Column name spelling errors | `product_name_lenght`, `product_description_lenght` — corrected in the schema |
| Geolocation has no clean key | Tried zip alone, zip+state, zip+state+city, and lat/lng dedup — all fell short of the table's row count and were many-to-many against customers and sellers, so the whole table was left out of the model |

---

## Phase 3 — Relational Integrity

### Schema and Keys

| Table | Primary Key | Foreign Key |
|---|---|---|
| customers | customer_id | — |
| orders | order_id | customer_id → customers |
| order_items | order_id + order_item_id (composite) | order_id → orders, product_id → products, seller_id → sellers |
| payments | order_id + payment_sequential (composite) | order_id → orders |
| reviews | none (review_id isn't actually unique) | order_id → orders |
| products | product_id | product_category_name → translation |
| sellers | seller_id | — |
| geolocation | none | — |
| translation | product_category_name | — |

### Orphan Checks

| Relationship | Result |
|---|---|
| orders → customers | 0 orphans |
| order_items → orders | 0 orphans |
| payments → orders | 0 orphans |
| order_items → products | 0 orphans |
| order_items → sellers | 0 orphans |
| reviews → orders | 0 orphans |
| products → translation | 623 orphaned products |

### Cardinality

| Relationship | Cardinality |
|---|---|
| customers → orders | One-to-One at `customer_id` level (Olist gives every order its own customer_id); One-to-Many at `customer_unique_id` level, which is the real repeat-customer key |
| orders → order_items | One-to-Many (up to 21 items per order) |
| orders → payments | One-to-Many (up to 29 payment rows per order) |
| orders → reviews | Should be One-to-One, actually One-to-Many — resolved with dedup, see below |
| order_items → products | Many-to-One |
| order_items → sellers | Many-to-One |
| products → translation | Many-to-One |

---

## Phase 4 — Data Model

Instead of one big flat table, this splits into dimension tables (descriptive attributes) and fact tables (keys + measures), plus one supplementary view. All of it lives as SQL views.

One honest caveat: `fact_reviews` doesn't cleanly fit either box (final name in the model: `new_dim_reviews` — it got renamed partway through once its actual behavior became clear). It's built like a fact table (one row per order), but the way it ends up connected in the model — directly to `fact_order_items`, instead of through customers/date like the other facts — means it behaves more like a dimension in practice. That's part of why this write-up doesn't call the whole thing a "star schema": it's dimension and fact tables, with one table that sits in a gray zone between the two.

### Dimensions

| View | Grain | Description |
|---|---|---|
| `dim_date` | 1 row per calendar day | Date spine (2016-09-01 to 2018-11-01) with year/quarter/month/day-of-week/weekend flags |
| `dim_customers` | 1 row per customer_id | City, state, zip |
| `dim_sellers` | 1 row per seller_id | City, state, zip |
| `dim_products` | 1 row per product_id | English category name (via translation join), weight/dimensions, photo count |
| `dim_customer_unique` | 1 row per customer_unique_id | Supplementary view — Olist gives every order its own customer_id, so without this, a person who ordered 3 times looks like 3 different customers. Carries `clean_order_count` and `is_repeat_customer` so repeat-purchase behavior can actually be measured. |

### Facts

| View | Grain | Description |
|---|---|---|
| `fact_orders` | 1 row per order | Lifecycle dates, status flags (`is_delivered`, `is_canceled`, `is_excluded_from_clean`), computed `is_late`, `delivery_days`, `approval_days` |
| `fact_order_items` | 1 row per order line item | Product_id, seller_id, price, freight_value, plus order-level flags reused from `fact_orders` |
| `fact_payments` | 1 row per payment record | payment_type, installments, payment_value, `is_zero_value_payment` flag |
| `fact_reviews` (final name: `new_dim_reviews`) | 1 row per order (deduplicated) | Latest review per order via `ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY review_answer_timestamp DESC)`, restricted to delivered orders |

### Design principles

- **No fact-to-fact relationships, with one deliberate exception.** Every fact table connects independently to `dim_customers` and `dim_date`. The one exception is `fact_reviews` (renamed `new_dim_reviews` in the final model), which needed a direct link to `fact_order_items` to slice review sentiment by product category without creating an ambiguous filter path — this meant deactivating two of its default relationships (to `dim_customers` and `dim_date`) and adding one active relationship straight to `fact_order_items`. It's the only place the "dimension → fact only" rule gets broken, and it's broken on purpose, not by accident.
- **Only `order_purchase_date` connects to `dim_date`.** The other order date columns (approved, carrier, delivered, estimated) stay as plain datetime columns — durations are computed once in SQL instead of solved with role-playing date dimensions in DAX.
- **Almost every relationship is single-direction**, dimension → fact only, to stop filters from leaking between fact tables through a shared dimension.
- **"Clean" vs "Gross"** is just a boolean column (`is_excluded_from_clean`), not a DAX filter — Gross = no filter, Clean = `is_excluded_from_clean = False`.
- **Ranking cutoffs are based on volume, not on what looks good.** Any city-level comparison (average order value, late-delivery rate, etc.) only includes cities that clear a minimum order-count threshold — otherwise a city with 3 orders and 1 late delivery would show a meaningless 33% late rate. The same city list is reused across every city-level chart so they stay comparable to each other. State-level numbers don't get filtered this way (there are only 27 states), but the smallest-volume states are called out separately since their rates can swing a lot from very few orders.

### Why the Logic Lives in SQL, Not DAX

This isn't about DAX being unable to do something — it's a deliberate choice about where the heavy lifting happens. Deduplication, flagging, and derived columns (like `is_late` or `is_excluded_from_clean`) are computed once, in the database, as part of the view definition — not recomputed every time a visual renders. That keeps the aggregation work close to the data itself, using the database engine it's already built for, instead of pushing that logic into the reporting layer. Power BI's job in this project is just to display already-correct, already-flagged data using its native aggregations (Sum, Average, Count, Count Distinct) — nothing gets computed twice, and every number in the report traces back to one documented line of SQL.

---

## Power BI Report Pages

| Page | What's on it |
|---|---|
| 1. Executive Overview | Top-level KPIs (clean/gross revenue, clean orders, AOV, review score, repeat rate, late delivery rate, cancellation rate), monthly orders & revenue trend, order status split |
| 2. The Growth Engine | Active states/cities/sellers/categories, revenue by state and city, seller count by state, revenue by category |
| 3. Cracks in Business | Freight cost by state, late deliveries by state, median delivery days by state, canceled orders by state |
| 4. Can We Deliver on the Promise? | Delivery day stats (median/min/max), delivered orders by state and trend, seller count by city, top sellers by delivered orders |
| 5. Who's Buying: Where and What | Customer counts (unique/repeat/non-repeat), order-frequency distribution, top customers by revenue, repeat customers by category |
| 6. When and How They Buy | Orders by day of week, weekday vs weekend split, payment type usage and value share, installment distribution |
| 7. Voice of Customers | Review score distribution, review score by state and category, delivery days vs review score |

Each page has its own slicers (mostly Year and Customer State, with a few pages adding Seller State or Category depending on what the page is actually about).

---

## Key Findings

### Revenue and Orders
- Total gross revenue of **16.01M BRL** across 99,441 orders
- Revenue is `SUM(payment_value)`, not item price — it reflects what was actually collected, freight included
- Order volume and revenue don't always move together month to month, meaning average order value shifts on its own sometimes

### Geographic Concentration
- **São Paulo (SP) dominates** — ~42% of orders and ~37% of revenue, more than 3x the #2 state — but has the *lowest* AOV of any state, so it's volume driving its lead, not bigger orders
- Top 5 states account for ~75–77% of both orders and revenue
- Delivery reliability and seller density don't track cleanly with order volume — some high-volume states have worse late-delivery rates than smaller ones, and the state with the most sellers is only mid-pack on time

### Delivery Performance
- Delivery time is the clearest driver of review scores — satisfaction drops noticeably once delivery stretches past ~15-20 days
- Remote/low-volume states show much longer delivery windows and noisier rate metrics (a handful of orders can swing a cancellation rate a lot) — read those numbers with that in mind, not as a clean signal

### Customer Behavior
- Repeat purchase rate is only **~3%** — the large majority of customers order exactly once, which is the biggest retention gap visible in the data
- ~17% of customers generate roughly 50% of clean revenue
- Credit card dominates both transaction count and value share; installments beyond 1x are basically credit-card only
- Weekday orders outnumber weekend orders by roughly 3 to 1

### Customer Satisfaction
- Average review score sits around 4.1–4.2, using delivered-only, latest-review-per-order (a completed purchase should be what a review reflects)
- ~2.9% of raw reviews are attached to non-delivered orders and are excluded for that reason
- Category and state review scores stay fairly clustered — delivery speed matters more to satisfaction than category or location does

---

## How to Reproduce

1. Download the Olist dataset from [Kaggle](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce)
2. Set up a local PostgreSQL database
3. Run `olist_data_pipeline_analysis.ipynb` — update the connection string with your own credentials before the loader cell
4. Keep running through the schema-building section — it creates all dimension/fact views directly against your database via SQLAlchemy
5. Open the Power BI file (see `final_dashboard_v2.md` for the file link) and update the data source: Home → Transform Data → Data Source Settings → point it at your own PostgreSQL server
6. Refresh — the report is Import mode, so once refreshed it works fully offline

---

## Limitations and Known Issues

- Very limited measures by design — a couple of ratio metrics (like late-delivery % by state) are shown as visual comparisons instead of a single computed percentage; a future version could add a small number of DAX measures just for those
- `fact_order_items` is at line-item grain, not order grain — one row per item, not per order. A plain Count on it counts items, not orders, so anything that needs an order-level number (like total orders) has to use Count Distinct on `order_id` instead
- `fact_payments` is at payment-record grain, not order grain, so a plain average of payment_value differs slightly from a true order-level AOV
- 610 products have no source category and are grouped under "uncategorized"
- Sep 2016 and Oct 2018 are partial months — read trend charts with that in mind
- Nov 2016 has almost no orders at all — confirmed as a real gap in the data, not a filtering artifact

---

## Files in This Repository

| File | Description |
|---|---|
| `olist_data_pipeline_analysis.ipynb` | Data loading, profiling, validation, relational integrity checks, and the dimension/fact view build |
| `final_dashboard_v2.md` | Link to the Power BI report (too large to upload directly to GitHub) plus screenshots |
| `Recommendation.md` | A handful of business takeaways based on the analysis |
| `archive/` | Earlier versions — first-draft notebook, first dashboard writeup, and the standalone SQL view file (the current view definitions live directly in the notebook now) |

---

This was my first time building something end-to-end rather than starting from an already-clean CSV — most of the interesting problems (what counts as "clean," why a table gets excluded, where a relationship needs an exception) only showed up because the data itself was messy in specific, real ways.
