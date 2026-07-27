
CREATE OR REPLACE FUNCTION generate_unique_key_dynamic(
    schema_name TEXT,
    table_name TEXT,
    column_name TEXT
)
RETURNS TEXT AS $$
DECLARE
    target_length INT;
    generated_key TEXT;
    set_result BOOLEAN;
    key_exists BOOLEAN;
    allowed_chars TEXT := 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
BEGIN
	-- This function will do the following:
	--    1. Read the length of the supplied column in the supplied table.
	--    2. Create a random string of length that matches the supplied column length.
	--    3. Validate that the created string is not already in the supplied column.
	--    4. If the generated string is found in the supplied column, go back to step #2 and try again.
	-- ----------------------------
	-- Example call of this function:
	-- SELECT generate_unique_key_dynamic('myschema', 'mytable', 'mykey');

	-- set the schema
	EXECUTE format('SET search_path TO %I, public', schema_name);

    -- 1. Read the length of the column dynamically
    -- %I safely escapes table and column names to prevent SQL injection
    EXECUTE format('SELECT LENGTH(%I) FROM %I WHERE %I IS NOT NULL LIMIT 1', 
                   column_name, table_name, column_name)
    INTO target_length;

    -- Handle case where the table is empty or column has only NULL values
    IF target_length IS NULL THEN
        RAISE EXCEPTION 'Target table % or column % is empty or contains only NULLs.', table_name, column_name;
    END IF;

    -- Loop construct for unique key generation
    LOOP
        -- 2. Create a random string of the matching length
        SELECT array_to_string(array(
            SELECT substr(allowed_chars, floor(random() * length(allowed_chars) + 1)::int, 1)
            FROM generate_series(1, target_length)
        ), '') INTO generated_key;

        -- 3. Validate that the created string is not already in the specific column
        EXECUTE format('SELECT EXISTS(SELECT 1 FROM %I WHERE %I = %L)', 
                       table_name, column_name, generated_key)
        INTO key_exists;

        -- 4. If not found, exit loop.
        IF NOT key_exists THEN
            EXIT;
        END IF;
    END LOOP;

    -- Return the generated string directly
    RETURN generated_key;
END;
$$ LANGUAGE plpgsql;
