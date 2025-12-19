# Retail-DataWarehouse

# How to run

## 0. Quick View 

If you only want to view the final dashboard, simply open the **.pbix** file in Power BI Desktop.

If you want to set up the full project environment and data pipeline, please follow the steps below.

## 1. Environment Configuration

Ensure you have Make installed to streamline the execution process.

Create a file named `.env` at the root of the project and paste the following content:

```bash
MYSQL_USER = "aid" 
MYSQL_PASSWORD = "Bolodearroz123!"
MYSQL_HOST = "aid.mysql.database.azure.com"
MYSQL_PORT = "3306"
MYSQL_DATABASE = "aidtrabalho"
MYSQL_SSL_CA = "./DigiCertGlobalRootG2.crt.pem"
```

## 2. Installation

Run the following command to install project requirements and submit data to the Azure cloud server:
```bash
make setup
```

## 3. Connect via MySQL Workbench

To inspect the database directly, establish a new connection in MySQL Workbench using these settings:
- **Connection Name:** Can be anything (we used `Azure Database`)
- **Hostname:** `aid.mysql.database.azure.com`
- **Port:** `3306`
- **Username:** `aid`
- **Password:** Click `Store in Vault` and enter: `Bolodearroz123!`
- **SSL:** Navigate to the **SSL** tab. In the **CA File** field, select the `DigiCertGlobalRootG2.crt.pem` file located in this repository.

## 4. Connect via Power BI

To connect the data to Power BI manually:
1. Open Power BI Desktop and create a blank report.
2. Select **Get Data** > **Database** > **MySQL Database**.
3. Enter the following credentials:
   - **Server:** `aid.mysql.database.azure.com`
   - **Database:** `aidtrabalho`
4. If prompted for authentication, select **Database** (left sidebar) and use the username and password provided in Step 3.


# 1. Subject description

**Title:** Retail Sales Data Warehouse (E-commerce Cross-Country Dataset)

**Goal:** Implementation of a robust Star Schema to analyze multi-national retail transactions, tracking customer behavior through both granular transaction logs and monthly snapshots.

**Scope & requirements (from assignment):**

* **Facts (transaction-level) > 10,000 rows:** The full dataset contains almost 290k transactions. The primary additive measure is `line_total_amount`.
* **Aggregated facts / snapshots:** We create monthly snapshots of customer lifetime spending. The measure `lifetime_spend` is semi‑additive (additive across customers but not across time).
* **At least 4 dimensions:** We implemented 7 dimensions: `DimDate`, `DimTimeOfDay`, `DimCustomer`, `DimProduct`, `DimLocation`, `DimPayment`, and `DimShipping`.

**Primary fact table(s):**

1. `FactSales` — Transaction-level grain. Measures: `quantity`, `unit_price`, `line_total_amount`, `ratings`.
2. `Fact_Customer_MonthlySnapshot` — Monthly grain. Measures: `month_spend`, `month_orders` and `lifetime_spend` (Semi-additive).

---

# 2. Planning: Dimensional bus matrix, dimensions and facts dictionary

## 2.1 Dimensional Bus Matrix (high level)

| Business Process / Fact | Date | TimeOfDay | Customer | Product | Location | Payment | Shipping |
| :--- | :-: | :-: | :-: | :-: | :-: | :-: | :-: |
| Sales Transaction (FactSales) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Customer Monthly Snapshot | ✓ (month) | --- | ✓ | --- | ✓ (customer) | --- | --- |

Conformed dimensions: **Date**, **Customer**, **Product**, **Location** - these are shared between the fact tables.

## 2.2 Dimensions dictionary

### DimDate

* **Grain:** 1 row per calendar day.
* **Key:** `date_key` (DDMMYYYY integer).
* **Attributes:** `date` (date), `day_of_week`, `day_name`, `month`, `month_name`, `quarter`, `year`, `is_weekend`.

### DimTimeOfDay

* **Grain:** 1 row per second.
* **Key:** `time_key` (SSMMHH integer).
* **Attributes:** `time_of_day`, `hour_24`, `minute`, `second`, `time_bucket_12hr`, `time_bucket_period` (Morning, Afternoon, Evening, Night).

### DimCustomer

* **Grain:** 1 row per customer.
* **Key:** `customer_key` (Surrogate Key).
* **Natural key:** `Customer_ID`.
* **Attributes:** `name`, `email`, `phone`, `address`, `city`, `state`, `zipcode`, `country`, `age`, `gender`, `income_segment`, `customer_segment`, `first_order_date`, `last_order_date`, `customer_status` (active/inactive).

### DimProduct

* **Grain:** 1 row per product.
* **Key:** `product_key` (Surrogate Key).
* **Natural keys / attributes:** `product_name` (from source `products`), `product_type`, `product_brand`, `product_category`.

### DimLocation

* **Grain:** row per unique City/State/Zipcode/Country.
* **Key:** `location_key` (Surrogate Key).
* **Attributes:** `city`, `state`, `zipcode`, `country`, `region` (e.g., 'Europe', 'North America').

### DimPayment

* **Grain:** 1 row per payment method.
* **Key:** `payment_key` (Surrogate Key).
* **Attributes:** `payment_method` (Credit Card, Debit Card, PayPal, Cash, etc.), `payment_provider` (nullable).

### DimShipping

* **Grain:** 1 row per shipping method.
* **Key:** `shipping_key` (Surrogate Key).
* **Attributes:** `shipping_method` (Same-Day, Standard, Express), `shipping_speed_tier` (Priority, Standard, Economy), `shipping_service_level` (Premium, Basic).

## 2.3 Facts dictionary

### FactSales

* **Grain:** 1 row per transaction line.
* **FKs:** `date_key`, `time_key`, `customer_key`, `product_key`, `location_key`, `payment_key`, `shipping_key`.
* **Degenerate Dimension:** `transaction_id` (This groups product lines into a single order).
* **Measures:** `quantity`, `unit_price`, `line_total_amount` (Additive), `ratings`, `order_status` (e.g., 'Processing'), `feedback`.


### Fact_Customer_MonthlySnapshot

* **Grain:** 1 row per customer per month.
* **FKs:** `snapshot_date_key`, `customer_key`, `location_key`.
* **Measures:** `month_spend`, `month_orders`, `lifetime_spend` (Semi-additive).

---

# 3. Dimensional data model (explained)

We implemented a Star Schema to minimize complexity for BI tools like Power BI. `FactSales` acts as the primary fact table. A second star schema is formed around `Fact_Customer_MonthlySnapshot`, sharing the `DimCustomer`, `DimDate` and `DimLocation` conformed dimensions.


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
                        |
                        |
                     DimDate

Fact_Customer_MonthlySnapshot -> DimTimeOfDay (month), DimCustomer, DimLocation
```

**Why star, not snowflake:** simplicity for BI queries and performance.

**Surrogate keys & SCDs:**

* `DimCustomer` and `DimProduct` should be modeled as **Slowly Changing Dimensions (SCD)** type 2 where appropriate (e.g., `customer_segment` or `income_segment` changes tracked with `effective_date` / `end_date` and surrogate keys). This preserves historical correctness for analysis over time.

---

# 4. Extraction, transformation and loading (ETL)

The transformation process is managed via a custom Python-based pipeline (SQLAlchemy + Pandas) utilizing SSL encryption for Azure.

Source file: `new_retail_data.csv`.

## 4.1 Data Cleaning & Integrity

* **Collision Resolution:** Identifies "collided" transactions (IDs associated with multiple customers/dates) and purges them to maintain strict integrity.
* **Critical Filtration:** Rows missing IDs or essential measures (line_total_amount, quantity) are dropped.
* **Imputation:** Missing categorical fields (Income, Brand, etc.) are filled with "Unknown". Missing Zipcodes are normalized to -1.


## Key Engineering
* **Temporal Keys:** Generates integer-based date_key (DDMMYYYY) and time_key (SSMMHH).
* **Null-Safe Joins:** Uses the Null-Safe Equality Operator (<=>) during the fact load to ensure records with missing geographic attributes are correctly mapped to surrogate keys


# 5. Power BI Implementation

## 5.1 DAX Measures
To support analytical depth, the following DAX measures were implemented within the Power BI model:

### FactSales (Transactional Metrics)
* **Total Sales:** 
```sql
Total Sales = SUM('FactSales'[line_total_amount])
```

* **Total Orders:** 
```sql
Total Orders = DISTINCTCOUNT('FactSales'[transaction_id])
```

* **Average Order Value (AOV):** 
```sql
AOV = DIVIDE([Total Sales], [Total Orders], 0)
```

### Fact_Customer_MonthlySnapshot (Growth Metrics)
* **Total Monthly Spend:** 
```sql 
Total Monthly Spend = SUM('Fact_Customer_MonthlySnapshot'[month_spend])
```

* Prev Month Spend: 
```sql 
Prev Month Spend = 
CALCULATE(
    [Total Monthly Spend], 
    PREVIOUSMONTH('DimDate'[Date])
)
```

* Spend Growth: 
```sql
Spend Growth = 
IF(
    ISBLANK([Prev Month Spend]), 
    BLANK(), 
    [Total Monthly Spend] - [Prev Month Spend]
)
```

## 5.2 Key Visualizations
The dashboard is organized to provide insights into sales trends, geography, and customer behavior:

| Visualization        | Description            | Purpose                                                                  |
|----------------------|------------------------|--------------------------------------------------------------------------|
| Trend Analysis       | Line Chart             | Tracks Total Sales over time by day to identify seasonal peaks.          |
| Best Sellers         | Bar Chart              | Ranks Product Category by Total Sales to find revenue drivers.           |
| Geographic Reach     | Map Chart              | Displays Total Orders per State to identify high-density markets.        |
| Shopping Habits      | Bar Chart              | Analyzes Total Orders by Day Period (Morning, Afternoon, etc.).          |
| Logistics Analysis   | Bar Chart              | Compares Total Sales per Shipping Type to evaluate shipping tier impact. |
| Customer Growth      | Multi-row Card / Bar   | Highlights the Top 5 Customers with the highest monthly spend rise.      |


# 6. Querying and data analysis

Below are representative SQL queries and the expected analytical outcomes.



---

# 7. Critical reflection

## Advantages

* **Optimized for analytics:** Denormalized star schema provides fast aggregation queries compared to normalized OLTP.
* **Conformed dimensions:** Single source of truth for Customer, Product, and Date across data marts.
* **Analytic Readiness:** Monthly snapshots allow for longitudinal analysis (Spend Growth) without heavy OLTP impact.

## Shortcomings / trade‑offs

* **Latency:** batch-loading introduces latency (data is not real-time, it must be updated manually). Storage is higher due to denormalization in dimensions, but this is a standard trade-off for analytical performance.
* **SCD Constraints:** Currently implements SCD Type 1 (Overwriting). Future iterations should move to SCD Type 2 to preserve rigorous historical accuracy for attribute changes.
* **Granularity Trade-offs:** Snapshot table has a fixed monthly granularity; bi-weekly analysis would require re-processing atomic facts.
* **Audit Metadata:** Lacks a formal Audit Dimension to track ETL run-times and data quality flags.

---

# 8. Conclusion

The data warehouse successfully integrates granular sales data with high-level monthly performance metrics. By utilizing conformed dimensions and semi-additive measures like `lifetime_spend`, the model provides a 360-degree view of both product performance and customer loyalty trends.

**Deliverables included:**

* Subject description and requirements mapping
* Dimensional bus matrix, dimension and fact dictionaries
* Dimensional model (star schema) with SCD recommendations
* ETL plan (updated to use `Transaction_ID` as the core transaction key) and snapshot computation strategy
* Representative analytical queries
* Critical reflection and conclusion
