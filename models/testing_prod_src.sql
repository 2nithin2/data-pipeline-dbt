
SELECT * FROM {{source('prod_src_raw','SUPERSTORE')}} 
WHERE row_id IN (99901, 99902, 99903)
----**** DBT IS CASE SENSITIVE