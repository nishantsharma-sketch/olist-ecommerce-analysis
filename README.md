# olist-ecommerce-analysis
End-to-end data analytics project using Olist Brazilian E-Commerce dataset

## Overview

A full-stack data analytics portfolio project built on the [Olist Brazilian E-Commerce dataset](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) — a real-world dataset covering 100,000+ orders placed on the Olist marketplace between 2016 and 2018.

The project spans the complete data pipeline: raw CSV ingestion → PostgreSQL → Python/SQLAlchemy validation and analysis → SQL analytical views → Power BI dashboard with 7 report pages.

---

## Tech Stack

| Layer | Tool |
|---|---|
| Database | PostgreSQL |
| Data Loading & Validation | Python (pandas, SQLAlchemy, psycopg2) |
| Analytical Logic | SQL (CTEs, window functions, filtered aggregates) |
| Business Intelligence | Power BI Desktop (Mixed mode — Import + DirectQuery) |
| Version Control | GitHub |

---

## Dataset

**Source:** Kaggle — Olist Brazilian E-Commerce Public Dataset
**Tables:** 9 tables, 100,000+ orders
**Date Range:** September 2016 – October 2018
**Note:** September 2016 and October 2018 are partial months and not used for trend interpretation.

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
| olist_geolocation_dataset | Zip code coordinates |
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

Extensive per-table data quality checks were performed before any analysis. Issues were documented and handled explicitly.

### Key Data Quality Issues Found

| Issue | Detail |
|---|---|
| Delivered orders with null dates | 14 null approved_at, 2 null carrier date, 8 null customer delivery date |
| Date logic violations | 1,373 delivered orders where dates are out of sequence |
| Review ID not unique | 789 review_ids mapped to multiple order_ids; 547 order_ids with multiple review_ids |
| Payment value = 0 or negative | Multiple rows — filtered in analysis |
| Payment installments < 1 | Anomalous rows found and excluded |
| Payment sequential gaps | 80 orders with non-contiguous payment_sequential numbering |
| 1 product with all fields null | Only product_id present — complete data gap |
| 610 products missing metadata | No category name, name length, description, or photo count |
| 4 products with weight = 0 | Physical dimension integrity violation |
| 1 delivered order with no payment | Confirmed via order ID — excluded from payment analysis |
| 775 orders with no items | 603 unavailable, 164 canceled, 5 created, 2 invoiced, 1 shipped |
| Translation mismatch | 73 unique categories in products vs 71 in translation table — 623 products affected |
| Column name spelling errors | product_name_lenght, product_description_lenght — corrected in dataframes |

### Date Logic Validation

For all delivered orders with non-null dates, validated:
`purchase < approved < carrier_delivery < customer_delivery`

→ 1,373 violations found. Excluded from date-sensitive analysis (late delivery rate) from both numerator and denominator.

---

## Phase 3 — Relational Integrity

### Schema and Keys

| Table | Primary Key | Foreign Key |
|---|---|---|
| customers | customer_id | — |
| orders | order_id | customer_id → customers |
| order_items | order_id + order_item_id (composite) | order_id → orders, product_id → products, seller_id → sellers |
| payments | none | order_id → orders |
| reviews | none (review_id NOT unique — data quality issue) | order_id → orders |
| products | product_id | product_category_name → translation |
| sellers | seller_id | — |
| geolocation | none | — |
| translation | product_category_name | — |

### Orphan Checks

| Relationship | Result |
|---|---|
| orders → customers | ✅ 0 orphans |
| order_items → orders | ✅ 0 orphans |
| payments → orders | ✅ 0 orphans |
| order_items → products | ✅ 0 orphans |
| order_items → sellers | ✅ 0 orphans |
| reviews → orders | ✅ 0 orphans |
| products → translation | ⚠️ 623 orphaned products (610 null category + 13 from 2 missing categories) |

### Cardinality

| Relationship | Cardinality |
|---|---|
| customers → orders | One-to-One at customer_id level; One-to-Many at customer_unique_id level |
| orders → order_items | One-to-Many (max 21 items per order) |
| orders → payments | One-to-Many (max 29 payments per order) |
| orders → reviews | Expected One-to-One; Actual One-to-Many (data quality issue) |
| order_items → products | Many-to-One |
| order_items → sellers | Many-to-One |
| products → translation | Many-to-One |

### Fan-Out and Data Loss Checks

Systematic JOIN validation performed for all 8 relationships using LEFT JOIN and row count comparison:

- **Customers → Orders:** Clean join
- **Orders → Order Items:** Fan-out expected (one-to-many); 775 unmatched orders (all non-delivered statuses — delivered orders unaffected)
- **Orders → Payments:** Fan-out expected; 1 unmatched delivered order (no payment recorded)
- **Orders → Reviews:** Fan-out expected (547 orders with multiple reviews); 768 orders with no review (normal — not every customer reviews)
- **Order Items → Sellers:** Clean join
- **Order Items → Products:** Clean join
- **Products → Translation:** 623 unmatched products (known — null categories and 2 missing translations)

---

## Phase 4 — Analysis and KPIs

### Key KPIs

| KPI | Value |
|---|---|
| Total Gross Revenue | 16.01M BRL |
| Total Clean Revenue | 15.74M BRL |
| Revenue Gap (canceled/unavailable) | 269.74K BRL |
| Total Orders | 99,441 |
| Delivery Rate | 97.02% |
| Late Delivery Rate | 8.11% |
| Positive Review Rate (≥4 stars) | 77.07% |
| Negative Review Rate (≤2 stars) | 14.69% |
| 5-Star Review Share | 59.22% |
| 1-Star Review Share | 9.76% |
| Repeat Customer Rate | 3.01% |
| Cancellation Rate | 0.63% |
| Unavailability Rate | 0.61% |
| Total Active Sellers | 3,095 (100% active) |
| AOV — Clean Orders | 160.26 BRL |
| Max Orders by Single Customer | 17 |
| Peak Revenue Month | 2017-09 |

### KPI Methodology Notes

- Clean Revenue excludes canceled and unavailable orders
- Late Delivery Rate excludes 24 null-date rows and 1,373 date logic violations from both numerator and denominator
- Positive/Negative Review Rate uses latest review per order_id — deduped using `ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY review_answer_timestamp DESC)`
- Repeat Customer Rate is customer-based: unique customers with more than 1 order divided by total unique customers
- AOV pre-aggregates payments to order level before averaging to prevent fan-out from multi-row payment table

---

## Phase 5 — Power BI Architecture

### Mixed Model Approach

The project started with a full Import mode setup — all 9 raw tables loaded directly into Power BI, with DAX measures for KPIs and visuals.

As analysis grew more complex, DAX began producing incorrect results for:
- Review deduplication (no ROW_NUMBER equivalent)
- Multi-table joins with fan-out risk
- Filtered aggregations across multiple conditions
- Window function logic for share percentages

**PostgreSQL views were introduced** to handle all complex analytical logic. Power BI was then connected to these views via DirectQuery on top of the existing imported tables — creating a mixed model.

**Result:** Raw tables (Import) handle simple card measures and base relationships. Views (DirectQuery) handle all complex analytical visuals. This mirrors a production BI architecture where heavy computation lives in the database layer.

### Why SQL Views Over DAX

| Requirement | DAX | SQL View |
|---|---|---|
| ROW_NUMBER deduplication | No native equivalent | ✅ Window function |
| Multi-step CTEs | Not supported | ✅ Fully supported |
| Filtered aggregates | Verbose, error-prone | ✅ COUNT(*) FILTER (WHERE ...) |
| Fan-out prevention | Requires careful CALCULATE | ✅ Pre-aggregate in CTE |
| Share % via window function | Complex nested measures | ✅ SUM(COUNT(*)) OVER () |

---

## SQL Views Created

| View | Description |
|---|---|
| `vw_positive_review_rate` | Deduped positive review rate (score ≥ 4) |
| `vw_negative_review_rate` | Deduped negative review rate (score ≤ 2) |
| `vw_avg_order_value` | AOV on clean orders — payments pre-aggregated to order level |
| `vw_review_score_distribution` | Overall score distribution for delivered orders |
| `vw_review_score_by_delivery_bucket` | Score breakdown by delivery timeliness (Very Early to Very Late) |
| `vw_survey_response_time_vs_review` | Score breakdown by time between delivery and review submission |
| `vw_review_score_by_category` | Score breakdown by product category (item-level review attribution) |
| `vw_order_items_by_category` | Clean vs failed item counts per category |
| `vw_cancellation_rate_by_category` | Order-level cancellation rate per category |
| `vw_late_delivery_rate_by_category` | Late delivery rate per product category |
| `vw_repeat_purchase_category_composition` | Share of repeat purchase items by category |
| `vw_seller_concentration` | Item volume and clean revenue per seller |
| `vw_seller_delay_rate` | Late delivery rate per seller at item level |
| `vw_payment_type_usage_share` | Payment type transaction share (zero-value rows excluded) |
| `vw_payment_type_value_share` | Payment type value share |
| `vw_installment_behavior` | Installment count bucket distribution |
| `vw_customer_order_frequency` | Order count per unique customer |
| `vw_peak_month` | Month with highest clean revenue |
| `vw_orders_by_hour_bucket` | Order volume by 4-hour time-of-day bucket |

### Key SQL Techniques Used

- `ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY review_answer_timestamp DESC)` — review deduplication
- `COUNT(*) FILTER (WHERE ...)` — conditional aggregation
- `SUM(COUNT(*)) OVER ()` — window function for share percentage
- `COALESCE(product_category_name, 'Other')` — null category handling
- `EXTRACT(DAYS FROM ...)` — delivery delay calculation
- `CASE WHEN ... END` — bucketing for time of day, installments, delivery timeliness
- Multi-step CTEs for complex transformations
- Fan-out prevention via pre-aggregation before joining

---

## Power BI Report Pages

| Page | Visuals | KPI Cards |
|---|---|---|
| Executive Overview | Orders and revenue trend (2016–2018), order status donut | Gross Revenue, Clean Revenue, Total Orders, Delivery Rate, Active Sellers, Positive Review Rate, Late Delivery Rate, Repeat Customer Rate, Cancellation Rate, Unavailability Rate |
| Regional & Temporal Patterns | Revenue by state, orders by time-of-day bucket, delivered orders by weekday | Total Clean Revenue, Revenue Gap, Top State by Revenue, AOV, Peak Week Day |
| Delivery Performance | Late delivery by state, AOV vs late delivery scatter by city, late delivery by category | Late Delivery Rate, Median Delivery Days, Avg Delivery Days, Worst State, Best State |
| Customer Satisfaction | Review score distribution, score by delivery bucket, score by survey response time, score by category | Positive Review Rate, Negative Review Rate, 5-Star Share, 1-Star Share |
| Product & Category Analysis | Clean vs failed orders by category, repeat purchase share, cancellation rate by category | Total Categories, Avg Cancellation Rate, Top Repeat Category, Total Clean Orders |
| Seller Performance | Top 25 sellers by revenue with item volume vs revenue, seller delay rate | Total Active Sellers |
| Payments & Customer Behavior | Installment behavior, customer order frequency, payment value share | Repeat Customer Rate, Dominant Payment Type, Single Installment Share, Max Orders Per Customer |

---

## Key Findings

### Revenue and Orders
- Total clean revenue of **15.74M BRL** across 99K orders over approximately 2 years
- Clear **Q4 2017 revenue peak** — strong seasonality, likely tied to Black Friday and holiday season
- Revenue gap from failed orders is only **269.74K BRL** (~1.7% of gross) — operationally healthy

### Geographic Concentration
- **SP and RJ dwarf all other states** in revenue — extreme geographic concentration risk
- 20+ states contribute minimal revenue — large untapped expansion opportunity
- Northeastern states (AL, MA, PI, CE) combine **low revenue with high late delivery rates** — double challenge for any expansion effort

### Delivery Performance
- **97.02% delivery rate** — strong operational baseline
- **8.11% late delivery rate** among valid delivered orders
- **AL has the worst late delivery rate (~20%)**, RO the best (~3-4%)
- Heavy/bulky categories (`casa_conforto_2`, `moveis_colchao_e_estofado`) have the highest late delivery rates (~16-17%)
- **Most orders are delivered significantly ahead of estimated date** — Olist's delivery estimates are consistently conservative

### Customer Satisfaction
- **77.07% positive review rate**; **14.69% negative**
- Very Late deliveries show concentrated 1-star reviews — late delivery directly drives dissatisfaction
- Customers who review **2-3 days after delivery** are the most active reviewers (44K) and give the most 5-stars (27K)
- Same-day reviews are almost non-existent

### Category Insights
- **cama_mesa_banho** (bed/bath/table) leads in volume, repeat purchases, and total reviews — Olist's anchor category
- **pc_gamer** has the highest cancellation rate (~10%) — niche, high-ticket, high cancellation risk
- **beleza_saude** (health/beauty) leads in 5-star reviews — highest satisfaction category
- Electronics categories show disproportionate 1-star share relative to volume

### Seller Insights
- All **3,095 registered sellers** made at least one sale — 100% active
- Top seller generates ~250K clean revenue, nearly 3x the 25th ranked seller
- **Item volume and clean revenue are not correlated** — some high-volume sellers earn mid-level revenue while low-volume sellers can be top earners
- Even among high-volume sellers (25+ items), late delivery rates range 20-45% — systemic logistics problem, not isolated seller behavior

### Customer Behavior
- **96.88% of customers placed only 1 order** — severe retention gap, biggest business risk
- **Credit card dominates** — 73.93% of transactions, 78.34% of total value
- **50.58% pay in a single installment** — but 22% use 2-3 installments, Brazilian installment culture visible
- **Afternoon (12-16) and Evening (16-20)** are peak ordering windows
- **Monday to Thursday** dominate; Saturday is the weakest day

---

## How to Reproduce

1. Download the Olist dataset from [Kaggle](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce)
2. Set up a PostgreSQL database
3. Run `olist1.ipynb` — update the connection string with your credentials before running
4. Run all SQL view scripts from the `/views` folder in pgAdmin or any PostgreSQL client
5. Open `OLIST_Project.pbix` in Power BI Desktop
6. Update the data source connection: Home → Transform Data → Data Source Settings → update server and database name
7. Refresh the report

**Note:** The `.pbix` file uses a mixed model — raw tables are imported (data embedded) and views connect via DirectQuery (requires a live PostgreSQL connection). KPI cards and simple measures will load from the imported tables. Complex analytical visuals require the PostgreSQL connection to be active.

---

## Limitations and Known Issues

- Slicers not implemented — pre-aggregated views do not retain granular keys needed for reliable cross-view filter propagation in DirectQuery
- 1,373 delivered orders with date logic violations excluded from late delivery rate
- 1 delivered order with no payment record excluded from revenue analysis
- Category names remain in Portuguese (original dataset); English translations available for 71 of 73 categories
- Sep 2016 and Oct 2018 are partial months — excluded from trend interpretation
- Scatter plot (AOV vs Late Delivery Rate by City) has measure management issues — some legacy measures from the initial DAX phase may still be present in the model

---

## Files in This Repository

| File | Description |
|---|---|
| `olist1.ipynb` | Full data loading, profiling, validation, relational integrity, and analysis notebook |
| `OLIST_Project.pbix` | Power BI report (mixed model — partial data embedded, views require PostgreSQL connection) |
| `/views/` | All PostgreSQL view SQL scripts |

---

*Built as a portfolio project to demonstrate end-to-end data analytics skills — raw data ingestion, relational integrity validation, SQL-based analytical logic, and BI reporting with a production-standard architecture.*
