# String Operations in Staging Layer — Detailed Notes

## Overview

This document covers Snowflake string functions used to build the `stg_customer` dbt model from the `ECOMDB.RAW.SUPERSTORE` table. The goal is to standardize customer data, handle NULLs during concatenation, create a full address column, and generate MD5 business keys.

---

## Source Table: `ECOMDB.RAW.SUPERSTORE`

```sql
CREATE OR REPLACE TABLE SUPERSTORE (
    ROW_ID NUMBER(38,0),
    ORDER_ID VARCHAR(16777216),
    ORDER_DATE DATE,
    SHIP_DATE DATE,
    SHIP_MODE VARCHAR(16777216),
    CUSTOMER_ID VARCHAR(16777216),
    CUSTOMER_NAME VARCHAR(16777216),
    SEGMENT VARCHAR(16777216),
    COUNTRY VARCHAR(16777216),
    CITY VARCHAR(16777216),
    STATE VARCHAR(16777216),
    POSTAL_CODE NUMBER(38,0),
    REGION VARCHAR(16777216),
    PRODUCT_ID VARCHAR(16777216),
    CATEGORY VARCHAR(16777216),
    "Sub-Category" VARCHAR(16777216),
    PRODUCT_NAME VARCHAR(16777216),
    SALES NUMBER(38,4),
    QUANTITY NUMBER(38,0),
    DISCOUNT NUMBER(38,2),
    PROFIT NUMBER(38,4)
);
```

---

## Phase 1: Basic Concatenation with `CONCAT()`

### Syntax

```sql
CONCAT(expr1, expr2, ...)
```

### Example — Customer Summary

```sql
SELECT
    CUSTOMER_ID,
    CUSTOMER_NAME,
    SEGMENT,
    CONCAT(CUSTOMER_ID, ' ', CUSTOMER_NAME, ' ', SEGMENT) AS customer_summary
FROM ecomdb.raw.superstore;
```

### Example — City + State

```sql
SELECT CITY, STATE, CONCAT(CITY, ' CITY is in STATE ', STATE)
FROM ecomdb.raw.superstore;
```

### Problem: NULL Handling

In Snowflake, `CONCAT()` returns **NULL** if **any** argument is NULL.

```sql
-- If STATE is NULL, the entire result is NULL
SELECT CITY, STATE, CONCAT(CITY, ' CITY is in STATE ', STATE) AS output
FROM ecomdb.raw.superstore
WHERE COALESCE(CITY, STATE) IS NULL;
```

---

## Phase 2: Test Data Setup

Insert test rows to demonstrate NULL behavior:

```sql
INSERT INTO ecomdb.raw.superstore (ROW_ID, CUSTOMER_ID, CUSTOMER_NAME, CITY, STATE)
VALUES
    (99901, 'TEST-1', 'Henderson Customer', 'Henderson', 'Kentucky'),
    (99902, 'TEST-2', 'LA Customer', 'Los Angeles', 'California'),
    (99903, 'TEST-3', 'Houston Customer', 'Houston', NULL);
```

Verify:

```sql
SELECT ROW_ID, CITY, STATE
FROM ecomdb.raw.superstore
WHERE ROW_ID IN (99901, 99902, 99903);
```

Test concatenation:

```sql
SELECT CITY, STATE, CONCAT(CITY, ' CITY is in STATE ', STATE) AS OUTPUT
FROM ecomdb.raw.superstore
WHERE ROW_ID IN (99901, 99902, 99903);
```

**Output:**

| CITY | STATE | OUTPUT |
|------|-------|--------|
| Henderson | Kentucky | Henderson CITY is in STATE Kentucky |
| Los Angeles | California | Los Angeles CITY is in STATE California |
| Houston | NULL | **NULL** |

Row 99903 returns NULL because STATE is NULL — this is the core problem to solve.

---

## Phase 3: Solutions for NULL-Safe Concatenation

### Solution 1: `CONCAT_WS()` — Concat With Separator

```sql
CONCAT_WS(separator, expr1, expr2, ...)
```

```sql
SELECT city, state, CONCAT_WS(' ', 'city is state', city, state) AS output
FROM ecomdb.raw.superstore
WHERE row_id IN (99901, 99902, 99903);
```

> **Note:** In Snowflake, `CONCAT_WS` still returns NULL if any argument is NULL. It only skips empty strings, not NULLs.

---

### Solution 2: `IFF()` — Conditional Logic

```sql
IFF(<condition>, <expr_if_true>, <expr_if_false>)
```

```sql
SELECT
    city,
    state,
    IFF(state IS NULL,
        city,
        city || ' is city and in state ' || state) AS output
FROM ecomdb.raw.superstore
WHERE row_id IN (99901, 99902, 99903);
```

**How it works:** If STATE is NULL, return just the city. Otherwise, return the full concatenated string.

---

### Solution 3: `COALESCE()` — Replace NULL Before Concat

```sql
COALESCE(expr1, expr2, ...) -- Returns first non-NULL from left to right
```

```sql
SELECT city, state, CONCAT_WS(' ', 'city is state', city, COALESCE(state, '')) AS output
FROM ecomdb.raw.superstore
WHERE row_id IN (99901, 99902, 99903);
```

**How it works:** `COALESCE(state, '')` replaces NULL with an empty string before passing to `CONCAT_WS`.

---

### Solution 4: Combined `IFF` + `COALESCE`

```sql
SELECT
    CITY,
    STATE,
    IFF(
        STATE IS NULL,
        CITY,
        CONCAT(CITY, ' city is state ', COALESCE(STATE, ''))
    ) AS OUTPUT
FROM ECOMDB.RAW.SUPERSTORE
WHERE row_id IN (99901, 99902, 99903);
```

---

## Phase 4: Full Address Column — The Production Approach

### Best Solution: `ARRAY_CONSTRUCT_COMPACT` + `ARRAY_TO_STRING`

This is the cleanest approach and what's used in the `stg_customer` dbt model.

#### Step 1: `ARRAY_CONSTRUCT_COMPACT()`

Builds an array from its arguments, **automatically excluding NULLs**.

```sql
SELECT ARRAY_CONSTRUCT_COMPACT(city, state) FROM ecomdb.raw.superstore;
-- Output: ["Henderson", "Kentucky"]
```

#### Step 2: `ARRAY_TO_STRING()`

Converts the array back to a string with a delimiter.

```sql
SELECT
    ARRAY_TO_STRING(
        ARRAY_CONSTRUCT_COMPACT(CITY, STATE, COUNTRY, ROW_ID),
        ', '
    ) AS FULL_ADDRESS
FROM ECOMDB.RAW.SUPERSTORE
WHERE row_id IN (99901, 99902, 99903);
```

**Output:**

| FULL_ADDRESS |
|---|
| Henderson, Kentucky, United States, 99901 |
| Los Angeles, California, United States, 99902 |
| Houston, United States, 99903 |

> Row 99903 cleanly skips the NULL state — no extra commas, no NULL output.

### Why This Is Best

| Approach | Handles NULL? | Clean Output? | Scalable? |
|----------|:---:|:---:|:---:|
| `CONCAT()` | No | No | Yes |
| `CONCAT_WS()` | No | Partial | Yes |
| `IFF()` | Yes | Yes | No (verbose for many columns) |
| `COALESCE()` + `CONCAT` | Yes | Partial (empty strings) | Partial |
| **`ARRAY_CONSTRUCT_COMPACT` + `ARRAY_TO_STRING`** | **Yes** | **Yes** | **Yes** |

---

## Phase 5: MD5 Business Key

### Purpose

Create a deterministic, reproducible hash key from one or more columns. Used for joining records across models without relying on natural keys.

### Pattern

```sql
MD5(CONCAT_WS('|', COALESCE(col1, ''), COALESCE(col2, '')))
```

### Example — Business Key from ORDER_ID + PRODUCT_ID

```sql
SELECT
    ORDER_ID,
    PRODUCT_ID,
    MD5(
        CONCAT_WS(
            '|',
            COALESCE(ORDER_ID, ''),
            COALESCE(PRODUCT_ID, '')
        )
    ) AS BUSINESS_KEY
FROM ECOMDB.RAW.SUPERSTORE
WHERE row_id IN (99901, 99902, 99903);
```

### Key Points

- **`COALESCE(col, '')`** — Prevents NULL from corrupting the hash
- **`CONCAT_WS('|', ...)`** — Uses pipe as separator to avoid collisions (e.g., `AB|C` ≠ `A|BC`)
- **`MD5()`** — Returns a 32-character hex string; deterministic for same input

---

## Summary — Functions Used

| Function | Purpose | NULL Behavior |
|----------|---------|---------------|
| `CONCAT()` | Join strings | Returns NULL if any arg is NULL |
| `CONCAT_WS()` | Join with separator | Returns NULL if any arg is NULL |
| `IFF()` | Conditional expression | Programmer controls NULL handling |
| `COALESCE()` | First non-NULL value | Replaces NULL with fallback |
| `ARRAY_CONSTRUCT_COMPACT()` | Build array, skip NULLs | Excludes NULL elements |
| `ARRAY_TO_STRING()` | Array → delimited string | Skips NULL elements |
| `MD5()` | Hash function | Returns NULL if input is NULL |

---

## How This Maps to `stg_customer` Model

The `stg_customer.sql` dbt model applies these patterns:

```sql
-- Full address using ARRAY_CONSTRUCT_COMPACT
ARRAY_TO_STRING(
    ARRAY_CONSTRUCT_COMPACT(CITY, STATE, COUNTRY),
    ', '
) AS FULL_ADDRESS,

-- Business key using MD5
MD5(COALESCE(CUSTOMER_ID, '')) AS CUSTOMER_BK
```

Combined with `UPPER()`, `TRIM()`, `INITCAP()` for standardization and `ROW_NUMBER()` for deduplication.

---

## dbt Model: `stg_customer.sql` — Full Logic Breakdown

### Purpose

The `stg_customer` model is a **staging layer** model that:
- Standardizes raw customer data (case, whitespace)
- Removes duplicate customer records
- Creates a deterministic business key
- Generates a clean full address column

**Grain:** One row per unique customer.

---

### Architecture: 3 CTEs + Final SELECT

```
┌─────────────────────┐
│  customer_source    │  ← CTE 1: Standardize raw data
└─────────┬───────────┘
          │
┌─────────▼───────────┐
│ deduplicated_customers │  ← CTE 2: Remove duplicates via ROW_NUMBER()
└─────────┬───────────┘
          │
┌─────────▼───────────┐
│   Final SELECT      │  ← Add FULL_ADDRESS + CUSTOMER_BK
└─────────────────────┘
```

---

### CTE 1: `customer_source` — Data Standardization

```sql
WITH customer_source AS (
    SELECT
        CUSTOMER_ID,
        TRIM(INITCAP(CUSTOMER_NAME)) AS CUSTOMER_NAME,
        UPPER(TRIM(SEGMENT)) AS SEGMENT,
        INITCAP(TRIM(CITY)) AS CITY,
        INITCAP(TRIM(STATE)) AS STATE,
        UPPER(TRIM(COUNTRY)) AS COUNTRY,
        UPPER(TRIM(REGION)) AS REGION
    FROM {{ source('raw_src', 'superstore') }}
)
```

**Transformations applied:**

| Function | Purpose | Example |
|----------|---------|---------|
| `TRIM()` | Remove leading/trailing whitespace | `'  Henderson '` → `'Henderson'` |
| `INITCAP()` | Capitalize first letter of each word | `'los angeles'` → `'Los Angeles'` |
| `UPPER()` | Convert to uppercase | `'consumer'` → `'CONSUMER'` |

**Why standardize here?**
- Ensures consistent casing for downstream joins and aggregations
- Prevents duplicates caused by case differences (e.g., `'Consumer'` vs `'CONSUMER'`)
- Applied at the staging layer so all downstream models inherit clean data

---

### CTE 2: `deduplicated_customers` — Remove Duplicates

```sql
deduplicated_customers AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY CUSTOMER_ID
            ORDER BY CUSTOMER_NAME
        ) AS row_num
    FROM customer_source
)
```

**How it works:**

1. `PARTITION BY CUSTOMER_ID` — Groups all rows with the same customer ID
2. `ORDER BY CUSTOMER_NAME` — Deterministic tie-breaking within each group
3. `ROW_NUMBER()` — Assigns 1 to the first row in each partition
4. The final SELECT filters `WHERE row_num = 1` — keeping only one row per customer

**Why ROW_NUMBER() over DISTINCT?**
- `DISTINCT` doesn't let you control which row to keep
- `ROW_NUMBER()` gives deterministic deduplication with explicit ordering
- You can easily change the tie-breaking logic (e.g., most recent order date)

---

### Final SELECT — Derived Columns

```sql
SELECT
    CUSTOMER_ID,
    CUSTOMER_NAME,
    SEGMENT,
    CITY,
    STATE,
    COUNTRY,
    REGION,
    ARRAY_TO_STRING(
        ARRAY_CONSTRUCT_COMPACT(CITY, STATE, COUNTRY),
        ', '
    ) AS FULL_ADDRESS,
    MD5(COALESCE(CUSTOMER_ID, '')) AS CUSTOMER_BK
FROM deduplicated_customers
WHERE row_num = 1
```

#### `FULL_ADDRESS`

- Uses `ARRAY_CONSTRUCT_COMPACT` to skip NULL components
- Joins with `', '` separator via `ARRAY_TO_STRING`
- If STATE is NULL: output is `"Houston, United States"` (not `"Houston, , United States"`)

#### `CUSTOMER_BK` (Business Key)

- `COALESCE(CUSTOMER_ID, '')` — Prevents NULL input to MD5
- `MD5()` — Produces a 32-character deterministic hash
- Used for joining customer records across downstream models (fact tables, dimensions)

---

### Full Model Code

```sql
{{
    config(
        materialized='view'
    )
}}

WITH customer_source AS (
    SELECT
        CUSTOMER_ID,
        TRIM(INITCAP(CUSTOMER_NAME)) AS CUSTOMER_NAME,
        UPPER(TRIM(SEGMENT)) AS SEGMENT,
        INITCAP(TRIM(CITY)) AS CITY,
        INITCAP(TRIM(STATE)) AS STATE,
        UPPER(TRIM(COUNTRY)) AS COUNTRY,
        UPPER(TRIM(REGION)) AS REGION
    FROM {{ source('raw_src', 'superstore') }}
),

deduplicated_customers AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY CUSTOMER_ID
            ORDER BY CUSTOMER_NAME
        ) AS row_num
    FROM customer_source
)

SELECT
    CUSTOMER_ID,
    CUSTOMER_NAME,
    SEGMENT,
    CITY,
    STATE,
    COUNTRY,
    REGION,
    ARRAY_TO_STRING(
        ARRAY_CONSTRUCT_COMPACT(CITY, STATE, COUNTRY),
        ', '
    ) AS FULL_ADDRESS,
    MD5(COALESCE(CUSTOMER_ID, '')) AS CUSTOMER_BK
FROM deduplicated_customers
WHERE row_num = 1
```

---

### DAG (Dependency Graph)

```
ECOMDB.RAW.SUPERSTORE (source)
        │
        ▼
   stg_customer (staging model)
        │
        ▼
   [downstream models: dim_customer, fct_orders, etc.]
```

---

### Running the Model

```bash
# Build the model
dbt run --select stg_customer

# Run tests (not_null, unique, accepted_values)
dbt test --select stg_customer

# Build + test in one command
dbt build --select stg_customer
```

> **Important:** You must run `dbt run` before `dbt test`. Tests query the materialized table/view — if it doesn't exist yet, tests will error (not fail).

---

## YAML Schema: `stg_customer.yml` — Tests & Documentation

### Purpose

The YAML file defines:
- **Model-level documentation** — What the model does, its grain
- **Column-level documentation** — What each column means
- **Data tests** — Assertions that validate data quality after materialization

---

### Full YAML

```yaml
version: 2

models:
  - name: stg_customer
    description: >
      Customer staging model built from the Superstore source table.
      The model standardizes customer-related attributes, removes duplicate customer records,
      creates a customer business key, and generates a readable full address.
      The grain of this model is one row per customer.
    columns:
      - name: CUSTOMER_ID
        description: >
          Unique identifier for a customer. Used as the primary business identifier.
        tests:
          - not_null
          - unique

      - name: CUSTOMER_NAME
        description: >
          Standardized customer name associated with the customer identifier.
        tests:
          - not_null

      - name: SEGMENT
        description: >
          Customer segment classification such as Consumer, Corporate, or Home Office.
        tests:
          - not_null

      - name: CITY
        description: >
          Customer city location.
        tests:
          - not_null

      - name: STATE
        description: >
          Customer state or province.
        tests:
          - not_null

      - name: COUNTRY
        description: >
          Customer country.
        tests:
          - not_null

      - name: REGION
        description: >
          Geographic sales region associated with the customer.
        tests:
          - not_null

      - name: FULL_ADDRESS
        description: >
          Concatenated address string generated from CITY, STATE, and COUNTRY
          using ARRAY_CONSTRUCT_COMPACT and ARRAY_TO_STRING.
          Null address components are automatically excluded.
        tests:
          - not_null

      - name: CUSTOMER_BK
        description: >
          Deterministic MD5 business key generated from CUSTOMER_ID.
          Used for joining customer records across downstream models.
        tests:
          - not_null
          - unique
```

---

### Tests Summary

| Column | not_null | unique |
|--------|:---:|:---:|
| CUSTOMER_ID | Yes | Yes |
| CUSTOMER_NAME | Yes | — |
| SEGMENT | Yes | — |
| CITY | Yes | — |
| STATE | Yes | — |
| COUNTRY | Yes | — |
| REGION | Yes | — |
| FULL_ADDRESS | Yes | — |
| CUSTOMER_BK | Yes | Yes |

**Total: 11 tests** (9 `not_null` + 2 `unique`)

---

### Test Types Explained

| Test | What It Checks | Fails When |
|------|----------------|------------|
| `not_null` | Column has no NULL values | Any row has NULL in that column |
| `unique` | Column has no duplicate values | Two or more rows share the same value |

---

### Running Tests

```bash
# Run all tests for stg_customer
dbt test --select stg_customer

# Run only not_null tests
dbt test --select stg_customer --exclude "tag:unique"

# Build + test in one step
dbt build --select stg_customer
```

---

### Error vs Fail

| Result | Meaning | Common Cause |
|--------|---------|--------------|
| **Pass** | Test assertion holds — no violations found | Data is clean |
| **Fail** | Test ran but found violations (e.g., NULLs exist) | Data quality issue |
| **Error** | Test could not execute at all | Model not built yet, SQL syntax error, permission issue |

> If you see "error" on all tests, run `dbt run --select stg_customer` first to materialize the model.

---

### Lessons Learned: `accepted_values` in dbt-fusion 2.0

In dbt-fusion 2.0, the `accepted_values` test syntax changed. The old format:

```yaml
# OLD FORMAT (deprecated — causes DbtYamlValidationError dbt1159)
tests:
  - accepted_values:
      values: ['Consumer', 'Corporate', 'Home Office']
```

Must be migrated to:

```yaml
# NEW FORMAT (dbt-fusion 2.0 compatible)
tests:
  - accepted_values:
      arguments:
        values: ['Consumer', 'Corporate', 'Home Office']
```

The `values` list moves under an `arguments` field. Without this, parsing fails with:

```
Error [DbtYamlValidationError (dbt1159)]: Deprecated test arguments: ["values"]
at top-level detected. Please migrate to the new format under the 'arguments' field.
```
