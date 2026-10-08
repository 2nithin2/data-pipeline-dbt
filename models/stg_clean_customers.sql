--stg_clean_customers.sql

WITH source AS (
    SELECT * FROM {{ source('raw_src', 'SUPERSTORE') }}
),

cleaned AS (
    SELECT DISTINCT
        CUSTOMER_ID,
        CUSTOMER_NAME,
        CITY,
        COALESCE(STATE, 'Unknown') AS STATE,
        COALESCE(COUNTRY, 'United States') AS COUNTRY,
        COALESCE(REGION, 'Unassigned') AS REGION
    FROM source
    WHERE CUSTOMER_ID IS NOT NULL
)

SELECT * FROM cleaned