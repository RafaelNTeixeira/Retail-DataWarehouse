--------------------------------------
-----------    DimDate    ------------
--------------------------------------
-- Create Table
CREATE TABLE DimDate (
    date_key INT PRIMARY KEY,
    date DATE,
    day_of_week INT,
    day_name VARCHAR(20),
    month INT,
    month_name VARCHAR(20),
    quarter INT,
    year INT,
    is_weekend CHAR(1),
    is_holiday_flag CHAR(1) DEFAULT 'N'
);
-- Populate Data
INSERT INTO DimDate (date_key, date, day_of_week, day_name, month, month_name, quarter, year, is_weekend)
SELECT DISTINCT 
    date_key,
    Date,
    DAYOFWEEK(Date), -- 1=Sunday, 7=Saturday
    DAYNAME(Date),
    MONTH(Date),
    MONTHNAME(Date),
    QUARTER(Date),
    YEAR(Date),
    CASE WHEN DAYOFWEEK(Date) IN (1, 7) THEN 'Y' ELSE 'N' END
FROM retail_sales
ON DUPLICATE KEY UPDATE date = VALUES(date); -- Prevents errors if run twice


--------------------------------------
------------ DimTimeOfDay ------------
--------------------------------------
-- Create Table
CREATE TABLE DimTimeOfDay (
    time_key INT PRIMARY KEY,
    time_of_day TIME,
    hour_24 INT,
    minute INT,
    second INT,
    time_bucket_12hr VARCHAR(20),
    time_bucket_period VARCHAR(20)
);
-- Populate Data
INSERT INTO DimTimeOfDay (time_key, time_of_day, hour_24, minute, second, time_bucket_12hr, time_bucket_period)
SELECT DISTINCT 
    time_key,
    Time,
    HOUR(Time),
    MINUTE(Time),
    SECOND(Time),
    -- Create 12hr Bucket text (e.g., "08:00 - 08:59")
    CONCAT(LPAD(HOUR(Time), 2, '0'), ':00 - ', LPAD(HOUR(Time), 2, '0'), ':59'),
    -- Create Period Buckets
    CASE 
        WHEN HOUR(Time) BETWEEN 5 AND 11 THEN 'Morning'
        WHEN HOUR(Time) BETWEEN 12 AND 16 THEN 'Afternoon'
        WHEN HOUR(Time) BETWEEN 17 AND 21 THEN 'Evening'
        ELSE 'Night'
    END
FROM retail_sales
ON DUPLICATE KEY UPDATE time_of_day = VALUES(time_of_day);


--------------------------------------
------------ DimLocation -------------
--------------------------------------
-- Create Table
CREATE TABLE DimLocation (
    location_key INT AUTO_INCREMENT PRIMARY KEY,
    city VARCHAR(100),
    state VARCHAR(100),
    zipcode VARCHAR(20),
    country VARCHAR(50),
    region VARCHAR(50)
);
-- Populate Data
INSERT INTO DimLocation (city, state, zipcode, country, region)
SELECT DISTINCT 
    City, 
    State, 
    Zipcode, 
    Country,
    CASE 
        WHEN Country IN ('UK', 'England', 'Germany', 'France') THEN 'Europe'
        WHEN Country IN ('USA', 'Canada', 'Mexico') THEN 'North America'
        WHEN Country IN ('Australia', 'New Zealand') THEN 'Oceania'
        ELSE 'Other' -- Fallback for unknown countries
    END
FROM retail_sales;


--------------------------------------
------------- DimProduct -------------
--------------------------------------
-- Create Table
CREATE TABLE DimProduct (
    product_key INT AUTO_INCREMENT PRIMARY KEY,
    product_name VARCHAR(255),
    product_category VARCHAR(100),
    product_brand VARCHAR(100),
    product_type VARCHAR(100)
);
-- Populate Data
INSERT INTO DimProduct (product_name, product_category, product_brand, product_type)
SELECT DISTINCT 
    product_name, 
    Product_Category, 
    Product_Brand, 
    Product_Type
FROM retail_sales;


--------------------------------------
------------- DimPayment -------------
--------------------------------------
-- Create Table
CREATE TABLE DimPayment (
    payment_key INT AUTO_INCREMENT PRIMARY KEY,
    payment_method VARCHAR(50),
    payment_provider VARCHAR(50)
);
-- Populate Data
INSERT INTO DimPayment (payment_method, payment_provider)
SELECT DISTINCT 
    Payment_Method, 
    'Unknown' -- Source data doesn't have provider (e.g., Visa/Mastercard), so we default to Unknown
FROM retail_sales;


--------------------------------------
------------ DimShipping -------------
--------------------------------------
-- Create Table
CREATE TABLE DimShipping (
    shipping_key INT AUTO_INCREMENT PRIMARY KEY,
    shipping_method VARCHAR(50),
    shipping_speed_tier VARCHAR(50),
    shipping_service_level VARCHAR(50)
);

-- Populate Data
INSERT INTO DimShipping (shipping_method, shipping_speed_tier, shipping_service_level)
SELECT DISTINCT 
    Shipping_Method,
    -- Logic to guess Tier based on name
    CASE 
        WHEN Shipping_Method LIKE '%Same-Day%' THEN 'Priority'
        WHEN Shipping_Method LIKE '%Express%' THEN 'Express'
        ELSE 'Standard'
    END,
    -- Logic to guess Level
    CASE 
        WHEN Shipping_Method LIKE '%Same-Day%' THEN 'Premium'
        ELSE 'Basic'
    END
FROM retail_sales;



--------------------------------------
------------ DimShipping -------------
--------------------------------------
CREATE TABLE DimCustomer (
    customer_key INT AUTO_INCREMENT PRIMARY KEY,
    customer_id BIGINT NOT NULL,           -- Business key

    name VARCHAR(100),
    email VARCHAR(100),
    phone VARCHAR(50),
    address VARCHAR(255),
    city VARCHAR(100),
    state VARCHAR(100),
    zipcode VARCHAR(20),
    country VARCHAR(50),
    age INT,
    gender VARCHAR(20),
    income_segment VARCHAR(50),
    customer_segment VARCHAR(50),

    first_order_date DATE,
    last_order_date DATE,
    customer_status VARCHAR(20),

    -- SCD Type 2 fields
    effective_from DATE NOT NULL,
    effective_to   DATE NOT NULL,
    is_current     TINYINT(1) NOT NULL,
    row_hash       BINARY(16) NOT NULL,

    INDEX idx_customer_current (customer_id, is_current),
    INDEX idx_customer_dates (customer_id, effective_from, effective_to)
);

-- Guarantee only one current row per customer
ALTER TABLE DimCustomer
ADD COLUMN current_customer_id BIGINT
  GENERATED ALWAYS AS (IF(is_current = 1, customer_id, NULL)) STORED,
ADD UNIQUE KEY uq_one_current (current_customer_id);


/* ================= INITIAL SCD2 LOAD FROM retail_sales ================= */

WITH per_day AS (
    SELECT
        r.customer_id,
        r.Date,

        MAX(r.Name) AS name,
        MAX(r.Email) AS email,
        MAX(r.Phone) AS phone,
        MAX(r.Address) AS address,
        MAX(r.City) AS city,
        MAX(r.State) AS state,
        MAX(r.Zipcode) AS zipcode,
        MAX(r.Country) AS country,
        MAX(r.Age) AS age,
        MAX(r.Gender) AS gender,
        MAX(r.Income) AS income_segment,
        MAX(r.Customer_Segment) AS customer_segment,

        MIN(r.Date) OVER (PARTITION BY r.customer_id) AS first_order_date,
        MAX(r.Date) OVER (PARTITION BY r.customer_id) AS last_order_date,

        UNHEX(MD5(CONCAT_WS('|',
            COALESCE(MAX(r.Name),''),
            COALESCE(MAX(r.Email),''),
            COALESCE(MAX(r.Phone),''),
            COALESCE(MAX(r.Address),''),
            COALESCE(MAX(r.City),''),
            COALESCE(MAX(r.State),''),
            COALESCE(MAX(r.Zipcode),''),
            COALESCE(MAX(r.Country),''),
            COALESCE(CAST(MAX(r.Age) AS CHAR),''),
            COALESCE(MAX(r.Gender),''),
            COALESCE(MAX(r.Income),''),
            COALESCE(MAX(r.Customer_Segment),'')
        ))) AS row_hash
    FROM retail_sales r
    GROUP BY r.customer_id, r.Date
),
changes AS (
    SELECT *,
           LAG(row_hash) OVER (PARTITION BY customer_id ORDER BY Date) AS prev_hash
    FROM per_day
),
change_points AS (
    SELECT *,
           LEAD(Date) OVER (PARTITION BY customer_id ORDER BY Date) AS next_change_date
    FROM changes
    WHERE prev_hash IS NULL OR row_hash <> prev_hash
)
INSERT INTO DimCustomer (
    customer_id, name, email, phone, address, city, state, zipcode, country,
    age, gender, income_segment, customer_segment,
    first_order_date, last_order_date, customer_status,
    effective_from, effective_to, is_current, row_hash
)
SELECT
    customer_id, name, email, phone, address, city, state, zipcode, country,
    age, gender, income_segment, customer_segment,
    first_order_date, last_order_date, 'Active',
    Date,
    COALESCE(next_change_date, '9999-12-31'),
    CASE WHEN next_change_date IS NULL THEN 1 ELSE 0 END,
    row_hash
FROM change_points;
