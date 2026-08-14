SET search_path TO pilot;

DO $$
DECLARE
    max_id int;
	seq_name text;
    set_val int;
BEGIN
	-- categories
    select coalesce(max(categoryid), 0) into max_id from categories;
	select pg_get_serial_sequence('categories', 'categoryid') into seq_name;
	select setval(seq_name, max_id + 1, false) INTO set_val;
    RAISE NOTICE 'categories Set Val is: %', set_val;
	
	-- employees
    select coalesce(max(employeeid), 0) into max_id from employees;
	select pg_get_serial_sequence('employees', 'employeeid') into seq_name;
	select setval(seq_name, max_id + 1, false) INTO set_val;
    RAISE NOTICE 'employees Set Val is: %', set_val;	
	
	-- orders
    select coalesce(max(orderid), 0) into max_id from orders;
	select pg_get_serial_sequence('orders', 'orderid') into seq_name;
	select setval(seq_name, max_id + 1, false) INTO set_val;
    RAISE NOTICE 'orders Set Val is: %', set_val;
	
	-- products
    select coalesce(max(productid), 0) into max_id from products;
	select pg_get_serial_sequence('products', 'productid') into seq_name;
	select setval(seq_name, max_id + 1, false) INTO set_val;
    RAISE NOTICE 'products Set Val is: %', set_val;
	
	-- shippers
    select coalesce(max(shipperid), 0) into max_id from shippers;
	select pg_get_serial_sequence('shippers', 'shipperid') into seq_name;
	select setval(seq_name, max_id + 1, false) INTO set_val;
    RAISE NOTICE 'shippers Set Val is: %', set_val;
	
	-- suppliers
    select coalesce(max(supplierid), 0) into max_id from suppliers;
	select pg_get_serial_sequence('suppliers', 'supplierid') into seq_name;
	select setval(seq_name, max_id + 1, false) INTO set_val;
    RAISE NOTICE 'suppliers Set Val is: %', set_val;
END $$;
