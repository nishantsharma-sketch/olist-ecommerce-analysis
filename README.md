# olist-ecommerce-analysis
End-to-end data analytics project using the Olist Brazilian E-Commerce dataset

## Overview
A full-stack data analytics portfolio project built on the [Olist Brazilian E-Commerce dataset](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) — a real-world dataset covering ~100,000 orders placed on the Olist marketplace between 2016 and 2018.

The project spans the complete pipeline: raw CSV ingestion → PostgreSQL → Python/SQLAlchemy profiling and validation → an 8-table SQL star schema (4 dimensions + 4 facts) → a 5-page Power BI report, built entirely on basic aggregations with no DAX.

---

## Tech Stack

| Layer | Tool |
|---|---|
| Database | PostgreSQL |
| Data Loading & Validation | Python (pandas, SQLAlchemy, psycopg2) |
| Analytical Logic | SQL (subqueries, window functions, filtered aggregates) |
| Data Modeling | Star schema — 4 dimension tables + 4 fact tables, built as SQL views |
| Business Intelligence | Power BI Desktop (Import mode) |
| Version Control | GitHub |

---

## Dataset
**Source:** Kaggle — Olist Brazilian E-Commerce Public Dataset
**Tables:** 9 tables, ~100,000 orders
**Date Range:** September 2016 – October 2018
**Note:** September 2016 and October 2018 are partial months and are treated with caution in trend interpretation.

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
| olist_geolocation_dataset | Zip code coordinates (profiled, excluded from modeling — see below) |
| product_category_name_translation | Portuguese to English category name mapping |

---

## Phase 1 — Data Loading
All 9 CSVs were loaded into PostgreSQL using Python and SQLAlchemy:
```python
df.to_sql(table_name, engine, if_exists='replace', index=False)
```
Column names, data types, row counts, null counts, and unique value counts were profiled for all 9 tables before any analysis.

---

## Phase 2 — Data Quality & Validation
Per-table data quality checks were performed before any analysis. Issues were documented and handled explicitly rather than silently dropped.

### Key Data Quality Issues Found
| Issue | Detail |
|---|---|
| Delivered orders with null dates | 14 null `approved_at`, 2 null carrier date, 8 null customer delivery date |
| Review ID not a unique key | 789 `review_id`s mapped to multiple `order_id`s; 547 `order_id`s with multiple `review_id`s; 649 rows affected by both |
| Payment value = 0 | 9 rows — 3 explained as `not_defined` payment type, 6 unexplained; flagged, not deleted |
| Payment installments = 0 | Found on real, non-zero-value payments — data quality issue, not excluded |
| Payment sequential gaps | 80 orders with non-contiguous `payment_sequential` numbering — confirmed negligible revenue impact (0.06–0.08%), retained |
| 1 product with all fields null | Only `product_id` present — complete data gap |
| 610 products missing metadata | No category name, name length, description length, or photo count |
| 4 products with weight = 0 | All in `cama_mesa_banho`, near-identical dimensions — possible duplicate listings, not confirmed |
| 1 delivered order with no payment | Confirmed via order ID — excluded from payment-level analysis |
| 775 orders with no items | 603 unavailable, 164 canceled, 5 created, 2 invoiced, 1 shipped — delivered orders unaffected |
| Category translation mismatch | 73 unique categories in products vs 71 in translation table — 623 products affected (610 null category + 13 from 2 missing translations) |
| Column name spelling errors | `product_name_lenght`, `product_description_lenght` — corrected in the schema |
| Geolocation has no clean key | Zip alone, zip+state, zip+state+city, and lat/lng dedup all fall short of the table's row count; confirmed many-to-many against both customers and sellers — excluded from the model entirely |

---

## Phase 3 — Relational Integrity

### Schema and Keys
| Table | Primary Key | Foreign Key |
|---|---|---|
| customers | customer_id | — |
| orders | order_id | customer_id → customers |
| order_items | order_id + order_item_id (composite) | order_id → orders, product_id → products, seller_id → sellers |
| payments | order_id + payment_sequential (composite) | order_id → orders |
| reviews | none (review_id NOT unique — data quality issue) | order_id → orders |
| products | product_id | product_category_name → translation |
| sellers | seller_id | — |
| geolocation | none (no clean key at any grain tested) | — |
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
| customers → orders | One-to-One at `customer_id` level (a known Olist quirk — `customer_id` is unique per order); One-to-Many at `customer_unique_id` level |
| orders → order_items | One-to-Many (max 21 items per order) |
| orders → payments | One-to-Many (max 29 payment rows per order) |
| orders → reviews | Expected One-to-One; actual One-to-Many (data quality issue, resolved via dedup — see below) |
| order_items → products | Many-to-One |
| order_items → sellers | Many-to-One |
| products → translation | Many-to-One |

---

## Phase 4 — Data Model: 8-Table Star Schema

Rather than one wide denormalized table, the project uses a proper Kimball-style star schema — 4 dimension tables carrying descriptive attributes, and 4 fact tables carrying only foreign keys and measures. All 8 objects are SQL views built with subqueries (no CTEs) and window functions where needed.

### Dimensions
| View | Grain | Description |
|---|---|---|
| `dim_date` | 1 row per calendar day | Generated date spine (2016-09-01 to 2018-11-01) with year/quarter/month/day-of-week/weekend flags |
| `dim_customers` | 1 row per customer_id | City, state, zip, and the real repeat-shopper key `customer_unique_id` |
| `dim_sellers` | 1 row per seller_id | City, state, zip |
| `dim_products` | 1 row per product_id | English category name (via translation join, nulls coalesced to "uncategorized"), weight/dimensions, photo count |

### Facts
| View | Grain | Description |
|---|---|---|
| `fact_orders` | 1 row per order | Order lifecycle dates, status flags (`is_delivered`, `is_canceled`, `is_excluded_from_clean`), computed `is_late`, `delivery_days`, `approval_days` |
| `fact_order_items` | 1 row per order line item | Primary revenue fact — product_id, seller_id, price, freight_value, plus order-level flags reused from `fact_orders` |
| `fact_payments` | 1 row per payment record | payment_type, installments, payment_value, `is_zero_value_payment` flag |
| `fact_reviews` | 1 row per order (deduplicated) | Latest review per order via `ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY review_answer_timestamp DESC)`, restricted to delivered orders |

### Design principles
- **No fact-to-fact relationships.** Every fact table carries its own `customer_id` and `order_purchase_date`, denormalized via the SQL join, so each fact relates independently to `dim_customers` and `dim_date`. Avoids ambiguous filter propagation in Power BI entirely.
- **Only `order_purchase_date` relates to `dim_date`.** The other four order date columns (approved, carrier, delivered, estimated) stay as plain datetime columns; durations are computed once in SQL rather than solved with role-playing dimensions in DAX.
- **All 10 relationships are single cross-filter direction**, dimension → fact only — including the one genuinely one-to-one relationship (`dim_customers` ↔ `fact_orders`), to prevent indirect filter leakage between fact tables through a shared dimension.
- **"Clean" vs "Gross"** is handled via a plain boolean column (`is_excluded_from_clean`) rather than a DAX filter — Gross = no filter, Clean = `is_excluded_from_clean = False`.

### Why SQL Views Instead of DAX
| Requirement | DAX | SQL View |
|---|---|---|
| Review deduplication | No native ROW_NUMBER equivalent | Window function |
| Multi-table joins with fan-out risk | Requires careful CALCULATE/relationship management | Pre-joined and pre-flagged at the correct grain |
| Gross vs Clean filtering | Would need a measure per KPI | Single boolean column, reused everywhere |
| Delivery duration / lateness logic | Verbose nested CASE/CALCULATE | One CASE WHEN per column, computed once |

All Power BI visuals in this report use only basic field aggregations (Sum, Average, Count, Count Distinct) and native filter cards (checkbox and Top N) — zero DAX measures were written. All analytical logic lives in the SQL layer, which is deliberately the more heavily documented and defensible part of the project.

---

## Power BI Report Pages

| Page | Visuals | KPI Cards |
|---|---|---|
| 1. Executive Overview | Revenue & order trend, order status donut, revenue by state, payment type split | Clean Orders, Gross Revenue, Clean Revenue, Avg Order Value, Avg Review Score |
| 2. Revenue & Order Outcomes | Orders by status, monthly order volume trend | Gross Revenue, Total Orders, Canceled Orders, Unavailable Orders |
| 3. Regional & Delivery Performance | Revenue by state, avg freight by state, late orders by state, top cities by revenue, top 10 sellers by revenue | Active States, Active Sellers, Avg Freight Cost, Late Orders, Avg Delivery Days |
| 4. Temporal Patterns | Orders by day of week, weekday vs weekend split, orders by month (seasonality) | Total Orders, Total Revenue |
| 5. Payments, Products & Customer Feedback | Payment type orders vs value, avg payment value by type, installments distribution, top 10 categories by revenue, review score distribution | Total Payment Value, Avg Payment Value, Avg Installments, Credit Card Payments |

---

## Key Findings

### Revenue and Orders
- Total gross revenue of **16.01M BRL** across 99,441 orders over roughly 2 years
- Revenue is defined as `SUM(payment_value)`, not item price — payments reflect what was actually collected, including freight
- Order volume and revenue don't always move together month-to-month (e.g. Jul 2018 vs Aug 2018) — a sign that average order value shifts independently of volume

### Geographic Concentration
- **São Paulo (SP) dominates by a wide margin** — ~42% of orders and ~37% of revenue, more than 3x the #2 state — but has the *lowest* AOV of any state, meaning volume, not value per order, drives its lead
- Top 5 states account for ~75–77% of both order volume and revenue; the remaining 22 states share the rest
- Freight cost and product price mix vary far more by state than basket size (items per order) does — the likely real driver of regional AOV differences

### Delivery Performance
- Delivery reliability doesn't track cleanly with order volume — some high-volume states/cities have worse late-delivery rates than smaller ones, and vice versa
- Seller density doesn't guarantee reliability either — the state with the most sellers is only mid-pack on-time

### Customer Satisfaction
- Average review score sits around 4.1–4.2 depending on whether all reviews or only delivered/deduplicated reviews are counted — this project uses the delivered-only, latest-review-per-order basis throughout, since review scores should reflect a completed purchase experience
- ~2.9% of raw reviews are attached to non-delivered orders and are excluded from analysis for this reason

### Category Insights
- `cama_mesa_banho` (bed/bath/table) is the largest category by volume but shows comparatively weaker review sentiment than smaller, higher-satisfaction categories
- Category ranking by order count and by revenue diverge meaningfully — some categories are low-volume but high-value niches

### Customer Behavior
- The large majority of customers place only one order — repeat purchase is the exception, not the norm, and is the single biggest retention risk visible in the data
- ~17% of customers generate roughly 50% of clean revenue — significant revenue concentration in a small customer base
- Credit card is the dominant payment method by both transaction count and value share; installment usage beyond 1x is exclusive to credit card

---

## How to Reproduce
1. Download the Olist dataset from [Kaggle](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce)
2. Set up a local PostgreSQL database
3. Run `olistv2.ipynb` — update the connection string with your own credentials before running the loader cell
4. Continue running the notebook through the schema-building section — it creates all 8 dimension/fact views directly against your PostgreSQL database via SQLAlchemy
5. Open `OLIST_Project.pbix` in Power BI Desktop
6. Update the data source: Home → Transform Data → Data Source Settings → point it at your own PostgreSQL server/database
7. Refresh — the report is Import mode, so once refreshed it works fully offline, no live database connection required afterward

---

## Limitations and Known Issues
- No DAX measures were used by design — a small number of ratio-based metrics (e.g. late delivery %, category-level cancellation rate) are approximated visually via clustered comparisons rather than computed as a single percentage; a future iteration will add a handful of one-line DAX measures for these
- `fact_payments` is at payment-record grain, not order grain — a plain "Average of payment_value" differs slightly from a true order-level AOV (which requires pre-aggregating payments to one row per order first); noted here rather than hidden
- Category names are shown in English via the translation join, with 610 uncategorized products (no source category) grouped under "uncategorized"
- Sep 2016 and Oct 2018 are partial months and should be read with that caveat in any trend chart
- Nov 2016 shows a near-total absence of orders — confirmed as a real data gap during profiling, not an artifact of the date range

---

## Files in This Repository
| File | Description |
|---|---|
| `olistv2.ipynb` | Full data loading, profiling, validation, relational integrity work, and the SQL view/schema build |
| `OLIST_Project.pbix` | Power BI report — Import mode, 5 pages, no DAX |
| `Olist_Star_Schema_8Views.sql` | Standalone copy of the 8 view definitions, for reference outside the notebook |

---

*Built as a portfolio project to demonstrate end-to-end data analytics skills — raw data ingestion, relational integrity validation, dimensional data modeling, and BI reporting without relying on DAX for core business logic.*
