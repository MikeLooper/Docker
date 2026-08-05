# Docker - Setup - PostgreSQL

Install and set up PostgreSQL on Docker using Docker Compose.

## Preparation

Previous setup noted in the [Main README](.\README.md) should have already been accomplished.

Change to the current directory.
  
```
cd PostgreSQL
```

When this process is complete, change the directory back to the main directory.
  
```
cd ..
```

## Database

The Northwind database used in this process originally came from:
https://github.com/microsoft/sql-server-samples/tree/master/samples/databases/northwind-pubs

The downloaded SQL in this repository has been adjusted for PostgreSQL.

## Primary Script

Use:

```
Docker-PostgreSQL-builder.bat
```

This script uses:

- `docker-compose.postgresql.yml` for container lifecycle
- Docker CLI only where needed (`docker exec` for SQL execution)

## Required Secrets File

Create a local secrets file:

```
copy ..\secrets\postgresql.env.example secrets\postgresql.env
```

Then replace values in `..\secrets\postgresql.env`:

- `DEV_USER_PASSWORD=<dev-user-password>`

## Processing Steps (Compose-first)

1. Pull the current image: `docker pull postgres:latest`.
2. Stop prior stack: `docker compose -f docker-compose.postgresql.yml down --remove-orphans`.
3. Start container: `docker compose -f docker-compose.postgresql.yml up -d --force-recreate`.
4. Recreate database `northwind` (drop/create).
5. Load [northwind.sql](northwind.sql).
6. Validate pilot tables were loaded.
7. Load [customobjects.sql](customobjects.sql).

## Manual Commands (Equivalent)

```bat
set "IMAGE_FILE=postgres:latest"
set "WORKING_DIR=C:/Working/Storage/Dev/GitHub/Working"
set "DEV_USER_PASSWORD=replace-me"
docker pull "%IMAGE_FILE%"
docker compose -f docker-compose.postgresql.yml -p local_postgres up -d --force-recreate
docker exec local_postgres psql -U DevUser -d postgres -c "DROP DATABASE IF EXISTS northwind;"
docker exec local_postgres psql -U DevUser -d postgres -c "CREATE DATABASE northwind;"
docker exec -i local_postgres psql -U DevUser -d northwind < northwind.sql
docker exec -i local_postgres psql -U DevUser -d northwind < customobjects.sql
```

## Connection Info

- Host: `localhost`
- Port: `5432`
- Username: `DevUser`
- Password: value of `DEV_USER_PASSWORD`
- Database: `northwind`

## Additional Notes

- The compose service is named `local_postgres` to preserve existing references from API configs.
- Data is persisted in named volume `postgres_data`.
- Re-running the script intentionally reloads database objects for a deterministic local state.
- Script loads secrets from `..\secrets\postgresql.env` and stops with a clear error when the file is missing or placeholders are unchanged.

## Additional CLI Commands

1. Restart this stack:

```
docker compose -f docker-compose.postgresql.yml restart
```

2. Stop and remove this stack:

```
docker compose -f docker-compose.postgresql.yml down
```

3. List databases:

```
docker exec local_postgres psql -U DevUser -d devDb -l
```

## Troubleshooting

If an error similar to `ERROR: duplicate key value violates unique constraint "suppliers_pkey"` occurs, it may be necessary to reset primary key sequences.
Run the following SQL:

```
SET search_path TO pilot;

DO $$
DECLARE
    max_id int;
	seq_name text;
    set_val int;
BEGIN
	-- Categories
    select coalesce(max(CategoryID), 0) into max_id from Categories;
	select pg_get_serial_sequence('Categories', 'categoryid') into seq_name;
	select setval(seq_name, max_id + 1, false) INTO set_val;
    RAISE NOTICE 'Categories Set Val is: %', set_val;
	
	-- Employees
    select coalesce(max(EmployeeID), 0) into max_id from Employees;
	select pg_get_serial_sequence('Employees', 'employeeid') into seq_name;
	select setval(seq_name, max_id + 1, false) INTO set_val;
    RAISE NOTICE 'Employees Set Val is: %', set_val;	
	
	-- Orders
    select coalesce(max(OrderID), 0) into max_id from Orders;
	select pg_get_serial_sequence('Orders', 'orderid') into seq_name;
	select setval(seq_name, max_id + 1, false) INTO set_val;
    RAISE NOTICE 'Orders Set Val is: %', set_val;
	
	-- Products
    select coalesce(max(ProductID), 0) into max_id from Products;
	select pg_get_serial_sequence('Products', 'productid') into seq_name;
	select setval(seq_name, max_id + 1, false) INTO set_val;
    RAISE NOTICE 'Products Set Val is: %', set_val;
	
	-- Shippers
    select coalesce(max(ShipperID), 0) into max_id from Shippers;
	select pg_get_serial_sequence('Shippers', 'shipperid') into seq_name;
	select setval(seq_name, max_id + 1, false) INTO set_val;
    RAISE NOTICE 'Shippers Set Val is: %', set_val;
	
	-- Suppliers
    select coalesce(max(SupplierID), 0) into max_id from Suppliers;
	select pg_get_serial_sequence('Suppliers', 'supplierid') into seq_name;
	select setval(seq_name, max_id + 1, false) INTO set_val;
    RAISE NOTICE 'Suppliers Set Val is: %', set_val;
END $$;
```
