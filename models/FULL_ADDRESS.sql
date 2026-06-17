SELECT
    ARRAY_TO_STRING(
        ARRAY_CONSTRUCT_COMPACT(
            UPPER(TRIM(CUSTOMER_ID)),
            INITCAP(TRIM(CUSTOMER_NAME)),
            UPPER(TRIM(SEGMENT)),
            INITCAP(TRIM(CITY)),
            INITCAP(TRIM(STATE)),
            UPPER(TRIM(COUNTRY)),
            UPPER(TRIM(REGION))
        ),
        ', '
    ) AS FULL_ADDRESS
FROM {{ source('raw_src', 'superstore') }}

	--COUNTRY VARCHAR(16777216),
-- 	CITY VARCHAR(16777216),
-- 	STATE VARCHAR(16777216),
-- 	POSTAL_CODE NUMBER(38,0),
-- 	REGION VARCHAR(16777216),

    -- UPPER(TRIM(CUSTOMER_ID))
    --     AS CUSTOMER_ID,

    -- INITCAP(TRIM(CUSTOMER_NAME))
    --     AS CUSTOMER_NAME,

    -- UPPER(TRIM(SEGMENT))
    --     AS SEGMENT,

    -- INITCAP(TRIM(CITY))
    --     AS CITY,

    -- INITCAP(TRIM(STATE))
    --     AS STATE,

    -- UPPER(TRIM(COUNTRY))
    --     AS COUNTRY,

    -- UPPER(TRIM(REGION))
    --     AS REGION,