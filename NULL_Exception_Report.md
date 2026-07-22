# NULL Exception Report — ECOMDB.RAW.SUPERSTORE

## Overview

| Metric | Value |
|--------|-------|
| **Table** | `ECOMDB.RAW.SUPERSTORE` |
| **Total Rows** | 9,999 |
| **Total Columns** | 21 |
| **Columns with NULLs** | 19 |
| **Clean Columns** | 2 |
| **Report Date** | 2026-07-22 |

---

## Severity Thresholds

| Severity | Rule |
|----------|------|
| PASS | 0 NULLs |
| LOW | ≤ 10% NULLs |
| WARNING | 10–50% NULLs |
| CRITICAL | > 50% NULLs |

---

## Exception Details

| Column | NULL Count | Total Rows | NULL % | Severity |
|--------|:---:|:---:|:---:|:---:|
| ROW_ID | 0 | 9,999 | 0.00% | PASS |
| CUSTOMER_NAME | 0 | 9,999 | 0.00% | PASS |
| ORDER_DATE | 5 | 9,999 | 0.05% | LOW |
| SHIP_DATE | 5 | 9,999 | 0.05% | LOW |
| SHIP_MODE | 5 | 9,999 | 0.05% | LOW |
| SEGMENT | 5 | 9,999 | 0.05% | LOW |
| POSTAL_CODE | 5 | 9,999 | 0.05% | LOW |
| CATEGORY | 5 | 9,999 | 0.05% | LOW |
| Sub-Category | 5 | 9,999 | 0.05% | LOW |
| PRODUCT_NAME | 5 | 9,999 | 0.05% | LOW |
| QUANTITY | 5 | 9,999 | 0.05% | LOW |
| PROFIT | 5 | 9,999 | 0.05% | LOW |
| STATE | 3 | 9,999 | 0.03% | LOW |
| DISCOUNT | 3 | 9,999 | 0.03% | LOW |
| COUNTRY | 2 | 9,999 | 0.02% | LOW |
| ORDER_ID | 1 | 9,999 | 0.01% | LOW |
| CUSTOMER_ID | 1 | 9,999 | 0.01% | LOW |
| CITY | 1 | 9,999 | 0.01% | LOW |
| REGION | 1 | 9,999 | 0.01% | LOW |
| PRODUCT_ID | 1 | 9,999 | 0.01% | LOW |
| SALES | 1 | 9,999 | 0.01% | LOW |

---

## Key Findings

1. **Only 2 columns are fully clean:** `ROW_ID` and `CUSTOMER_NAME`
2. **10 columns have exactly 5 NULLs** — these correspond to the test rows (99901–99905) inserted with partial data
3. **No CRITICAL or WARNING issues** — all NULL percentages are below 0.1%
4. **STATE and DISCOUNT** have 3 NULLs each (intentional test data)
5. **COUNTRY** has 2 NULLs, and 6 columns have exactly 1 NULL each

---

## Recommendations

| Priority | Action |
|----------|--------|
| 1 | Add NOT NULL constraints on `ROW_ID` and `CUSTOMER_NAME` (confirmed clean) |
| 2 | Investigate the 5-NULL rows — likely test data that should be removed before production |
| 3 | Apply `COALESCE` defaults in staging layer for columns like STATE, DISCOUNT |
| 4 | Add dbt tests (`not_null`) on critical columns: `ROW_ID`, `ORDER_ID`, `CUSTOMER_ID` |

---

## SQL Query Used

```sql
WITH total AS (
    SELECT COUNT(*) AS total_rows FROM ECOMDB.RAW.SUPERSTORE
),
null_counts AS (
    SELECT 'ROW_ID' AS COLUMN_NAME, COUNT_IF(ROW_ID IS NULL) AS NULL_COUNT FROM ECOMDB.RAW.SUPERSTORE
    UNION ALL SELECT 'ORDER_ID', COUNT_IF(ORDER_ID IS NULL) FROM ECOMDB.RAW.SUPERSTORE
    UNION ALL SELECT 'ORDER_DATE', COUNT_IF(ORDER_DATE IS NULL) FROM ECOMDB.RAW.SUPERSTORE
    UNION ALL SELECT 'SHIP_DATE', COUNT_IF(SHIP_DATE IS NULL) FROM ECOMDB.RAW.SUPERSTORE
    UNION ALL SELECT 'SHIP_MODE', COUNT_IF(SHIP_MODE IS NULL) FROM ECOMDB.RAW.SUPERSTORE
    UNION ALL SELECT 'CUSTOMER_ID', COUNT_IF(CUSTOMER_ID IS NULL) FROM ECOMDB.RAW.SUPERSTORE
    UNION ALL SELECT 'CUSTOMER_NAME', COUNT_IF(CUSTOMER_NAME IS NULL) FROM ECOMDB.RAW.SUPERSTORE
    UNION ALL SELECT 'SEGMENT', COUNT_IF(SEGMENT IS NULL) FROM ECOMDB.RAW.SUPERSTORE
    UNION ALL SELECT 'COUNTRY', COUNT_IF(COUNTRY IS NULL) FROM ECOMDB.RAW.SUPERSTORE
    UNION ALL SELECT 'CITY', COUNT_IF(CITY IS NULL) FROM ECOMDB.RAW.SUPERSTORE
    UNION ALL SELECT 'STATE', COUNT_IF(STATE IS NULL) FROM ECOMDB.RAW.SUPERSTORE
    UNION ALL SELECT 'POSTAL_CODE', COUNT_IF(POSTAL_CODE IS NULL) FROM ECOMDB.RAW.SUPERSTORE
    UNION ALL SELECT 'REGION', COUNT_IF(REGION IS NULL) FROM ECOMDB.RAW.SUPERSTORE
    UNION ALL SELECT 'PRODUCT_ID', COUNT_IF(PRODUCT_ID IS NULL) FROM ECOMDB.RAW.SUPERSTORE
    UNION ALL SELECT 'CATEGORY', COUNT_IF(CATEGORY IS NULL) FROM ECOMDB.RAW.SUPERSTORE
    UNION ALL SELECT 'Sub-Category', COUNT_IF("Sub-Category" IS NULL) FROM ECOMDB.RAW.SUPERSTORE
    UNION ALL SELECT 'PRODUCT_NAME', COUNT_IF(PRODUCT_NAME IS NULL) FROM ECOMDB.RAW.SUPERSTORE
    UNION ALL SELECT 'SALES', COUNT_IF(SALES IS NULL) FROM ECOMDB.RAW.SUPERSTORE
    UNION ALL SELECT 'QUANTITY', COUNT_IF(QUANTITY IS NULL) FROM ECOMDB.RAW.SUPERSTORE
    UNION ALL SELECT 'DISCOUNT', COUNT_IF(DISCOUNT IS NULL) FROM ECOMDB.RAW.SUPERSTORE
    UNION ALL SELECT 'PROFIT', COUNT_IF(PROFIT IS NULL) FROM ECOMDB.RAW.SUPERSTORE
)
SELECT
    n.COLUMN_NAME,
    n.NULL_COUNT,
    t.total_rows AS TOTAL_ROWS,
    ROUND(n.NULL_COUNT * 100.0 / t.total_rows, 2) AS NULL_PERCENT,
    CASE
        WHEN n.NULL_COUNT = 0 THEN 'PASS'
        WHEN n.NULL_COUNT * 100.0 / t.total_rows > 50 THEN 'CRITICAL'
        WHEN n.NULL_COUNT * 100.0 / t.total_rows > 10 THEN 'WARNING'
        ELSE 'LOW'
    END AS SEVERITY
FROM null_counts n
CROSS JOIN total t
ORDER BY NULL_COUNT DESC;
```
