# Docker - Setup - PostgreSQL

Install and set up PostgreSQL on Docker.

## Database

The Northwind database used in this process originally came from: https://github.com/microsoft/sql-server-samples/tree/master/samples/databases/northwind-pubs

The Downloaded Northwind database SQL has been altered to use PostgreSQL commands and make the data loading INSERT statements friendlier.

## Processing Steps

1. Setup:
  Docker documentation:
  - [Download and Install](https://www.docker.com/blog/how-to-use-the-postgres-docker-official-image/)
  - [Get Started](https://docs.docker.com/guides/postgresql/)

  - Substitutions: in order for this following steps to work the following placeholders will need correct values substituted:
    - <dev-user-password>

  - Change to the working directory:
    ```
    cd C:\Working\Storage\Dev\GitHub\Working
    ```

2. Clean up prior working files:

  ```
  erase /S /Q .\*
  ```

3. Remove a previously existing partition), if any is present:

  ```
  docker rm -f local_postgres
  ```

4. Get the latest image:

  ```
  docker pull postgres
  ```

5. Create and start an instance:

  ```
  docker run --name local_postgres \
  -p 5432:5432 \
  --network pilot-net \
  -m 512m \
  -e POSTGRES_USER=DevUser \
  -e POSTGRES_PASSWORD=<dev-user-password> \
  -e POSTGRES_DB=devDb \
  -v "postgres_data:/var/lib/postgresql" \
  -v ".:/local_working" \
  -d postgres
  ```

6. Create the northwind database:

  ```
  docker exec local_postgres psql -U DevUser -d devDb \
  -c "CREATE DATABASE northwind;"
  ```

  Validate database was created (should not get an error):

  ```
  docker exec local_postgres psql -U DevUser -d northwind
  ```

7. Copy database script:

  ```
  copy "..\PilotApiDotNet\docker\PostgreSQL\northwind.sql" "."
  ```

8. Load data into the database:

  ```
  docker exec -i local_postgres psql -U DevUser -d northwind \
  < ..\PilotApiDotNet\docker\PostgreSQL\northwind.sql
  ```

  Validate (should show a list of tables):

  ```
  docker exec local_postgres psql -U DevUser -d northwind \
  -c "SELECT table_name FROM information_schema.tables WHERE table_schema = 'pilot' AND table_type = 'BASE TABLE';"
  ```

9. Clean up prior working files:

  ```
  erase /S /Q .\*
  ```

10. Copy custom script:

  ```
  copy "..\PilotApiDotNet\docker\PostgreSQL\customobjects.sql" "."
  ```

11. Load data into the database:

  ```
  docker exec -i local_postgres psql -U DevUser -d northwind \
  < ..\PilotApiDotNet\docker\PostgreSQL\customobjects.sql
  ```

12. Clean up prior working files:

  ```
  erase .\* /S /Q
  ```

## Additional CLI commands

1. start container

  ```
  docker start local_postgres
  ```

2. Stop and remove container:

  ```
  docker rm -f local_postgres
  ```

3. Remove a database:

  ```
  docker exec local_postgres psql -U DevUser -d devDb -c "DROP DATABASE northwind WITH (FORCE);"
  ```

4. List all databases:

  ```
  docker exec local_postgres psql -U DevUser -d devDb -l
  ```

## Interacting with a Docker database

How can we interact with a database installed on a Docker container?

1. Via Command Line (psql)

  ```
  docker exec -it postgres_db psql -U myuser -d mydatabase
  ```

2. Via GUI Desktop Tools:
- Open tools like:
	- DBeaver, 
	- DataGrip, or 
	- pgAdmin
- Connect using:
	- Host: localhost
	- Port: 5432
	- User/Password: As defined in your environment variables.

## Troubleshooting

If an error similar to 'ERROR: duplicate key value violates unique constraint "suppliers_pkey"' occurs, it may be necessary to reset the primary key sequences.
This reset can be accomplished via the following script:

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
