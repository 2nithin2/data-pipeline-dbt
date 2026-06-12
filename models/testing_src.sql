-- testing src is working or not
SELECT * FROM {{source('raw_src','superstore')}} 
WHERE row_id IN (99901, 99902, 99903)
