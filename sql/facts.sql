/* ============================================================
   FACT: SALES (SCD2-AWARE)
   Notes:
   - Assumes source column is named `customer_id` in `retail_sales`.
   ============================================================ */

DROP TABLE IF EXISTS FactSales;

CREATE TABLE FactSales AS
SELECT
    r.Order_ID,
    r.Date,
    r.Product_ID,
    r.Store_ID,
    c.customer_key,
    r.Quantity,
    r.Unit_Price,
    r.Total_Amount
FROM retail_sales r
LEFT JOIN DimCustomer c
  ON r.customer_id = c.customer_id
 AND r.Date >= c.effective_from
 AND r.Date <  c.effective_to;


/* ============================================================
   FACT: CUSTOMER MONTHLY SNAPSHOT (SCD2-SAFE)
   ============================================================ */

DROP TABLE IF EXISTS Fact_Customer_MonthlySnapshot;

CREATE TABLE Fact_Customer_MonthlySnapshot AS
SELECT
    LAST_DAY(r.Date) AS snapshot_month,
    r.customer_id,
    c.customer_key,
    COUNT(DISTINCT r.Order_ID) AS total_orders,
    SUM(r.Total_Amount) AS total_spent
FROM retail_sales r
JOIN DimCustomer c
  ON r.customer_id = c.customer_id
 AND LAST_DAY(r.Date) >= c.effective_from
 AND LAST_DAY(r.Date) <  c.effective_to
GROUP BY
    LAST_DAY(r.Date),
    r.customer_id,
    c.customer_key;
