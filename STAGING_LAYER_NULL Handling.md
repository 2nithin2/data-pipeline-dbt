# NULL Handling in Snowflake — Complete Guide

## Overview

NULL represents the **absence of a value** in SQL. It is not zero, not an empty string — it is unknown. Any operation involving NULL propagates NULL unless explicitly handled.

**Key rule:** `NULL` is not equal to anything — not even itself. `NULL = NULL` returns `NULL` (not TRUE).

---

## Test Data Setup

```sql
INSERT INTO ECOMDB.RAW.SUPERSTORE (ROW_ID, CUSTOMER_ID, CUSTOMER_NAME, CITY, STATE, COUNTRY, REGION, ORDER_ID, PRODUCT_ID, SALES, DISCOUNT)
VALUES
    (99901, 'TEST-1', 'Henderson Customer', 'Henderson', 'Kentucky', 'United States', 'South', 'ORD-901', 'PROD-901', 500.00, 0.10),
    (99902, 'TEST-2', 'Houston Customer', 'Houston', NULL, 'United States', 'South', 'ORD-902', 'PROD-902', 1200.00, 0.20),
    (99903, 'TEST-3', 'Mystery Customer', 'Dallas', NULL, NULL, 'Central', 'ORD-903', 'PROD-903', 800.00, NULL),
    (99904, 'TEST-4', 'Ghost Customer', NULL, NULL, NULL, NULL, 'ORD-904', 'PROD-904', 300.00, NULL),
    (99905, NULL, 'No ID Customer', 'Austin', 'Texas', 'United States', 'South', NULL, NULL, NULL, NULL);
```

| ROW_ID | CUSTOMER_ID | CITY | STATE | COUNTRY | DISCOUNT |
|--------|-------------|------|-------|---------|----------|
| 99901 | TEST-1 | Henderson | Kentucky | United States | 0.10 |
| 99902 | TEST-2 | Houston | **NULL** | United States | 0.20 |
| 99903 | TEST-3 | Dallas | **NULL** | **NULL** | **NULL** |
| 99904 | TEST-4 | **NULL** | **NULL** | **NULL** | **NULL** |
| 99905 | **NULL** | Austin | Texas | United States | **NULL** |

---

## 1. COALESCE — Replace NULL with a Default

### Syntax

```sql
COALESCE(expr1, expr2, expr3, ...)
-- Returns the FIRST non-NULL argument from left to right
```

### Example: Basic NULL Replacement

```sql
SELECT CITY, STATE, COALESCE(STATE, 'Unknown') AS STATE_CLEAN
FROM ECOMDB.RAW.SUPERSTORE
WHERE ROW_ID IN (99901, 99902, 99903, 99904, 99905);
```

| CITY | STATE | STATE_CLEAN |
|------|-------|-------------|
| Henderson | Kentucky | Kentucky |
| Houston | NULL | **Unknown** |
| Dallas | NULL | **Unknown** |
| NULL | NULL | **Unknown** |
| Austin | Texas | Texas |

### Example: Multiple Fallbacks

```sql
SELECT COALESCE(STATE, CITY, COUNTRY, 'No Location') AS BEST_LOCATION
FROM ECOMDB.RAW.SUPERSTORE
WHERE ROW_ID IN (99901, 99902, 99903, 99904, 99905);
```

| CITY | STATE | COUNTRY | BEST_LOCATION | Why |
|------|-------|---------|---------------|-----|
| Henderson | Kentucky | United States | Kentucky | STATE found first |
| Houston | NULL | United States | Houston | STATE NULL → falls to CITY |
| Dallas | NULL | NULL | Dallas | STATE NULL → falls to CITY |
| NULL | NULL | NULL | No Location | All NULL → uses literal default |
| Austin | Texas | United States | Texas | STATE found first |

---

## 2. Concatenation Approaches — Handling NULLs in Strings

### Problem: CONCAT breaks on NULL

```sql
CONCAT('Houston', ', ', NULL, ', ', 'United States')
-- Result: NULL (entire output is NULL!)
```

### Approach A: CONCAT + COALESCE (BAD)

```sql
CONCAT(COALESCE(CITY,''), ', ', COALESCE(STATE,''), ', ', COALESCE(COUNTRY,''))
```

| CITY | STATE | Result |
|------|-------|--------|
| Houston | NULL | `Houston, , United States` |
| NULL | NULL | `, ,` |

**Problem:** Double commas where NULLs were. Ugly output.

---

### Approach B: CONCAT_WS (GOOD)

```sql
CONCAT_WS(', ', CITY, STATE, COUNTRY)
-- "Concat With Separator" — automatically skips NULL values
```

| CITY | STATE | Result |
|------|-------|--------|
| Houston | NULL | `Houston, United States` |
| NULL | NULL | ` ` (empty string) |

**Better:** No double commas. But returns empty string when all values are NULL.

---

### Approach C: ARRAY_CONSTRUCT_COMPACT + ARRAY_TO_STRING (BEST — Production Standard)

```sql
ARRAY_TO_STRING(ARRAY_CONSTRUCT_COMPACT(CITY, STATE, COUNTRY), ', ')
```

| CITY | STATE | Result |
|------|-------|--------|
| Houston | NULL | `Houston, United States` |
| NULL | NULL | **NULL** |

**Best for production.**

---

### Comparison Table

| Method | Double Commas? | All-NULL Result | Scalable? | Production? |
|--------|:-:|:-:|:-:|:-:|
| `CONCAT + COALESCE` | Yes | `, ,` | No (COALESCE per column) | **NO** |
| `CONCAT_WS` | No | `''` (empty string) | Yes | Acceptable |
| **`ARRAY_CONSTRUCT_COMPACT + ARRAY_TO_STRING`** | **No** | **NULL** | **Yes** | **YES** |

### Why ARRAY_CONSTRUCT_COMPACT Wins

1. **NULL in = NULL out** — If all fields are NULL, result is NULL (semantically correct: "no address exists")
2. **No double commas** — Removes NULLs BEFORE joining
3. **Scalable** — Adding fields = adding to the array (no extra COALESCE per column)
4. **Readable** — Clear intent: "build list, skip nulls, join with comma"
5. **Deterministic** — Same input always produces same output

### How It Works Internally

```
Step 1: ARRAY_CONSTRUCT_COMPACT('Houston', NULL, 'United States')
        → ['Houston', 'United States']     ← NULL removed from array

Step 2: ARRAY_TO_STRING(['Houston', 'United States'], ', ')
        → 'Houston, United States'          ← joined with separator
```

### Production SQL (from stg_customer model)

```sql
ARRAY_TO_STRING(
    ARRAY_CONSTRUCT_COMPACT(CITY, STATE, COUNTRY),
    ', '
) AS FULL_ADDRESS
```

---

## 3. COALESCE with Numeric Columns

### Formula: Net Sales Calculation

```sql
SALES * (1 - COALESCE(DISCOUNT, 0)) AS NET_SALES
```

### Step-by-Step

```
SALES = 1200, DISCOUNT = 0.20:
  Step 1: COALESCE(0.20, 0) → 0.20
  Step 2: 1 - 0.20 → 0.80
  Step 3: 1200 * 0.80 → 960.00

SALES = 800, DISCOUNT = NULL:
  Step 1: COALESCE(NULL, 0) → 0
  Step 2: 1 - 0 → 1
  Step 3: 800 * 1 → 800.00 (full price)

Without COALESCE:
  Step 1: 1 - NULL → NULL
  Step 2: 800 * NULL → NULL (calculation lost!)
```

### Expected Output

| ORDER_ID | SALES | DISCOUNT | DISCOUNT_CLEAN | NET_SALES |
|----------|-------|----------|:-:|-----------|
| ORD-901 | 500.00 | 0.10 | 0.10 | 450.00 |
| ORD-902 | 1200.00 | 0.20 | 0.20 | 960.00 |
| ORD-903 | 800.00 | NULL | **0.00** | **800.00** |
| ORD-904 | 300.00 | NULL | **0.00** | **300.00** |
| NULL | NULL | NULL | **0.00** | NULL |

> Last row: SALES is NULL so NET_SALES is NULL — COALESCE can't save a calculation when the base value itself is missing.

---

## 4. COALESCE Before Hashing (MD5 Business Keys)

### Problem

```sql
MD5(NULL) = NULL  -- No hash generated!
```

### Solution

```sql
MD5(COALESCE(CUSTOMER_ID, '')) AS CUSTOMER_BK
```

### Expected Output

| CUSTOMER_ID | CUSTOMER_BK |
|-------------|-------------|
| TEST-1 | `a5b9f...` (hash of 'TEST-1') |
| TEST-2 | `c3d7e...` (hash of 'TEST-2') |
| NULL | `d41d8cd98f00...` (hash of empty string) |

### Production Best Practice for Business Keys

| Scenario | Approach |
|----------|----------|
| Column guaranteed NOT NULL (test enforced) | `MD5(CUSTOMER_ID)` |
| Defensive coding (safety net) | `MD5(COALESCE(CUSTOMER_ID, ''))` |
| Column CAN be NULL, need unique keys | `MD5(COALESCE(CUSTOMER_ID, 'NULL_' \|\| ROW_ID::STRING))` |
| Never use | `MD5(COALESCE(CUSTOMER_ID, NULL))` — does nothing |

> **Warning:** `MD5(COALESCE(col, ''))` gives ALL null rows the same hash (`d41d8...`). This causes join collisions. If nulls are possible, include a unique identifier in the hash.

---

## 5. COALESCE in WHERE Clause

### Find Rows Where STATE is NULL

```sql
SELECT ROW_ID, CITY, STATE, COUNTRY
FROM ECOMDB.RAW.SUPERSTORE
WHERE COALESCE(STATE, 'MISSING') = 'MISSING';
```

### Logic

```
Row 99901: COALESCE('Kentucky', 'MISSING') = 'Kentucky' ≠ 'MISSING' → excluded
Row 99902: COALESCE(NULL, 'MISSING') = 'MISSING' = 'MISSING' → included
Row 99904: COALESCE(NULL, 'MISSING') = 'MISSING' = 'MISSING' → included
```

### Better Alternative (use IS NULL directly)

```sql
-- More readable and performant:
WHERE STATE IS NULL
```

> Use `COALESCE` in WHERE only when you need complex multi-value logic. For simple NULL checks, `IS NULL` / `IS NOT NULL` is preferred.

---

## 6. COALESCE vs NVL vs IFNULL

### Comparison

| Function | Standard | Max Args | Portable? | Production? |
|----------|----------|:---:|:-:|:-:|
| **COALESCE** | ANSI SQL | 2+ | All databases | **YES** |
| NVL | Oracle/Snowflake | 2 | No | Avoid |
| IFNULL | MySQL/Snowflake | 2 | No | Avoid |

### Example

```sql
SELECT
    STATE,
    COALESCE(STATE, 'N/A') AS USING_COALESCE,  -- ANSI standard
    NVL(STATE, 'N/A')      AS USING_NVL,        -- Oracle-style
    IFNULL(STATE, 'N/A')   AS USING_IFNULL      -- MySQL-style
FROM ECOMDB.RAW.SUPERSTORE;
```

All three produce identical results for 2 arguments. The difference is portability and extensibility.

### Production Rule

**Always use COALESCE:**
- Works on Snowflake, Postgres, BigQuery, Redshift, Databricks, SQL Server
- Supports multiple fallbacks: `COALESCE(a, b, c, d, 'default')`
- Every SQL developer knows it regardless of their DB background
- Migration-safe if you ever move platforms

---

## 7. When to Use What

| Scenario | Function | Example |
|----------|----------|---------|
| Replace NULL with a default | `COALESCE` | `COALESCE(STATE, 'Unknown')` |
| Multiple fallback values | `COALESCE` | `COALESCE(STATE, CITY, 'N/A')` |
| NULL-safe math | `COALESCE` | `SALES * (1 - COALESCE(DISCOUNT, 0))` |
| Protect hash from NULL | `COALESCE` | `MD5(COALESCE(ID, ''))` |
| Build concatenated strings | `ARRAY_CONSTRUCT_COMPACT` | `ARRAY_TO_STRING(ARRAY_CONSTRUCT_COMPACT(...), ', ')` |
| Simple NULL check in WHERE | `IS NULL` | `WHERE STATE IS NULL` |
| Quick ad-hoc (not production) | `NVL` / `IFNULL` | `NVL(STATE, 'N/A')` |

---

## Summary: Production Patterns

```sql
-- String concatenation (skip NULLs cleanly)
ARRAY_TO_STRING(ARRAY_CONSTRUCT_COMPACT(CITY, STATE, COUNTRY), ', ') AS FULL_ADDRESS

-- Numeric safety (NULL → 0 for calculations)
SALES * (1 - COALESCE(DISCOUNT, 0)) AS NET_SALES

-- Hash safety (NULL → deterministic input)
MD5(COALESCE(CUSTOMER_ID, '')) AS CUSTOMER_BK

-- Default value replacement
COALESCE(STATE, 'Unknown') AS STATE_CLEAN

-- Multiple fallbacks
COALESCE(STATE, CITY, COUNTRY, 'No Location') AS BEST_LOCATION
```
