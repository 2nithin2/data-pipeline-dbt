# Replacing Missing Values with COALESCE in Snowflake

Exercises for handling NULL values using `ECOMDB.RAW.SUPERSTORE` test data.

## Test Data Setup

The exercises use 5 pre-inserted rows with various NULL patterns:

| ROW_ID | Description |
|--------|-------------|
| 99901  | All values present (no NULLs) |
| 99902  | STATE is NULL |
| 99903  | STATE and COUNTRY are NULL |
| 99904  | CITY, STATE, COUNTRY all NULL |
| 99905  | CUSTOMER_ID is NULL, DISCOUNT is NULL |

```sql
-- Verify test rows
SELECT ROW_ID, CUSTOMER_ID, CUSTOMER_NAME, CITY, STATE, COUNTRY, REGION, ORDER_ID, SALES, DISCOUNT
FROM ECOMDB.RAW.SUPERSTORE
WHERE ROW_ID IN (99901, 99902, 99903, 99904, 99905);
```

---

## Exercise 1: Replace NULL STATE with 'Unknown'

**Concept:** Basic single-column NULL replacement.

```sql
SELECT
    CITY,
    STATE,
    COALESCE(STATE, 'Unknown') AS STATE_CLEAN
FROM ECOMDB.RAW.SUPERSTORE
WHERE ROW_ID IN (99901, 99902, 99903, 99904, 99905);
```

| CITY | STATE | STATE_CLEAN |
|------|-------|-------------|
| Henderson | Kentucky | Kentucky |
| Houston | NULL | Unknown |
| Dallas | NULL | Unknown |
| NULL | NULL | Unknown |
| Austin | Texas | Texas |

---

## Exercise 2: Replace NULL CUSTOMER_ID with a Surrogate Key

**Concept:** Generate a fallback ID using concatenation when the original is NULL.

```sql
SELECT
    ROW_ID,
    CUSTOMER_ID,
    COALESCE(CUSTOMER_ID, 'UNKNOWN-' || ROW_ID::STRING) AS ID_CLEAN
FROM ECOMDB.RAW.SUPERSTORE
WHERE ROW_ID IN (99901, 99902, 99903, 99904, 99905);
```

| ROW_ID | CUSTOMER_ID | ID_CLEAN |
|--------|-------------|----------|
| 99901 | TEST-1 | TEST-1 |
| 99905 | NULL | UNKNOWN-99905 |

---

## Exercise 3: Cascading Fallback for Location

**Concept:** COALESCE with multiple columns — first non-NULL wins.

```sql
SELECT
    CITY,
    STATE,
    COUNTRY,
    REGION,
    COALESCE(CITY, STATE, COUNTRY, REGION, 'No Location') AS BEST_LOCATION
FROM ECOMDB.RAW.SUPERSTORE
WHERE ROW_ID IN (99901, 99902, 99903, 99904, 99905);
```

| CITY | STATE | COUNTRY | REGION | BEST_LOCATION |
|------|-------|---------|--------|---------------|
| Henderson | Kentucky | United States | South | Henderson |
| NULL | NULL | NULL | NULL | No Location |

---

## Exercise 4: Replace NULL DISCOUNT with 0, Calculate NET_SALES

**Concept:** Prevent NULL from breaking arithmetic operations.

```sql
SELECT
    ORDER_ID,
    SALES,
    DISCOUNT,
    COALESCE(DISCOUNT, 0) AS DISCOUNT_CLEAN,
    SALES * (1 - COALESCE(DISCOUNT, 0)) AS NET_SALES
FROM ECOMDB.RAW.SUPERSTORE
WHERE ROW_ID IN (99901, 99902, 99903, 99904, 99905);
```

> **Key insight:** `SALES * (1 - NULL)` = NULL. COALESCE prevents NULL from propagating through calculations.

---

## Exercise 5: Replace NULL SALES with Average (Window Function)

**Concept:** Fill NULLs with a computed aggregate using a window function.

```sql
SELECT
    ORDER_ID,
    SALES,
    COALESCE(SALES, AVG(SALES) OVER()) AS SALES_FILLED
FROM ECOMDB.RAW.SUPERSTORE
WHERE ROW_ID IN (99901, 99902, 99903, 99904, 99905);
```

| ORDER_ID | SALES | SALES_FILLED |
|----------|-------|--------------|
| ORD-901 | 500.00 | 500.00 |
| NULL | NULL | 700.00 |

> `AVG(SALES) OVER()` computes the average across all non-NULL sales in the window, then COALESCE uses it as the fallback.

---

## Exercise 6: Build FULL_ADDRESS Skipping NULLs (Production Pattern)

**Concept:** Use `ARRAY_CONSTRUCT_COMPACT` to skip NULLs instead of getting ugly `, , ` in output.

```sql
SELECT
    CITY,
    STATE,
    COUNTRY,
    ARRAY_TO_STRING(
        ARRAY_CONSTRUCT_COMPACT(CITY, STATE, COUNTRY),
        ', '
    ) AS FULL_ADDRESS
FROM ECOMDB.RAW.SUPERSTORE
WHERE ROW_ID IN (99901, 99902, 99903, 99904, 99905);
```

| CITY | STATE | COUNTRY | FULL_ADDRESS |
|------|-------|---------|--------------|
| Henderson | Kentucky | United States | Henderson, Kentucky, United States |
| Houston | NULL | United States | Houston, United States |
| Dallas | NULL | NULL | Dallas |
| NULL | NULL | NULL | NULL |

---

## Exercise 7: COALESCE Before MD5 Hashing

**Concept:** `MD5(NULL)` returns NULL. COALESCE ensures every row gets a valid hash.

```sql
SELECT
    CUSTOMER_ID,
    MD5(CUSTOMER_ID) AS BK_WITHOUT_COALESCE,
    MD5(COALESCE(CUSTOMER_ID, '')) AS BK_WITH_COALESCE
FROM ECOMDB.RAW.SUPERSTORE
WHERE ROW_ID IN (99901, 99902, 99903, 99904, 99905);
```

| CUSTOMER_ID | BK_WITHOUT_COALESCE | BK_WITH_COALESCE |
|-------------|---------------------|------------------|
| TEST-1 | abc123... | abc123... |
| NULL | NULL | d41d8cd98f00b204e98... |

---

## Exercise 8: Compare All 3 Concat Approaches

**Concept:** Understand the behavioral differences between concatenation methods when NULLs are present.

```sql
SELECT
    ROW_ID,
    CONCAT(COALESCE(CITY,''), ', ', COALESCE(STATE,''), ', ', COALESCE(COUNTRY,'')) AS CONCAT_COALESCE,
    CONCAT_WS(', ', CITY, STATE, COUNTRY) AS CONCAT_WS_RESULT,
    ARRAY_TO_STRING(ARRAY_CONSTRUCT_COMPACT(CITY, STATE, COUNTRY), ', ') AS ARRAY_PRODUCTION
FROM ECOMDB.RAW.SUPERSTORE
WHERE ROW_ID IN (99901, 99902, 99903, 99904, 99905);
```

| Approach | NULL handling | All-NULL result |
|----------|--------------|-----------------|
| `CONCAT + COALESCE` | Leaves empty separators (`, , `) | `, , ` |
| `CONCAT_WS` | Skips NULLs automatically | Empty string |
| `ARRAY_CONSTRUCT_COMPACT` | Skips NULLs, cleanest output | NULL |

> **Production recommendation:** Use `ARRAY_CONSTRUCT_COMPACT` + `ARRAY_TO_STRING` for the cleanest results.

---

## Exercise 9: Count NULLs Per Row (Data Quality Score)

**Concept:** Measure data completeness per record.

```sql
SELECT
    ROW_ID,
    (IFF(CUSTOMER_ID IS NULL, 1, 0) +
     IFF(CUSTOMER_NAME IS NULL, 1, 0) +
     IFF(CITY IS NULL, 1, 0) +
     IFF(STATE IS NULL, 1, 0) +
     IFF(COUNTRY IS NULL, 1, 0) +
     IFF(REGION IS NULL, 1, 0) +
     IFF(ORDER_ID IS NULL, 1, 0) +
     IFF(SALES IS NULL, 1, 0) +
     IFF(DISCOUNT IS NULL, 1, 0) +
     IFF(PRODUCT_ID IS NULL, 1, 0)) AS NULL_COUNT,
    ROUND((1 - NULL_COUNT / 10.0) * 100, 1) || '%' AS COMPLETENESS
FROM ECOMDB.RAW.SUPERSTORE
WHERE ROW_ID IN (99901, 99902, 99903, 99904, 99905);
```

| ROW_ID | NULL_COUNT | COMPLETENESS |
|--------|------------|--------------|
| 99901 | 0 | 100.0% |
| 99902 | 1 | 90.0% |
| 99903 | 2 | 80.0% |
| 99904 | 4 | 60.0% |
| 99905 | 4 | 60.0% |

---

## Exercise 10: Full Production ETL — Replace ALL Missing Values

**Concept:** A complete staging model with zero NULLs in output.

```sql
SELECT
    ROW_ID,
    COALESCE(CUSTOMER_ID, 'UNKNOWN-' || ROW_ID::STRING) AS CUSTOMER_ID,
    COALESCE(CUSTOMER_NAME, 'Unknown Customer') AS CUSTOMER_NAME,
    COALESCE(CITY, 'Unknown City') AS CITY,
    COALESCE(STATE, 'Unknown State') AS STATE,
    COALESCE(COUNTRY, 'Unknown Country') AS COUNTRY,
    COALESCE(REGION, 'Unknown Region') AS REGION,
    ARRAY_TO_STRING(
        ARRAY_CONSTRUCT_COMPACT(CITY, STATE, COUNTRY),
        ', '
    ) AS FULL_ADDRESS,
    COALESCE(SALES, 0) AS SALES,
    COALESCE(DISCOUNT, 0) AS DISCOUNT,
    COALESCE(SALES, 0) * (1 - COALESCE(DISCOUNT, 0)) AS NET_SALES,
    MD5(COALESCE(CUSTOMER_ID, 'UNKNOWN-' || ROW_ID::STRING)) AS CUSTOMER_BK
FROM ECOMDB.RAW.SUPERSTORE
WHERE ROW_ID IN (99901, 99902, 99903, 99904, 99905);
```

---

## Key Concepts Summary

| Pattern | Use Case |
|---------|----------|
| `COALESCE(col, default)` | Replace NULL with a single fallback value |
| `COALESCE(col1, col2, col3, ...)` | Cascading fallback — first non-NULL wins |
| `COALESCE + AVG() OVER()` | Fill NULL with a computed aggregate |
| `COALESCE + surrogate key` | Generate IDs for NULL records |
| `COALESCE in math` | Prevent NULL from breaking calculations |
| `COALESCE before MD5` | Prevent NULL hash output |
| `ARRAY_CONSTRUCT_COMPACT` | Skip NULLs in concatenation (production) |
| `IFF(col IS NULL, 1, 0)` | Count NULLs for data quality scoring |

---

## Cleanup

```sql
-- Run when done with ALL exercises
DELETE FROM ECOMDB.RAW.SUPERSTORE WHERE ROW_ID IN (99901, 99902, 99903, 99904, 99905);
```
