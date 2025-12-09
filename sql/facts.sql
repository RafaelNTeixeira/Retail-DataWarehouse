INSERT INTO FactSales (
    transaction_id, date_key, time_key, customer_key, product_key, 
    location_key, payment_key, shipping_key, quantity, unit_price, 
    line_total_amount, ratings, order_status, feedback
)
SELECT 
    r.transaction_id,
    r.date_key,
    r.time_key,
    c.customer_key,
    p.product_key,
    l.location_key,
    pay.payment_key,
    s.shipping_key,
    r.quantity,
    r.unit_price,
    r.line_total_amount,
    r.Ratings,
    r.Order_Status,
    r.Feedback
FROM retail_sales r
-- Customer (Safe to keep as LEFT JOIN)
LEFT JOIN DimCustomer c ON r.Customer_ID = c.Customer_ID
-- Product (Safe to keep as LEFT JOIN)
LEFT JOIN DimProduct p ON r.product_name = p.product_name 
                      AND r.Product_Category = p.product_category
                      AND r.Product_Brand = p.product_brand
                      AND r.Product_Type = p.product_type
-- Location: USE <=> HERE!
LEFT JOIN DimLocation l ON r.City <=> l.city 
                       AND r.State <=> l.state 
                       AND r.Zipcode <=> l.zipcode 
                       AND r.Country <=> l.country
-- Payment
LEFT JOIN DimPayment pay ON r.Payment_Method = pay.payment_method
-- Shipping
LEFT JOIN DimShipping s ON r.Shipping_Method = s.shipping_method;


CREATE TABLE Fact_Customer_MonthlySnapshot (
    snapshot_id INT AUTO_INCREMENT PRIMARY KEY,
    -- Points to Jan 31st, Feb 28th, etc.
    snapshot_date_key INT NOT NULL, 
    customer_key INT NOT NULL,
    location_key INT NOT NULL,  -- The location where they ended the month
    -- METRICS
    month_spend DECIMAL(15, 2) DEFAULT 0,
    month_orders INT DEFAULT 0,
    lifetime_spend DECIMAL(15, 2) DEFAULT 0,
    -- CONSTRAINTS
    -- This ensures Data Integrity. We cannot have a snapshot for a date that doesn't exist.
    FOREIGN KEY (snapshot_date_key) REFERENCES DimDate(date_key),
    FOREIGN KEY (customer_key) REFERENCES DimCustomer(customer_key),
    -- PERFORMANCE INDEX
    UNIQUE INDEX idx_cust_date (customer_key, snapshot_date_key)
);
INSERT INTO Fact_Customer_MonthlySnapshot (
    snapshot_date_key, 
    customer_key, 
    location_key, 
    month_spend, 
    month_orders, 
    lifetime_spend
)
WITH MonthlyActivity AS (
    SELECT 
        -- Calculate DDMMYYYY format (Day * 1000000 + Month * 10000 + Year)
        (DAY(LAST_DAY(CONCAT(d.year, '-', d.month, '-01'))) * 1000000) 
        + (d.month * 10000) 
        + d.year AS snapshot_date_key,
        
        f.customer_key,
        f.location_key,
        f.line_total_amount,
        f.transaction_id,
        
        ROW_NUMBER() OVER(
            PARTITION BY f.customer_key, d.year, d.month 
            ORDER BY d.year DESC, d.month DESC, f.time_key DESC
        ) as txn_rank_desc
        
    FROM FactSales f
    JOIN DimDate d ON f.date_key = d.date_key
),
MonthlyAggregates AS (
    SELECT 
        snapshot_date_key,
        customer_key,
        MAX(CASE WHEN txn_rank_desc = 1 THEN location_key END) as location_key,
        SUM(line_total_amount) as month_spend,
        COUNT(transaction_id) as month_orders
    FROM MonthlyActivity
    GROUP BY snapshot_date_key, customer_key
)
SELECT 
    snapshot_date_key,
    customer_key,
    location_key,
    month_spend,
    month_orders,
    SUM(month_spend) OVER (
        PARTITION BY customer_key 
        ORDER BY snapshot_date_key
    ) as lifetime_spend
FROM MonthlyAggregates;