
-- COMPREHENSIVE HOSPITAL SUPPLY CHAIN ANALYSIS 
Select *
From  [Healthcare ].[dbo].[Hospital_Supply_Chain_Data];

-- Check for NULL values
SELECT 
    'NULL Values Check' AS Analysis_Type,
    SUM(CASE WHEN Transaction_ID IS NULL THEN 1 ELSE 0 END) AS Null_Transaction_ID,
    SUM(CASE WHEN Item_Category IS NULL THEN 1 ELSE 0 END) AS Null_Item_Category,
    SUM(CASE WHEN Supplier IS NULL THEN 1 ELSE 0 END) AS Null_Supplier,
    SUM(CASE WHEN Unit_Cost IS NULL THEN 1 ELSE 0 END) AS Null_Unit_Cost,
    SUM(CASE WHEN Quantity_Ordered IS NULL THEN 1 ELSE 0 END) AS Null_Quantity_Ordered,
    SUM(CASE WHEN Stock_Level IS NULL THEN 1 ELSE 0 END) AS Null_Stock_Level,
    SUM(CASE WHEN Lead_Time_Days IS NULL THEN 1 ELSE 0 END) AS Null_Lead_Time,
    SUM(CASE WHEN Supplier_Reliability IS NULL THEN 1 ELSE 0 END) AS Null_Reliability,
    SUM(CASE WHEN Utilization_Rate IS NULL THEN 1 ELSE 0 END) AS Null_Utilization
FROM [Healthcare ].[dbo].[Hospital_Supply_Chain_Data];
GO

-- Check for invalid/outlier values
SELECT 
    'Data Validation Issues' AS Issue_Type,
    SUM(CASE WHEN Unit_Cost < 0 THEN 1 ELSE 0 END) AS Negative_Unit_Cost,
    SUM(CASE WHEN Quantity_Ordered <= 0 THEN 1 ELSE 0 END) AS Invalid_Quantity,
    SUM(CASE WHEN Stock_Level < 0 THEN 1 ELSE 0 END) AS Negative_Stock,
    SUM(CASE WHEN Lead_Time_Days < 0 THEN 1 ELSE 0 END) AS Negative_Lead_Time,
    SUM(CASE WHEN Supplier_Reliability < 0 OR Supplier_Reliability > 1 THEN 1 ELSE 0 END) AS Invalid_Reliability,
    SUM(CASE WHEN Utilization_Rate < 0 OR Utilization_Rate > 1 THEN 1 ELSE 0 END) AS Invalid_Utilization
FROM [Healthcare ].[dbo].[Hospital_Supply_Chain_Data];
GO


/** Calculates inventory stockout risk levels and quantifies the potential financial loss for understocked items across the
 supply chain **/
WITH StockoutRisk AS (
    SELECT 
        Transaction_ID,
        Item_Category,
        Supplier,
        Stock_Level,
        Quantity_Ordered,
        Lead_Time_Days,
        Supplier_Reliability,
        CASE 
            WHEN Stock_Level < Quantity_Ordered * 0.5 THEN 'CRITICAL'
            WHEN Stock_Level < Quantity_Ordered THEN 'HIGH'
            WHEN Stock_Level < Quantity_Ordered * 1.5 THEN 'MODERATE'
            ELSE 'SAFE'
        END AS Risk_Level,
        (Quantity_Ordered - Stock_Level) AS Stock_Deficit,
        Unit_Cost * (Quantity_Ordered - Stock_Level) AS Potential_Loss_Value
    FROM [Healthcare ].[dbo].[Hospital_Supply_Chain_Data]
)
SELECT 
    Risk_Level,
    COUNT(*) AS Transaction_Count,
    CAST(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM [Healthcare ].[dbo].[Hospital_Supply_Chain_Data]) AS DECIMAL(5,2)) AS Percentage,
    AVG(Stock_Deficit) AS Avg_Stock_Deficit,
    SUM(CASE WHEN Potential_Loss_Value > 0 THEN Potential_Loss_Value ELSE 0 END) AS Total_Potential_Loss
FROM StockoutRisk
GROUP BY Risk_Level
ORDER BY 
    CASE Risk_Level 
        WHEN 'CRITICAL' THEN 1
        WHEN 'HIGH' THEN 2
        WHEN 'MODERATE' THEN 3
        WHEN 'SAFE' THEN 4
    END;
GO

/** Rankings of product categories by stockout frequency and financial exposure to assist procurement in prioritizing
emergency replenishment**/
SELECT TOP 10
    Item_Category,
    COUNT(*) AS Critical_Stockout_Count,
    AVG(Stock_Level) AS Avg_Stock_Level,
    AVG(Quantity_Ordered) AS Avg_Quantity_Ordered,
    SUM(Unit_Cost * (Quantity_Ordered - Stock_Level)) AS Total_Value_At_Risk
FROM [Healthcare ].[dbo].[Hospital_Supply_Chain_Data]
WHERE Stock_Level < Quantity_Ordered * 0.5
GROUP BY Item_Category
ORDER BY Critical_Stockout_Count DESC;
GO

/** Aggregates supplier performance metrics (reliability, lead times, and order value) to assign standardized performance ratings
from 'Poor' to 'Excellent' **/

SELECT 
    Supplier,
    COUNT(*) AS Total_Transactions,
    AVG(Supplier_Reliability) AS Avg_Reliability,
    AVG(Lead_Time_Days) AS Avg_Lead_Time,
    MIN(Supplier_Reliability) AS Min_Reliability,
    MAX(Lead_Time_Days) AS Max_Lead_Time,
    SUM(Unit_Cost * Quantity_Ordered) AS Total_Order_Value,
    CASE 
        WHEN AVG(Supplier_Reliability) < 0.6 THEN 'POOR'
        WHEN AVG(Supplier_Reliability) < 0.75 THEN 'FAIR'
        WHEN AVG(Supplier_Reliability) < 0.85 THEN 'GOOD'
        ELSE 'EXCELLENT'
    END AS Performance_Rating
FROM [Healthcare ].[dbo].[Hospital_Supply_Chain_Data]
GROUP BY Supplier
ORDER BY Avg_Reliability ASC, Avg_Lead_Time DESC;
GO

/** dentifies high-risk supplier-category pairings where reliability falls below 70%, highlighting recurrent performance issues across at least 5 transactions  **/

SELECT 
    Supplier,
    Item_Category,
    COUNT(*) AS Transaction_Count,
    AVG(Supplier_Reliability) AS Avg_Reliability,
    AVG(Lead_Time_Days) AS Avg_Lead_Time,
    SUM(Unit_Cost * Quantity_Ordered) AS Category_Order_Value
FROM [Healthcare ].[dbo].[Hospital_Supply_Chain_Data]
WHERE Supplier_Reliability < 0.7
GROUP BY Supplier, Item_Category
HAVING COUNT(*) >= 5
ORDER BY Avg_Reliability ASC, Transaction_Count DESC;
GO

/** Flags the top 20 highest-value transactions where supplier reliability is below 70% and the order value exceeds 150% of the institutional average. **/

SELECT TOP 20
    Transaction_ID,
    Item_Category,
    Supplier,
    Unit_Cost * Quantity_Ordered AS Order_Value,
    Supplier_Reliability,
    Lead_Time_Days,
    Stock_Level,
    'High Risk: Low Reliability + High Value' AS Risk_Flag
FROM [Healthcare ].[dbo].[Hospital_Supply_Chain_Data]
WHERE Supplier_Reliability < 0.7 
  AND (Unit_Cost * Quantity_Ordered) > (
      SELECT AVG(Unit_Cost * Quantity_Ordered) * 1.5 
      FROM [Healthcare ].[dbo].[Hospital_Supply_Chain_Data]
  )
ORDER BY Order_Value DESC;
GO

/** Identifies inventory wastage risks by flagging items with low utilization (<30%) despite surplus stock levels,calculating the total capitaltied up in 
underused assets.**/

SELECT 
    Item_Category,
    COUNT(*) AS Low_Utilization_Count,
    AVG(Utilization_Rate) AS Avg_Utilization_Rate,
    AVG(Stock_Level) AS Avg_Stock_Level,
    AVG(Unit_Cost * Stock_Level) AS Avg_Inventory_Value,
    SUM(Unit_Cost * Stock_Level) AS Total_Wasted_Inventory_Value
FROM [Healthcare ].[dbo].[Hospital_Supply_Chain_Data]
WHERE Utilization_Rate < 0.3 AND Stock_Level > Quantity_Ordered
GROUP BY Item_Category
ORDER BY Total_Wasted_Inventory_Value DESC;
GO

/** Quantifies excess inventory levels and the resulting capital tied up in stock across four tiers of overstock severity **/

WITH OverstockAnalysis AS (
    SELECT 
        Item_Category,
        Supplier,
        Stock_Level,
        Quantity_Ordered,
        Utilization_Rate,
        Unit_Cost,
        (Stock_Level - Quantity_Ordered) AS Excess_Stock,
        Unit_Cost * (Stock_Level - Quantity_Ordered) AS Excess_Stock_Value,
        CASE 
            WHEN Stock_Level > Quantity_Ordered * 3 THEN 'SEVERE_OVERSTOCK'
            WHEN Stock_Level > Quantity_Ordered * 2 THEN 'HIGH_OVERSTOCK'
            WHEN Stock_Level > Quantity_Ordered * 1.5 THEN 'MODERATE_OVERSTOCK'
            ELSE 'ACCEPTABLE'
        END AS Overstock_Level
    FROM [Healthcare ].[dbo].[Hospital_Supply_Chain_Data]
    WHERE Stock_Level > Quantity_Ordered
)
SELECT 
    Overstock_Level,
    COUNT(*) AS Transaction_Count,
    AVG(Excess_Stock) AS Avg_Excess_Units,
    SUM(Excess_Stock_Value) AS Total_Capital_Tied,
    AVG(Utilization_Rate) AS Avg_Utilization
FROM OverstockAnalysis
GROUP BY Overstock_Level
ORDER BY 
    CASE Overstock_Level
        WHEN 'SEVERE_OVERSTOCK' THEN 1
        WHEN 'HIGH_OVERSTOCK' THEN 2
        WHEN 'MODERATE_OVERSTOCK' THEN 3
        ELSE 4
    END;
GO

/** Analyzes lead time consistency and delivery speed across supplier-category pairings to identify logistics bottlenecks and variability **/

SELECT 
    Item_Category,
    Supplier,
    COUNT(*) AS Transaction_Count,
    AVG(Lead_Time_Days) AS Avg_Lead_Time,
    MAX(Lead_Time_Days) AS Max_Lead_Time,
    MIN(Lead_Time_Days) AS Min_Lead_Time,
    STDEV(Lead_Time_Days) AS Lead_Time_Variability,
    CASE 
        WHEN AVG(Lead_Time_Days) > 15 THEN 'SLOW'
        WHEN AVG(Lead_Time_Days) > 10 THEN 'MODERATE'
        ELSE 'FAST'
    END AS Delivery_Speed_Category
FROM [Healthcare ].[dbo].[Hospital_Supply_Chain_Data]
GROUP BY Item_Category, Supplier
HAVING COUNT(*) >= 10
ORDER BY Avg_Lead_Time DESC;
GO

/** Isolates top 20 high-risk transactions where long lead times (>15 days) converge with existing stock deficits to predict imminent stockouts  **/

SELECT TOP 20
    Transaction_ID,
    Item_Category,
    Supplier,
    Lead_Time_Days,
    Stock_Level,
    Quantity_Ordered,
    Supplier_Reliability,
    'Critical Risk: Long Lead Time + Low Stock' AS Alert
FROM [Healthcare ].[dbo].[Hospital_Supply_Chain_Data]
WHERE Lead_Time_Days > 15 
  AND Stock_Level < Quantity_Ordered
ORDER BY Lead_Time_Days DESC, Stock_Level ASC;
GO

/** Summarizes procurement expenditure by category, calculating total financial outlay and unit cost variances to identify high-spend areas **/

SELECT 
    Item_Category,
    COUNT(*) AS Total_Orders,
    SUM(Quantity_Ordered) AS Total_Units_Ordered,
    AVG(Unit_Cost) AS Avg_Unit_Cost,
    MIN(Unit_Cost) AS Min_Unit_Cost,
    MAX(Unit_Cost) AS Max_Unit_Cost,
    SUM(Unit_Cost * Quantity_Ordered) AS Total_Procurement_Cost,
    AVG(Unit_Cost * Quantity_Ordered) AS Avg_Order_Value
FROM [Healthcare ].[dbo].[Hospital_Supply_Chain_Data]
GROUP BY Item_Category
ORDER BY Total_Procurement_Cost DESC;
GO

/** Identifies the top 20 most expensive transactions for items with low utilization (<30%), highlighting primary targets for immediate cost recovery **/

SELECT TOP 20
    Transaction_ID,
    Item_Category,
    Supplier,
    Unit_Cost,
    Quantity_Ordered,
    Unit_Cost * Quantity_Ordered AS Order_Value,
    Utilization_Rate,
    Stock_Level,
    'High Cost + Low Utilization = Waste' AS Optimization_Flag
FROM [Healthcare ].[dbo].[Hospital_Supply_Chain_Data]
WHERE Utilization_Rate < 0.3 
  AND Unit_Cost > (SELECT AVG(Unit_Cost) FROM [Healthcare ].[dbo].[Hospital_Supply_Chain_Data])
ORDER BY Order_Value DESC;
GO

/** Performs a competitive cost-benchmarking analysis, ranking suppliers from lowest to highest cost per category while factoring in reliability to assist in 
vendor selection**/

WITH SupplierCostRanking AS (
    SELECT 
        Item_Category,
        Supplier,
        AVG(Unit_Cost) AS Avg_Cost,
        COUNT(*) AS Order_Count,
        AVG(Supplier_Reliability) AS Avg_Reliability,
        RANK() OVER (PARTITION BY Item_Category ORDER BY AVG(Unit_Cost)) AS Cost_Rank
    FROM [Healthcare ].[dbo].[Hospital_Supply_Chain_Data]
    GROUP BY Item_Category, Supplier
)
SELECT 
    Item_Category,
    Supplier,
    Avg_Cost,
    Order_Count,
    Avg_Reliability,
    Cost_Rank,
    CASE 
        WHEN Cost_Rank = 1 THEN 'LOWEST COST'
        WHEN Cost_Rank = 2 THEN 'SECOND LOWEST'
        ELSE 'HIGHER COST'
    END AS Cost_Position
FROM SupplierCostRanking
WHERE Order_Count >= 10
ORDER BY Item_Category, Cost_Rank;
GO

/** Calculates a weighted Stockout Risk Score and 'Days of Stock Remaining' to identify items where current inventory will be depleted before the next shipment 
arrives**/

WITH StockoutProbability AS (
    SELECT 
        Transaction_ID,
        Item_Category,
        Supplier,
        Stock_Level,
        Quantity_Ordered,
        Lead_Time_Days,
        Supplier_Reliability,
        Utilization_Rate,
        CASE 
            WHEN Lead_Time_Days > 0 THEN (Quantity_Ordered * Utilization_Rate) / Lead_Time_Days
            ELSE 0
        END AS Estimated_Daily_Consumption,
        CASE 
            WHEN Quantity_Ordered * Utilization_Rate > 0 THEN 
                Stock_Level / ((Quantity_Ordered * Utilization_Rate) / NULLIF(Lead_Time_Days, 0))
            ELSE 999
        END AS Days_Of_Stock_Remaining,
        CAST(
            (1 - Supplier_Reliability) * 50 + 
            CASE WHEN Stock_Level < Quantity_Ordered THEN 30 ELSE 0 END + 
            CASE WHEN Lead_Time_Days > 15 THEN 20 ELSE 0 END  
        AS INT) AS Stockout_Risk_Score
    FROM [Healthcare ].[dbo].[Hospital_Supply_Chain_Data]
)
SELECT TOP 30
    Transaction_ID,
    Item_Category,
    Supplier,
    Stock_Level,
    Quantity_Ordered,
    CAST(Days_Of_Stock_Remaining AS DECIMAL(6,2)) AS Days_Stock_Remaining,
    Lead_Time_Days,
    Supplier_Reliability,
    Stockout_Risk_Score,
    CASE 
        WHEN Stockout_Risk_Score >= 70 THEN 'CRITICAL - IMMEDIATE ACTION'
        WHEN Stockout_Risk_Score >= 50 THEN 'HIGH RISK'
        WHEN Stockout_Risk_Score >= 30 THEN 'MODERATE RISK'
        ELSE 'LOW RISK'
    END AS Risk_Category
FROM StockoutProbability
WHERE Days_Of_Stock_Remaining < Lead_Time_Days * 1.5
ORDER BY Stockout_Risk_Score DESC, Days_Stock_Remaining ASC;
GO

/** Analyzes vendor dependency by calculating the market share each supplier holds within specific item categories to identify high concentration risks **/

WITH SupplierConcentration AS (
    SELECT 
        Item_Category,
        Supplier,
        COUNT(*) AS Order_Count,
        SUM(Unit_Cost * Quantity_Ordered) AS Total_Value,
        SUM(SUM(Unit_Cost * Quantity_Ordered)) OVER (PARTITION BY Item_Category) AS Category_Total_Value
    FROM [Healthcare ].[dbo].[Hospital_Supply_Chain_Data]
    GROUP BY Item_Category, Supplier
)
SELECT 
    Item_Category,
    Supplier,
    Order_Count,
    Total_Value,
    CAST(Total_Value * 100.0 / Category_Total_Value AS DECIMAL(5,2)) AS Percentage_Of_Category,
    CASE 
        WHEN Total_Value * 100.0 / Category_Total_Value > 50 THEN 'HIGH CONCENTRATION RISK'
        WHEN Total_Value * 100.0 / Category_Total_Value > 30 THEN 'MODERATE CONCENTRATION'
        ELSE 'DIVERSIFIED'
    END AS Concentration_Risk
FROM SupplierConcentration
ORDER BY Item_Category, Percentage_Of_Category DESC;

/** Evaluates market diversification across the inventory; flags categories with limited vendor options to prioritize the onboarding of alternative suppliers 
and reduce procurement vulnerability. **/

SELECT 
    Item_Category,
    COUNT(DISTINCT Supplier) AS Number_Of_Suppliers,
    COUNT(*) AS Total_Transactions,
    SUM(Unit_Cost * Quantity_Ordered) AS Total_Value,
    CASE 
        WHEN COUNT(DISTINCT Supplier) = 1 THEN 'SINGLE SUPPLIER - CRITICAL RISK'
        WHEN COUNT(DISTINCT Supplier) = 2 THEN 'LIMITED SUPPLIERS - HIGH RISK'
        WHEN COUNT(DISTINCT Supplier) <= 3 THEN 'FEW SUPPLIERS - MODERATE RISK'
        ELSE 'DIVERSIFIED'
    END AS Diversification_Status
FROM [Healthcare ].[dbo].[Hospital_Supply_Chain_Data]
GROUP BY Item_Category
ORDER BY Number_Of_Suppliers ASC, Total_Value DESC;
GO


/** Generates a prioritized procurement action list by calculating an 'Urgency Score' based on inventory deficits, supplier reliability, and delivery lead times **/

WITH EmergencyProcurement AS (
    SELECT 
        Transaction_ID,
        Item_Category,
        Supplier,
        Stock_Level,
        Quantity_Ordered,
        Unit_Cost,
        Lead_Time_Days,
        Supplier_Reliability,
        Utilization_Rate,
        CAST(
            CASE WHEN Stock_Level < Quantity_Ordered * 0.3 THEN 40 ELSE 0 END +
            CASE WHEN Supplier_Reliability < 0.6 THEN 25 ELSE 0 END +
            CASE WHEN Lead_Time_Days > 15 THEN 20 ELSE 0 END +
            CASE WHEN Utilization_Rate > 0.5 THEN 15 ELSE 0 END
        AS INT) AS Urgency_Score,
        (Quantity_Ordered - Stock_Level) AS Units_Needed,
        Unit_Cost * (Quantity_Ordered - Stock_Level) AS Procurement_Cost
    FROM [Healthcare ].[dbo].[Hospital_Supply_Chain_Data]
    WHERE Stock_Level < Quantity_Ordered
)
SELECT TOP 30
    Transaction_ID,
    Item_Category,
    Supplier,
    Stock_Level,
    Units_Needed,
    Procurement_Cost,
    Lead_Time_Days,
    Supplier_Reliability,
    Urgency_Score,
    CASE 
        WHEN Urgency_Score >= 60 THEN 'PRIORITY 1 - ORDER TODAY'
        WHEN Urgency_Score >= 40 THEN 'PRIORITY 2 - ORDER THIS WEEK'
        WHEN Urgency_Score >= 20 THEN 'PRIORITY 3 - PLAN PROCUREMENT'
        ELSE 'MONITOR'
    END AS Action_Required
FROM EmergencyProcurement
WHERE Urgency_Score >= 20
ORDER BY Urgency_Score DESC, Procurement_Cost DESC;
GO

/** Generates a high-level executive summary for each item category, aggregating spending, inventory health, and supplier performance into a single risk-profile 
view **/

SELECT 
    Item_Category,
    COUNT(*) AS Total_Transactions,
    COUNT(DISTINCT Supplier) AS Unique_Suppliers,
    AVG(Unit_Cost) AS Avg_Unit_Cost,
    SUM(Unit_Cost * Quantity_Ordered) AS Total_Spending,
    AVG(Stock_Level) AS Avg_Stock_Level,
    AVG(Quantity_Ordered) AS Avg_Order_Quantity,
    SUM(CASE WHEN Stock_Level < Quantity_Ordered THEN 1 ELSE 0 END) AS Stockout_Risk_Count,
    CAST(SUM(CASE WHEN Stock_Level < Quantity_Ordered THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS DECIMAL(5,2)) AS Stockout_Risk_Percentage,
    AVG(Lead_Time_Days) AS Avg_Lead_Time,
    AVG(Supplier_Reliability) AS Avg_Supplier_Reliability,
    AVG(Utilization_Rate) AS Avg_Utilization_Rate,
    CASE 
        WHEN AVG(Supplier_Reliability) < 0.7 THEN 'YES' ELSE 'NO' 
    END AS Low_Reliability_Flag,
    CASE 
        WHEN AVG(Utilization_Rate) < 0.3 THEN 'YES' ELSE 'NO'
    END AS Low_Utilization_Flag,
    CASE 
        WHEN SUM(CASE WHEN Stock_Level < Quantity_Ordered THEN 1 ELSE 0 END) * 100.0 / COUNT(*) > 30 THEN 'YES' ELSE 'NO'
    END AS High_Stockout_Risk_Flag
    
FROM [Healthcare ].[dbo].[Hospital_Supply_Chain_Data]
GROUP BY Item_Category
ORDER BY Total_Spending DESC;
GO

/** Calculates statistically-derived safety stock levels and reorder points based on lead time and demand variability to minimize stockout risk **/

WITH ReorderPointCalculation AS (
    SELECT 
        Item_Category,
        Supplier,
        AVG(Quantity_Ordered) AS Avg_Demand,
        AVG(Lead_Time_Days) AS Avg_Lead_Time,
        STDEV(Quantity_Ordered) AS Demand_Variability,
        STDEV(Lead_Time_Days) AS Lead_Time_Variability,
        AVG(Supplier_Reliability) AS Avg_Reliability,
        CAST(1.65 * SQRT(
            AVG(Lead_Time_Days) * POWER(STDEV(Quantity_Ordered), 2) +
            POWER(AVG(Quantity_Ordered), 2) * POWER(STDEV(Lead_Time_Days), 2)
        ) AS INT) AS Recommended_Safety_Stock,
        CAST(
            (AVG(Quantity_Ordered) * AVG(Lead_Time_Days) / 30) +
            1.65 * SQRT(
                AVG(Lead_Time_Days) * POWER(STDEV(Quantity_Ordered), 2) +
                POWER(AVG(Quantity_Ordered), 2) * POWER(STDEV(Lead_Time_Days), 2)
            )
        AS INT) AS Recommended_Reorder_Point,
        COUNT(*) AS Sample_Size
    FROM [Healthcare ].[dbo].[Hospital_Supply_Chain_Data]
    GROUP BY Item_Category, Supplier
    HAVING COUNT(*) >= 10  
)
SELECT 
    Item_Category,
    Supplier,
    Avg_Demand,
    Avg_Lead_Time,
    Recommended_Safety_Stock,
    Recommended_Reorder_Point,
    Sample_Size,
    CASE 
        WHEN Avg_Reliability < 0.7 THEN 'Increase safety stock by 20%'
        WHEN Lead_Time_Variability > 5 THEN 'Increase safety stock by 15%'
        ELSE 'Use recommended levels'
    END AS Special_Considerations
FROM ReorderPointCalculation
ORDER BY Item_Category, Supplier;
GO

/** Generates a high-level executive dashboard of supply chain health, consolidating total spend, average reliability,and key KPI percentages for stockouts, 
overstocking, and utilization **/

DECLARE @TotalTransactions INT;
DECLARE @TotalSpending DECIMAL(18,2);
DECLARE @AvgReliability DECIMAL(4,2);
DECLARE @StockoutRiskCount INT;
DECLARE @OverstockCount INT;
DECLARE @LowUtilizationCount INT;

SELECT @TotalTransactions = COUNT(*) FROM [Healthcare ].[dbo].[Hospital_Supply_Chain_Data];
SELECT @TotalSpending = SUM(Unit_Cost * Quantity_Ordered) FROM [Healthcare ].[dbo].[Hospital_Supply_Chain_Data];
SELECT @AvgReliability = AVG(Supplier_Reliability) FROM [Healthcare ].[dbo].[Hospital_Supply_Chain_Data];
SELECT @StockoutRiskCount = COUNT(*) FROM [Healthcare ].[dbo].[Hospital_Supply_Chain_Data] WHERE Stock_Level < Quantity_Ordered;
SELECT @OverstockCount = COUNT(*) FROM [Healthcare ].[dbo].[Hospital_Supply_Chain_Data] WHERE Stock_Level > Quantity_Ordered * 2;
SELECT @LowUtilizationCount = COUNT(*) FROM [Healthcare ].[dbo].[Hospital_Supply_Chain_Data] WHERE Utilization_Rate < 0.3;

SELECT 
    'Supply Chain Health Dashboard' AS Report_Section,
    @TotalTransactions AS Total_Transactions,
    '$' + CAST(@TotalSpending AS VARCHAR(20)) AS Total_Procurement_Value,
    CAST(@AvgReliability * 100 AS DECIMAL(5,2)) AS Avg_Supplier_Reliability_Percentage,
    @StockoutRiskCount AS Items_At_Stockout_Risk,
    CAST(@StockoutRiskCount * 100.0 / @TotalTransactions AS DECIMAL(5,2)) AS Stockout_Risk_Percentage,
    @OverstockCount AS Overstocked_Items,
    CAST(@OverstockCount * 100.0 / @TotalTransactions AS DECIMAL(5,2)) AS Overstock_Percentage,
    @LowUtilizationCount AS Low_Utilization_Items,
    CAST(@LowUtilizationCount * 100.0 / @TotalTransactions AS DECIMAL(5,2)) AS Low_Utilization_Percentage;
GO

/** Aggregates and prioritizes top-tier supply chain issues into a ranked action plan, quantifying the financial impact and recommended interventions for 
each risk category **/

SELECT 
    ROW_NUMBER() OVER (ORDER BY Priority_Score DESC) AS Action_Priority,
    Action_Category,
    Issue_Description,
    Affected_Transactions,
    Financial_Impact,
    Recommended_Action
FROM (
    SELECT 
        1 AS Priority_Score,
        'CRITICAL: Stockout Risk' AS Action_Category,
        'Items with stock below 50% of order quantity' AS Issue_Description,
        COUNT(*) AS Affected_Transactions,
        '$' + CAST(SUM(Unit_Cost * (Quantity_Ordered - Stock_Level)) AS VARCHAR(20)) AS Financial_Impact,
        'Immediate procurement required for ' + CAST(COUNT(*) AS VARCHAR(10)) + ' items' AS Recommended_Action
    FROM [Healthcare ].[dbo].[Hospital_Supply_Chain_Data]
    WHERE Stock_Level < Quantity_Ordered * 0.5
    
    UNION ALL
    
    -- Supplier reliability
    SELECT 
        2 AS Priority_Score,
        'HIGH: Supplier Reliability' AS Action_Category,
        'Orders from unreliable suppliers (reliability < 70%)' AS Issue_Description,
        COUNT(*) AS Affected_Transactions,
        '$' + CAST(SUM(Unit_Cost * Quantity_Ordered) AS VARCHAR(20)) AS Financial_Impact,
        'Review and diversify supplier base for critical items' AS Recommended_Action
    FROM [Healthcare ].[dbo].[Hospital_Supply_Chain_Data]
    WHERE Supplier_Reliability < 0.7
    
    UNION ALL
    
    -- Overstock with low utilization
    SELECT 
        3 AS Priority_Score,
        'MEDIUM: Inventory Waste' AS Action_Category,
        'Overstocked items with low utilization' AS Issue_Description,
        COUNT(*) AS Affected_Transactions,
        '$' + CAST(SUM(Unit_Cost * (Stock_Level - Quantity_Ordered)) AS VARCHAR(20)) AS Financial_Impact,
        'Reduce order quantities or redistribute excess stock' AS Recommended_Action
    FROM [Healthcare ].[dbo].[Hospital_Supply_Chain_Data]
    WHERE Stock_Level > Quantity_Ordered * 2 AND Utilization_Rate < 0.3
    
    UNION ALL
    
    -- Long lead times
    SELECT 
        4 AS Priority_Score,
        'MEDIUM: Lead Time Issues' AS Action_Category,
        'Items with lead times over 15 days' AS Issue_Description,
        COUNT(*) AS Affected_Transactions,
        'Affects ' + CAST(COUNT(*) AS VARCHAR(10)) + ' transactions' AS Financial_Impact,
        'Negotiate faster delivery or find alternative suppliers' AS Recommended_Action
    FROM [Healthcare ].[dbo].[Hospital_Supply_Chain_Data]
    WHERE Lead_Time_Days > 15
) AS ActionItems
ORDER BY Priority_Score;
GO
