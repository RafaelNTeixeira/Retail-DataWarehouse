/* ============================================================
   DIMENSION: CUSTOMER (SCD TYPE 2)
   Notes:
   - Assumes source column is named `customer_id` in `retail_sales`.
   - If your source uses a different name, replace `customer_id` consistently.
   ============================================================ */

DROP TABLE IF EXISTS DimCustomer;

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
