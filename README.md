# Retail-DataWarehouse

# 1. Subject description

**Title:** Retail Sales Data Warehouse (e‑commerce cross‑country dataset)

**Goal:** Design a data warehouse, implement it (logical and physical design, ETL plan) and exemplify its use with analytical queries and visualizations.

**Scope & requirements (from assignment):**

* Facts (transaction-level) > 10,000 rows (the full dataset provided to the group contains many thousands of transactions — sample shown in the brief). One additive measure is required: we use **Total_Amount** (monetary) as the principal additive measure.
* Aggregated facts / snapshots with at least one **semi‑additive** measure: we create monthly snapshots of customer lifetime spending (a cumulative metric) which is **semi‑additive** across non‑temporal dimensions but **not** additive across the time dimension (cannot sum across months without double counting).
* At least **4 dimensions**, one temporal; dimensions will be: **DimDate (temporal)**, **DimCustomer**, **DimProduct**, **DimLocation**, plus two small conformed dimensions **DimPayment** and **DimShipping**. Some dimensions (Date, Customer, Product) are shared/common across multiple fact tables.

**Primary fact table(s):**

1. `Fact_Sales_Transaction` — transaction-level, one row per Transaction_ID × product line (if a transaction contains multiple products, the ETL will explode the `products` into lines). Additive measure: `Amount`, `Total_Amount`.
2. `Fact_Customer_MonthlySnapshot` — monthly snapshot per customer. Semi-additive measure: `Customer_Lifetime_Spent` (cumulative spend up to month-end), also `Month_Total_Purchases` (additive across customers but semi-additive across time if recorded as cumulative). This meets the semi-additive requirement.

---

# 2. Planning: Dimensional bus matrix, dimensions and facts dictionary

## 2.1 Dimensional Bus Matrix (high level)

| Business Process / Fact   |            Date | Customer | Product |              Location | Payment | Shipping |
| ------------------------- | --------------: | -------: | ------: | --------------------: | ------: | -------: |
| Sales Transaction         |               ✓ |        ✓ |       ✓ |                     ✓ |       ✓ |        ✓ |
| Customer Monthly Snapshot | ✓ (month grain) |        ✓ |       — | ✓ (customer location) |       — |        — |

Conformed dimensions: **Date**, **Customer**, **Product**, **Location** — these are shared between the fact tables.

## 2.2 Dimensions dictionary

### DimDate

* **Grain:** 1 row per calendar day (also supports month, quarter, year attributes)
* **Key:** `date_key` (YYYYMMDD integer)
* **Attributes:** `date` (date), `day_of_week`, `day_name`, `month`, `month_name`, `quarter`, `year`, `is_weekend`, `is_holiday_flag` (nullable)

### DimCustomer

* **Grain:** 1 row per customer
* **Key:** `customer_key` (surrogate)
* **Natural key:** `Customer_ID` from source
* **Attributes:** `name`, `email`, `phone`, `address`, `city`, `state`, `zipcode`, `country`, `age`, `gender`, `income_segment`, `customer_segment`, `first_order_date`, `last_order_date`, `customer_status` (active/inactive)

### DimProduct

* **Grain:** 1 row per product SKU / product type (we will standardize `products` and `Product_Type` into SKUs)
* **Key:** `product_key` (surrogate)
* **Natural keys / attributes:** `product_name`, `product_category`, `product_brand`, `product_type`, `standard_price` (nullable), `is_discontinued`

### DimLocation

* **Grain:** 1 row per city/state/country combination (or postal code if needed)
* **Key:** `location_key`
* **Attributes:** `city`, `state`, `zipcode`, `country`, `region` (e.g., Europe, North America), `latitude`, `longitude` (optional)

### DimPayment

* **Grain:** 1 row per payment method type
* **Key:** `payment_key`
* **Attributes:** `payment_method` (Credit Card, Debit Card, PayPal, Cash, etc.), `payment_provider` (nullable)

### DimShipping

* **Grain:** 1 row per shipping method
* **Key:** `shipping_key`
* **Attributes:** `shipping_method` (Same-Day, Standard, Express), `carrier` (if available), `typical_lead_time_days`

## 2.3 Facts dictionary

### Fact_Sales_Transaction

* **Grain:** 1 row per transaction line (Transaction_ID × product_line)
* **FKs:** `date_key`, `customer_key`, `product_key`, `location_key`, `payment_key`, `shipping_key`
* **Measures:**

  * `quantity` (integer) — number of units (if available; otherwise default 1)
  * `amount` (monetary) — amount for this line (source: `Amount` or `Total_Amount` divided by number of product lines)
  * `total_amount` (monetary) — total for the transaction (useful for transaction-level aggregates; redundant but convenient)
  * `total_purchases` (integer) — number of items in the transaction (source `Total_Purchases`)
  * `rating` (numeric) — customer rating (for product satisfaction analysis)
  * `is_returned` (boolean) — capture return status if exists or derived from `Order_Status`

**Notes:** `amount` and `total_amount` are additive across all dimensional keys except when analyzing returns; careful handling required.

### Fact_Customer_MonthlySnapshot

* **Grain:** 1 row per customer per month (month-end)
* **FKs:** `month_key` (DimDate at month grain), `customer_key`, `location_key`
* **Measures (examples):**

  * `customer_lifetime_spent` (monetary) — cumulative spend by customer up to month-end (**semi‑additive**; cannot be summed across months).
  * `month_total_spent` (monetary) — amount spent during the month (additive across customers and months)
  * `month_total_orders` (integer) — number of orders in the month

---

# 3. Dimensional data model (explained)

We propose a **star schema** with `Fact_Sales_Transaction` at the center and the conformed dims around it. A second star uses `Fact_Customer_MonthlySnapshot` (month grain) which references the same `DimCustomer`, `DimDate` (at month granularity) and `DimLocation`.

**Diagram (textual):**

```
           DimProduct     DimShipping
                \             /
                 \           /
                  \         /
                   Fact_Sales_Transaction -- DimPayment
                  /    |    \\
                 /     |     \\
           DimCustomer  |     DimLocation
                 \      |
                  \     |
                   DimDate (day grain)

Fact_Customer_MonthlySnapshot -> DimDate (month), DimCustomer, DimLocation
```

**Why star, not snowflake:** simplicity for BI queries and performance. Dimensional attributes are denormalized into dimensions; only the product dimension may keep a small normalization layer if product hierarchies are deep.

**Surrogate keys & SCDs:**

* `DimCustomer` and `DimProduct` should be modeled as **Slowly Changing Dimensions (SCD)** type 2 where appropriate (e.g., `customer_segment` or `income_segment` changes tracked with `effective_date` / `end_date` and surrogate keys). This preserves historical correctness for analysis over time.

---

# 4. Data sources selection. Extraction, transformation and loading (ETL)

## 4.1 Sources

* Source file: raw CSV/JSON transaction logs (sample shown). Columns include `Transaction_ID`, `Customer_ID`, `Date`, `Product_Category`, `Product_Brand`, `Product_Type`, `Amount`, `Total_Amount`, `Total_Purchases`, `Payment_Method`, `Shipping_Method`, `Order_Status`, `Ratings`, etc.
* External references: product master (if available), postal/geo lookup for `zipcode -> region` mapping, holidays calendar (optional) to enrich `DimDate`.

## 4.2 ETL pipeline (high level)

1. **Ingest raw files** into a staging area (raw schema). Keep original column names, load dates, and file provenance.
2. **Data quality checks:** uniqueness of `Transaction_ID`, null checks on critical fields (`Customer_ID`, `Date`, `Total_Amount`), type validation (dates, numeric amounts), detect bad emails/phones for cleansing.
3. **Cleansing & standardization:**

   * Normalize `Date` to ISO format; compute `date_key` (YYYYMMDD) and `month_key` (YYYYMM).
   * Parse `products` free text into canonical `product_name` and map to `DimProduct` SKUs. When mapping fails, create a new `unknown` SKU and flag for manual review.
   * Standardize payment/shipping method names (trim, lower-case, map synonyms: 'Debit Card'/'Debit' -> 'Debit Card').
   * Normalize `Country` names and map to region (UK -> United Kingdom, England rows: Country = UK).
4. **Dimension loading:**

   * Use surrogate key generation and SCD handling. For SCD2: compare source natural key attributes to current dimensional record; if change -> close existing row with `end_date`, insert new row with new surrogate key and `effective_date`.
5. **Fact loading:**

   * Explode transactions with multiple products into transaction lines (one row per product line). Use `Total_Amount` allocation strategy when `Amount` is not per-line: allocate proportionally by a `line_price` or equally across `Total_Purchases`.
   * Look up surrogate keys from dimension staging tables and write to `Fact_Sales_Transaction`.
6. **Snapshot building:**

   * For each month-end, compute `month_total_spent` and `customer_lifetime_spent` per customer. `customer_lifetime_spent` is computed by summing all transaction amounts for that customer for all dates ≤ month_end. Insert one row per customer/month into `Fact_Customer_MonthlySnapshot`.
7. **Auditing & monitoring:**

   * Record row counts, rejections, and data quality metrics. Store ETL run metadata in an `etl_audit` table.

## 4.3 Example pseudocode for snapshot computation (SQL)

```sql
-- month_end is e.g. '2023-09-30'
INSERT INTO Fact_Customer_MonthlySnapshot (month_key, customer_key, location_key, month_total_spent, customer_lifetime_spent, month_total_orders)
SELECT m.month_key, c.customer_key, l.location_key,
       COALESCE(SUM(s.amount) FILTER (WHERE date_trunc('month', s.date)=m.month_start),0) AS month_total_spent,
       COALESCE(SUM(s.amount) FILTER (WHERE s.date <= m.month_end),0) AS customer_lifetime_spent,
       COALESCE(COUNT(DISTINCT s.transaction_id) FILTER (WHERE date_trunc('month', s.date)=m.month_start),0) AS month_total_orders
FROM DimMonth m
CROSS JOIN DimCustomer c
LEFT JOIN Fact_Sales_Transaction s
  ON s.customer_key = c.customer_key
LEFT JOIN DimLocation l ON c.location_key = l.location_key
WHERE m.month_key = 202309
GROUP BY m.month_key, c.customer_key, l.location_key;
```

(When dataset is large, derive monthly snapshots by incremental processing rather than full cross-join.)

---

# 5. Querying and data analysis

Below are representative SQL queries and the expected analytical outcomes.

## 5.1 Total sales by month (time series)

```sql
SELECT d.year, d.month_name, SUM(f.amount) AS total_sales
FROM Fact_Sales_Transaction f
JOIN DimDate d ON f.date_key = d.date_key
GROUP BY d.year, d.month_name
ORDER BY d.year, d.month;
```

**Use:** trend analysis, seasonal patterns, visualization in BI.

## 5.2 Top 10 products by revenue

```sql
SELECT p.product_brand, p.product_name, SUM(f.amount) AS revenue
FROM Fact_Sales_Transaction f
JOIN DimProduct p ON f.product_key = p.product_key
GROUP BY p.product_brand, p.product_name
ORDER BY revenue DESC
LIMIT 10;
```

## 5.3 Cohort / retention (example using snapshot)

Calculate monthly cohort retention by first purchase month and count of active customers in subsequent months. Use `Fact_Customer_MonthlySnapshot` to observe `customer_lifetime_spent` non-additive behavior and active flags.

## 5.4 Find customers with rising lifetime spend (business use case)

```sql
WITH monthly_spend AS (
  SELECT month_key, customer_key, month_total_spent
  FROM Fact_Customer_MonthlySnapshot
)
SELECT m1.customer_key
FROM monthly_spend m1
JOIN monthly_spend m2 ON m1.customer_key = m2.customer_key AND m2.month_key = m1.month_key + 1
WHERE m2.month_total_spent > m1.month_total_spent
GROUP BY m1.customer_key
ORDER BY SUM(m2.month_total_spent - m1.month_total_spent) DESC
LIMIT 50;
```

## 5.5 Snapshot use (semi-additive measure example)

Show `customer_lifetime_spent` at month-ends for a single customer — **do not sum** across months to get lifetime total (already cumulative). To get lifetime spend at a given month, select the snapshot for that month; to get lifetime growth between months subtract the preceding snapshot values.

---

# 6. Critical reflection: advantages and shortcomings vs operational (OLTP) databases

## Advantages of the data warehouse (star schema, analytical model)

* **Optimized for analytics:** denormalized dimensions and fact tables give fast aggregation queries (GROUP BYs, rollups) and simplified BI development.
* **Conformed dimensions:** single source of truth for `DimCustomer`, `DimProduct`, `DimDate` enables cross-functional analysis and consistent KPIs.
* **Time-variant history:** SCD2 support preserves historical changes (e.g., customer segment changes), enabling accurate longitudinal analysis.
* **Snapshots for trend & cohort analysis:** monthly snapshots make common business metrics (cohorts, lifetime value) fast to query without heavy OLTP impact.
* **ETL & data quality:** central place to run cleansing, enrichment and canonicalization; downstream analytics are more reliable.

## Shortcomings / trade‑offs

* **Latency:** the data warehouse is typically loaded in batches (hourly/daily), so it is not suitable for real‑time operational decisions.
* **Storage duplication:** denormalization and historical rows increase storage compared to transactional schemas (normalized OLTP).
* **ETL complexity:** building and maintaining robust ETL (SCDs, deduplication, snapshotting) requires engineering effort and run-time resources.
* **Potential divergence:** if SCDs or dimension mapping are not carefully synchronized with operational systems, users may see differences.

**When to use OLTP instead:** OLTP systems are the system of record for transaction processing, strict consistency and very high concurrency (checkout flow, inventory decrement). The DW is not a replacement but a complement for reporting and decision support.

---

# 7. Conclusion

We designed a star‑schema data warehouse for retail transaction analysis satisfying the assignment constraints: more than 10,000 facts (the full dataset), at least one additive measure (`amount`/`total_amount`) and at least one semi‑additive measure (`customer_lifetime_spent`) in a monthly snapshot fact table. The model uses conformed dimensions (Date, Customer, Product, Location) shared across facts and demonstrates how ETL builds and populates both transactional and snapshot facts. Example queries showcase common business analyses (time series, top products, cohort/retention) and illustrate correct handling of semi‑additive measures.

**Deliverables included:**

* Subject description and requirements mapping
* Dimensional bus matrix, dimension and fact dictionaries
* Dimensional model (star schema) with SCD recommendations
* ETL plan and snapshot computation strategy
* Representative analytical queries and explanation of snapshot semantics
* Critical reflection and conclusion

---

# Appendix: mapping from sample fields (source) to warehouse attributes

* `Transaction_ID` → Fact natural key (staged); surrogate `transaction_sk` in Fact_Sales_Transaction
* `Customer_ID`, `Name`, `Email`, `Phone`, `Address`, `City`, `State`, `Zipcode`, `Country`, `Age`, `Gender`, `Income`, `Customer_Segment` → DimCustomer attributes
* `Date`, `Year`, `Month`, `Time` → DimDate (and DimMonth)
* `Total_Purchases`, `Amount`, `Total_Amount` → Fact measures
* `Product_Category`, `Product_Brand`, `Product_Type`, `products` → DimProduct attributes (products parsed to single product lines)
* `Shipping_Method` → DimShipping
* `Payment_Method` → DimPayment
* `Order_Status`, `Ratings`, `Feedback` → Fact attributes/flags for returns or satisfaction analysis

---

*Prepared as a complete assignment report draft ready for instructor review and professor approval of subject.*
