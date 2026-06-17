select 
     ORDER_ID,
    PRODUCT_ID,

    MD5(
        CONCAT_WS(
            '|',
            COALESCE(ORDER_ID,''),
            COALESCE(PRODUCT_ID,'')
        )
    ) AS BUSINESS_KEY

FROM {{source('raw_src','superstore')}}

-- ===========================================================
-- -- WE USING COLEASE TO AVOID NULL BEFORE GETTING HASHED 
-- CREATING A BUSINESS WITH COMBINATION OF ORDERID AND SOLACEID
--Returns a 32-character hex-encoded string containing the 128-bit MD5 message digest.
--MD5(<msg>)
