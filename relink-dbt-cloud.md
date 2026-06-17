# Relink dbt Cloud to a New Snowflake Account (After Trial Expiry)

## Step 1: Set up the new Snowflake account

Run these SQL commands in your new Snowflake account:

```sql
-- Create your database (or upload/load your dataset first)
CREATE DATABASE IF NOT EXISTS ECOMDB;

-- Create the dbt role
CREATE ROLE IF NOT EXISTS PC_DBT_ROLE;

-- Grant warehouse access
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE PC_DBT_ROLE;

-- Grant database access
GRANT USAGE ON DATABASE ECOMDB TO ROLE PC_DBT_ROLE;

-- Grant schema access
GRANT USAGE ON ALL SCHEMAS IN DATABASE ECOMDB TO ROLE PC_DBT_ROLE;

-- Grant read access on all existing tables
GRANT SELECT ON ALL TABLES IN DATABASE ECOMDB TO ROLE PC_DBT_ROLE;

-- Grant dbt ability to create models (tables and views)
GRANT CREATE TABLE ON ALL SCHEMAS IN DATABASE ECOMDB TO ROLE PC_DBT_ROLE;
GRANT CREATE VIEW ON ALL SCHEMAS IN DATABASE ECOMDB TO ROLE PC_DBT_ROLE;

-- Assign role to your user
GRANT ROLE PC_DBT_ROLE TO USER VVNITHIN;

-- Create the dbt dev schema
CREATE SCHEMA IF NOT EXISTS ECOMDB.dbt_nit;
GRANT ALL ON SCHEMA ECOMDB.dbt_nit TO ROLE PC_DBT_ROLE;
