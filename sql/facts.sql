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