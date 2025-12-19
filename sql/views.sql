CREATE OR REPLACE VIEW V_Sales_Hierarchy_Summary AS
SELECT 
    IF(GROUPING(l.region), 'Global Market', l.region) AS Region,

    IF(GROUPING(p.product_category), 
       IF(GROUPING(l.region), '-', 'All Categories'), 
       p.product_category
    ) AS Product_Category,
    
    GROUPING(l.region) + GROUPING(p.product_category) AS Aggregation_Level,

    COUNT(f.transaction_id) AS Total_Transactions,
    SUM(f.line_total_amount) AS Total_Revenue,
    AVG(f.line_total_amount) AS Avg_Transaction_Value

FROM FactSales f
JOIN DimLocation l ON f.location_key = l.location_key
JOIN DimProduct p ON f.product_key = p.product_key

GROUP BY l.region, p.product_category WITH ROLLUP;

---------------------------------------

CREATE OR REPLACE VIEW V_Customer_Spending_Trends AS
SELECT 
    c.name AS Customer_Name,
    d.year,
    d.month, 
    d.month_name,
    s.month_spend AS Current_Month_Spend,
    
    ROUND(
        AVG(s.month_spend) OVER (
            PARTITION BY s.customer_key 
            ORDER BY s.snapshot_date_key 
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        ), 2
    ) AS Moving_Avg_3_Month,

    ROUND(
        s.month_spend - AVG(s.month_spend) OVER (
            PARTITION BY s.customer_key 
            ORDER BY s.snapshot_date_key 
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        ), 2
    ) AS Variance_From_Avg

FROM Fact_Customer_MonthlySnapshot s
JOIN DimCustomer c ON s.customer_key = c.customer_key
JOIN DimDate d ON s.snapshot_date_key = d.date_key;