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
    -- Primary Key (Composite)
    snapshot_key INT AUTO_INCREMENT PRIMARY KEY,
    
    -- Foreign Keys
    month_key INT,       -- Format: YYYYMM
    customer_key INT,
    location_key INT,    -- We will take their most recent location for that month
    
    -- Measures
    customer_lifetime_spent DECIMAL(15, 2), -- Cumulative (Running Total)
    month_total_spent DECIMAL(15, 2),       -- Additive
    month_total_orders INT,                 -- Additive
    
    -- Indexes for Performance
    INDEX idx_cust_month (customer_key, month_key)
);
INSERT INTO Fact_Customer_MonthlySnapshot (
    month_key, 
    customer_key, 
    location_key, 
    month_total_spent, 
    month_total_orders, 
    customer_lifetime_spent
)
WITH MonthlyAggregates AS (
    -- Step 1: Aggregate individual sales into Monthly Buckets
    SELECT 
        -- Create a Month Key (YYYYMM) from DimDate
        (d.year * 100) + d.month AS month_key,
        f.customer_key,
        -- Logic: Take the location of their most recent purchase in that month
        MAX(f.location_key) AS location_key,
        -- Monthly Totals
        SUM(f.line_total_amount) AS month_spend,
        COUNT(f.transaction_id) AS month_orders
        
    FROM FactSales f
    JOIN DimDate d ON f.date_key = d.date_key
    GROUP BY 
        (d.year * 100) + d.month, 
        f.customer_key
)
-- Step 2: Calculate the Cumulative Lifetime Spend
SELECT 
    month_key,
    customer_key,
    location_key,
    month_spend,
    month_orders,
    -- Window Function to calculate Running Total per Customer
    SUM(month_spend) OVER (
        PARTITION BY customer_key 
        ORDER BY month_key
    ) AS lifetime_spend
FROM MonthlyAggregates;