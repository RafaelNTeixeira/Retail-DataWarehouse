# Retail-DataWarehouse

# How to run

1. Ensure you have the required packages by running the following command in the terminal:
```bash
pip install -r requirements.txt
``` 

2. Run the following command in the terminal to clean and process the raw dataset data: 
```bash
python3 scripts/clean_data.py
```

# 1. Subject description

**Title:** Retail Sales Data Warehouse (e‑commerce cross‑country dataset)

**Goal:** Design a data warehouse, implement it (logical and physical design, ETL plan) and exemplify its use with analytical queries and visualizations.

**Scope & requirements (from assignment):**

* Facts (transaction-level) > 10,000 rows (the full dataset provided to the group contains many thousands of transactions — sample shown in the brief). One additive measure is required: we use **`Line_Total_Amount`** (monetary, from source `Total_Amount`) as the principal additive measure.
* Aggregated facts / snapshots with at least one **semi‑additive** measure: we create monthly snapshots of customer lifetime spending (a cumulative metric) which is **semi‑additive** across non‑temporal dimensions but **not** additive across the time dimension (cannot sum across months without double counting).
* At least **4 dimensions**, one temporal; dimensions will be: **`DimDate` (temporal)**, **`DimTimeOfDay` (temporal)**, **`DimCustomer`**, **`DimProduct`**, **`DimLocation`**, plus two small conformed dimensions **`DimPayment`** and **`DimShipping`**.

**Primary fact table(s):**

1. `Fact_Sales_Transaction` — transaction-level, one row per product line from the source. Additive measures: `Quantity`, `Unit_Price`, `Line_Total_Amount`.
2. `Fact_Customer_MonthlySnapshot` — monthly snapshot per customer. Semi-additive measure: `Customer_Lifetime_Spent` (cumulative spend up to month-end), also `Month_Total_Purchases` (additive across customers but semi-additive across time if recorded as cumulative). This meets the semi-additive requirement.

---

# 2. Planning: Dimensional bus matrix, dimensions and facts dictionary

## 2.1 Dimensional Bus Matrix (high level)

| Business Process / Fact | Date | TimeOfDay | Customer | Product | Location | Payment | Shipping |
| :--- | :-: | :-: | :-: | :-: | :-: | :-: | :-: |
| Sales Transaction | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Customer Monthly Snapshot | ✓ (month) | --- | ✓ | --- | ✓ (customer) | --- | --- |

Conformed dimensions: **Date**, **Customer**, **Product**, **Location** - these are shared between the fact tables.

## 2.2 Dimensions dictionary

### DimDate

* **Grain:** 1 row per calendar day
* **Key:** `date_key` (DDMMYYYY integer)
* **Attributes:** `date` (date), `day_of_week`, `day_name`, `month`, `month_name`, `quarter`, `year`, `is_weekend`, `is_holiday_flag` (nullable)

### DimTimeOfDay (New)

* **Grain:** 1 row per second
* **Key:** `time_key` (SSMMHH integer)
* **Attributes:** `time_of_day` (time), `hour_24`, `minute`, `second`, `time_bucket_12hr` (e.g., '8:00 AM - 8:59 AM'), `time_bucket_period` (e.g., 'Morning', 'Afternoon', 'Evening', 'Night')

### DimCustomer

* **Grain:** 1 row per customer
* **Key:** `customer_key` (surrogate)
* **Natural key:** `Customer_ID` from source
* **Attributes:** `name`, `email`, `phone`, `address`, `city`, `state`, `zipcode`, `country`, `age`, `gender`, `income_segment`, `customer_segment`, `first_order_date`, `last_order_date`, `customer_status` (active/inactive)

### DimProduct

* **Grain:** 1 row per product
* **Key:** `product_key` (surrogate)
* **Natural keys / attributes:** `product_name` (from source `products`), `product_type`, `product_brand`, `product_category`
* **Hierarchy:** `Product_Category` -> `Product_Brand` -> `Product_Type` -> `Product_Name`

### DimLocation

* **Grain:** 1 row per city/state/country combination
* **Key:** `location_key`
* **Attributes:** `city`, `state`, `zipcode`, `country`, `region` (e.g., 'Europe', 'North America')
* **Hierarchy:** `Region` -> `Country` -> `State` -> `City` -> `Zipcode`

### DimPayment

* **Grain:** 1 row per payment method type
* **Key:** `payment_key`
* **Attributes:** `payment_method` (Credit Card, Debit Card, PayPal, Cash, etc.), `payment_provider` (nullable)

### DimShipping

* **Grain:** 1 row per shipping method
* **Key:** `shipping_key`
* **Attributes:** `shipping_method` (Same-Day, Standard, Express), `shipping_speed_tier` (e.g., 'Priority', 'Standard', 'Economy'), `shipping_service_level` (e.g., 'Premium', 'Basic')
* **Hierarchy:** `Shipping_Service_Level` -> `Shipping_Speed_Tier` -> `Shipping_Method`

## 2.3 Facts dictionary

### Fact_Sales_Transaction

* **Grain:** 1 row per transaction line (as-is from the source data)
* **FKs:** `date_key`, `time_key`, `customer_key`, `product_key`, `location_key`, `payment_key`, `shipping_key`
* **Degenerate Dimension:** `transaction_id` (The source `Transaction_ID`. This groups product lines into a single order.)
* **Measures:**
    * `quantity` (integer) — (source: `Total_Purchases`)
    * `unit_price` (monetary) — (source: `Amount`)
    * `line_total_amount` (monetary) — (source: `Total_Amount`) **[Additive Measure]**
    * `rating` (numeric) — customer rating
    * `is_returned` (boolean) — derived from `Order_Status` (e.g., 'Returned')

**Note:** `line_total_amount` is fully additive.


### Fact_Customer_MonthlySnapshot

* **Grain:** 1 row per customer per month (month-end)
* **FKs:** `month_key` (DimDate at month grain), `customer_key`, `location_key`
* **Measures (examples):**
    * `customer_lifetime_spent` (monetary) — cumulative spend by customer up to month-end (**Semi‑Additive**; cannot be summed across months).
    * `month_total_spent` (monetary) — amount spent during the month (additive across customers and months)
    * `month_total_orders` (integer) — number of orders in the month

---

# 3. Dimensional data model (explained)

We propose a **star schema** with `Fact_Sales_Transaction` at the center. `DimTimeOfDay` is included to support timestamp-level analysis. A second star uses `Fact_Customer_MonthlySnapshot` (month grain) which references the same `DimCustomer`, `DimDate` (at month granularity) and `DimLocation`.

**Diagram (textual):**

```
           DimProduct         DimShipping
                \                 /
                 \               /
                  \             /
DimTimeOfDay -- Fact_Sales_Transaction -- DimPayment
                  /     |       \
                 /      |        \
           DimCustomer  |     DimLocation
                 \      |
                  \     |
                   DimDate (day grain)

Fact_Customer_MonthlySnapshot -> DimDate (month), DimCustomer, DimLocation
```

**Why star, not snowflake:** simplicity for BI queries and performance.

**Surrogate keys & SCDs:**

* `DimCustomer` and `DimProduct` should be modeled as **Slowly Changing Dimensions (SCD)** type 2 where appropriate (e.g., `customer_segment` or `income_segment` changes tracked with `effective_date` / `end_date` and surrogate keys). This preserves historical correctness for analysis over time.

---

# 4. Data sources selection. Extraction, transformation and loading (ETL)

## 4.1 Sources

* Source file: raw CSV (`new_retail_data.csv`).

## 4.2 ETL pipeline (high level)

1.  **Ingest raw files** into a staging area.
2.  **Data quality checks:**
    * **CRITICAL:** The source `Transaction_ID` must be cleansed to remove duplicates and collisions. This model relies on a clean `Transaction_ID` to correctly group product lines into unique orders.
    * Null checks on critical fields (`Customer_ID`, `Date`, `Time`, `Total_Amount`).
3.  **Cleansing & standardization:**
    * Normalize `Date` to ISO format; compute `date_key` (DDMMYYYY) and `month_key` (MMYYYY).
    * Parse `Time` to ISO format; compute `time_key` (SSMMHH).
    * Use the `products` column as the `product_name` to map to `DimProduct`.
    * Standardize payment/shipping/country names.
4.  **Dimension loading:**
    * Load `DimDate` and `DimTimeOfDay`.
    * Load other dimensions (`DimCustomer`, `DimProduct`, etc.) using surrogate key generation and SCD handling.
5.  **Fact loading (Fact_Sales_Transaction):**
    * The data is already at the correct grain (one row per product line).
    * Load each row from the source into `Fact_Sales_Transaction`, looking up the surrogate keys for each dimension (`date_key`, `time_key`, `customer_key`, `product_key`, etc.).
    * Load the cleansed `Transaction_ID` into the `transaction_id` degenerate dimension column.
6.  **Snapshot building (Fact_Customer_MonthlySnapshot):**
    * For each month-end, compute `month_total_spent` and `customer_lifetime_spent` per customer. `customer_lifetime_spent` is computed by summing all `line_total_amount` values from `Fact_Sales_Transaction` for that customer for all dates ≤ month-end. Insert one row per customer/month.
7.  **Auditing & monitoring:**
    * Record row counts, rejections, and data quality metrics.

## 4.3 Example pseudocode for snapshot computation (SQL)

```sql
-- month_end is e.g. '2023-09-30'
INSERT INTO Fact_Customer_MonthlySnapshot (month_key, customer_key, location_key, month_total_spent, customer_lifetime_spent, month_total_orders)
SELECT m.month_key, c.customer_key, l.location_key,
    COALESCE(SUM(s.line_total_amount) FILTER (WHERE date_trunc('month', s.date)=m.month_start),0) AS month_total_spent,
    COALESCE(SUM(s.line_total_amount) FILTER (WHERE s.date <= m.month_end),0) AS customer_lifetime_spent,
    -- Note: This counts unique transactions based on the (cleaned) transaction_id
    COALESCE(COUNT(DISTINCT s.transaction_id) FILTER (WHERE date_trunc('month', s.date)=m.month_start),0) AS month_total_orders
FROM DimMonth m
CROSS JOIN DimCustomer c
LEFT JOIN Fact_Sales_Transaction s
  ON s.customer_key = c.customer_key
LEFT JOIN DimLocation l ON c.location_key = l.location_key -- Assuming Customer location
WHERE m.month_key = 202309
GROUP BY m.month_key, c.customer_key, l.location_key;
```

(When dataset is large, derive monthly snapshots by incremental processing rather than full cross-join.)

---

# 5. Querying and data analysis

Below are representative SQL queries and the expected analytical outcomes.

## 5.1 Total sales by hour of day (Uses new DimTimeOfDay)

```sql
SELECT t.hour_24, t.time_bucket_period, SUM(f.line_total_amount) AS total_sales
FROM Fact_Sales_Transaction f
JOIN DimTimeOfDay t ON f.time_key = t.time_key
GROUP BY t.hour_24, t.time_bucket_period
ORDER BY t.hour_24;
```

**Use:** Identify peak purchase times and intra-day patterns for a global audience.

## 5.2 Top 10 products by revenue

```sql
SELECT p.product_name, p.product_brand, SUM(f.line_total_amount) AS revenue
FROM Fact_Sales_Transaction f
JOIN DimProduct p ON f.product_key = p.product_key
GROUP BY p.product_name, p.product_brand
ORDER BY revenue DESC
LIMIT 10;
```

## 5.3 Sales by shipping tier (Uses new DimShipping hierarchy)

```sql
SELECT s.shipping_speed_tier, SUM(f.line_total_amount) AS total_sales
FROM Fact_Sales_Transaction f
JOIN DimShipping s ON f.shipping_key = s.shipping_key
GROUP BY s.shipping_speed_tier
ORDER BY total_sales DESC;
```

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

Show `customer_lifetime_spent` at month-ends for a single customer. **Do not sum** this measure across months. To get lifetime spend at a given month, select the snapshot for that month; to get lifetime growth between months, subtract the preceding snapshot values.

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

We designed a star‑schema data warehouse for retail transaction analysis satisfying the assignment constraints: more than 10,000 facts, at least one additive measure (`line_total_amount`) and at least one semi‑additive measure (`customer_lifetime_spent`) in a monthly snapshot fact table. The model uses conformed dimensions (Date, TimeOfDay, Customer, Product, Location) shared across facts and demonstrates how ETL builds and populates both transactional and snapshot facts. The model also includes hierarchies in `DimShipping`, `DimLocation`, and `DimProduct` and a new `DimTimeOfDay` to support timestamp-level analysis.

**Deliverables included:**

* Subject description and requirements mapping
* Dimensional bus matrix, dimension and fact dictionaries
* Dimensional model (star schema) with SCD recommendations
* ETL plan (updated to use `Transaction_ID` as the core transaction key) and snapshot computation strategy
* Representative analytical queries
* Critical reflection and conclusion

---

# Appendix: mapping from sample fields (source) to warehouse attributes

* `Transaction_ID` → `transaction_id` (Degenerate Dimension in Fact_Sales_Transaction, after cleansing)
* `Customer_ID`, `Name`, `Email`, `Phone`, `Address`, `City`, `State`, `Zipcode`, `Country`, `Age`, `Gender`, `Income`, `Customer_Segment` → `DimCustomer` attributes
* `Date`, `Year`, `Month` → `DimDate` attributes
* `Time` → `DimTimeOfDay` attributes
* `Total_Purchases` → `quantity` (Fact measure)
* `Amount` → `unit_price` (Fact measure)
* `Total_Amount` → `line_total_amount` (Fact measure)
* `Product_Category`, `Product_Brand`, `Product_Type` → `DimProduct` attributes
* `products` → `product_name` (in `DimProduct`)
* `Shipping_Method` → `DimShipping`
* `Payment_Method` → `DimPayment`
* `Order_Status`, `Ratings`, `Feedback` → Fact attributes/flags for returns or satisfaction analysis

---

*Prepared as a complete assignment report draft ready for instructor review and professor approval of subject.*
