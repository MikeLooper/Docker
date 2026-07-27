
CREATE OR ALTER PROCEDURE dbo.GenerateUniqueKeyDynamic
    @SchemaName NVARCHAR(128),
    @TableName NVARCHAR(128),
    @ColumnName NVARCHAR(128),
    @GeneratedKey NVARCHAR(MAX) OUTPUT -- Returns the key via an output parameter
AS
BEGIN
	-- This stored procedure (SP) will do the following:
	--    1. Read the length of the supplied column in the supplied table.
	--    2. Create a random string of length that matches the supplied column length.
	--    3. Validate that the created string is not already in the supplied column.
	--    4. If the generated string is found in the supplied column, go back to step #2 and try again.
	-- ----------------------------
	-- Example call of this SP:
	-- -- Declare a variable to catch the returned key
	-- DECLARE @ResultKey NVARCHAR(MAX);
	-- 
	-- -- Call the procedure with your target table and column names
	-- EXEC dbo.GenerateUniqueKeyDynamic 
	--     @SchemaName = N'myschema', 
	--     @TableName = N'mytable', 
	--     @ColumnName = N'mykey', 
	--     @GeneratedKey = @ResultKey OUTPUT;
	-- 
	-- -- See the generated key
	-- SELECT @ResultKey AS GeneratedKey;

	SET NOCOUNT ON;

    DECLARE @TargetLength INT;
    DECLARE @KeyExists INT = 1;
    DECLARE @AllowedChars NVARCHAR(62) = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    DECLARE @SqlDynamic NVARCHAR(MAX);
    DECLARE @ParamDefinition NVARCHAR(500);

    -- 1. Read the length of the column dynamically from the first available row
    -- QUOTENAME() safely wraps identifiers in [brackets] to prevent SQL injection
    SET @SqlDynamic = N'SELECT TOP 1 @LengthOut = LEN(' + QUOTENAME(@ColumnName) + N') ' +
                      N'FROM ' + QUOTENAME(@SchemaName) + N'.' + QUOTENAME(@TableName) + N' ' +
                      N'WHERE ' + QUOTENAME(@ColumnName) + N' IS NOT NULL;';
    
    SET @ParamDefinition = N'@LengthOut INT OUTPUT';
    
    EXEC sp_executesql @SqlDynamic, @ParamDefinition, @LengthOut = @TargetLength OUTPUT;

    -- Handle case where the table is empty or column has only NULL values
    IF @TargetLength IS NULL OR @TargetLength = 0
    BEGIN
        RAISERROR('Target table or column is empty or contains only NULLs.', 16, 1);
        RETURN;
    END

    -- Loop construct for steps 2, 3, and 4
    WHILE @KeyExists = 1
    BEGIN
        -- 2. Create a random string of the matching length
        SET @GeneratedKey = '';
        DECLARE @Counter INT = 1;
        
        WHILE @Counter <= @TargetLength
        BEGIN
            -- NEWID() + CHECKSUM creates a unique random index for every single character loop
            DECLARE @RandomIndex INT;
            SET @RandomIndex = ABS(CHECKSUM(NEWID())) % LEN(@AllowedChars) + 1;
            
            SET @GeneratedKey = @GeneratedKey + SUBSTRING(@AllowedChars, @RandomIndex, 1);
            SET @Counter = @Counter + 1;
        END

        -- 3. Validate that the created string is not already in the specific column
        SET @SqlDynamic = N'IF EXISTS (SELECT 1 FROM ' + QUOTENAME(@TableName) + N' ' +
                          N'WHERE ' + QUOTENAME(@ColumnName) + N' = @KeyToCheck) ' +
                          N'SET @ExistsOut = 1 ELSE SET @ExistsOut = 0;';
        
        SET @ParamDefinition = N'@KeyToCheck NVARCHAR(MAX), @ExistsOut INT OUTPUT';
        
        EXEC sp_executesql @SqlDynamic, @ParamDefinition, 
                           @KeyToCheck = @GeneratedKey, 
                           @ExistsOut = @KeyExists OUTPUT;
        
        -- 4. If @KeyExists comes back as 0, the WHILE loop exits automatically.
    END
END;
