/* ============================================================
   VIEW: CUSTOMER SPENDING TRENDS (SCD2-SAFE)
   ============================================================ */

DROP VIEW IF EXISTS V_Customer_Spending_Trends;

CREATE VIEW V_Customer_Spending_Trends AS
SELECT
    customer_id,
    snapshot_month,
    total_spent,
    SUM(total_spent) OVER (
        PARTITION BY customer_id
        ORDER BY snapshot_month
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS cumulative_spending
FROM Fact_Customer_MonthlySnapshot;
