
WITH customer_source AS (

    SELECT

        UPPER(TRIM(CUSTOMER_ID)) AS CUSTOMER_ID,

        INITCAP(TRIM(CUSTOMER_NAME)) AS CUSTOMER_NAME,

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
            ORDER BY CUSTOMER_ID
        ) AS RN

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
        ARRAY_CONSTRUCT_COMPACT(
            CITY,
            STATE,
            COUNTRY
        ),
        ', '
    ) AS FULL_ADDRESS,

    MD5(
        ARRAY_TO_STRING(
            ARRAY_CONSTRUCT_COMPACT(
                CUSTOMER_ID
            ),
            '|'
        )
    ) AS CUSTOMER_BK


FROM deduplicated_customers

WHERE RN = 1