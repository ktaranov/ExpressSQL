USE [master];
GO

/* Cleanup existing versions */
IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[sp_sizeoptimiser]'))
	BEGIN
		DROP PROCEDURE [dbo].[sp_sizeoptimiser];
	END

IF  EXISTS (SELECT * FROM sys.types st JOIN sys.schemas ss ON st.schema_id = ss.schema_id WHERE st.name = N'SizeOptimiserTableType' AND ss.name = N'dbo')
	BEGIN
		DROP TYPE [dbo].[SizeOptimiserTableType]
	END
GO

/**************************************************************/
/* Create user defined table type for database list parameter */
/**************************************************************/
IF NOT EXISTS (SELECT * FROM sys.types st JOIN sys.schemas ss ON st.schema_id = ss.schema_id WHERE st.name = N'SizeOptimiserTableType' AND ss.name = N'dbo')
	CREATE TYPE [dbo].[SizeOptimiserTableType] AS TABLE(
		[database_name] [sysname] NOT NULL,
		PRIMARY KEY CLUSTERED ([database_name] ASC)WITH (IGNORE_DUP_KEY = OFF))
GO

/***************************/
/* Create stored procedure */
/***************************/
IF NOT EXISTS(SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[sp_sizeoptimiser]'))
	BEGIN
		EXEC dbo.sp_executesql @statement = N'CREATE PROCEDURE [dbo].[sp_sizeoptimiser] AS';
	END;
GO

ALTER PROCEDURE [dbo].[sp_sizeoptimiser] 
				@IndexNumThreshold TINYINT = 7,
				@Databases [dbo].[SizeOptimiserTableType] READONLY,
				@isExpress BIT = NULL

WITH RECOMPILE
AS
	SET NOCOUNT ON;
	BEGIN TRY

		DECLARE @hasSparse BIT = 0;
		DECLARE @debug BIT = 0;
		DECLARE @hasTempStat BIT = 0;
		DECLARE @fullVersion TINYINT;
		DECLARE @minorVersion INT;
		DECLARE @lastUpdated NVARCHAR(20) = '2018-07-10';
		DECLARE @version NVARCHAR(50) = CAST(SERVERPROPERTY('PRODUCTVERSION') AS NVARCHAR)
		DECLARE @checkSQL NVARCHAR(MAX) = N'';
		DECLARE @msg NVARCHAR(MAX) = N'';

		/* Validate database list */
		CREATE TABLE #Databases (
			[database_name] SYSNAME NOT NULL);

		IF 0 = (SELECT COUNT(*) FROM @Databases)
			BEGIN
				INSERT INTO #Databases
				SELECT [d].[name]
				FROM [sys].[databases] AS [d]
				WHERE [d].[database_id] > 4;
			END
		ELSE
			BEGIN
				INSERT INTO #Databases
				SELECT [database_name]
				FROM @Databases AS [d]
					INNER JOIN [sys].[databases] AS [sd] ON [sd].[name] = REPLACE(REPLACE([d].[database_name], '[', ''), ']', '')

				IF (SELECT COUNT(*) FROM @Databases) > (SELECT COUNT(*) FROM #Databases)
					BEGIN
						DECLARE @errorDatabase NVARCHAR(MAX);

						WITH NonExistantDatabase AS(
							SELECT [database_name]
							FROM @Databases
							EXCEPT
							SELECT [database_name]
							FROM #Databases)

						SELECT @errorDatabase = ISNULL(@errorDatabase + N', ' + [database_name], [database_name])
						FROM NonExistantDatabase;

						SET @msg = 'Supplied databases do not exist: ' + @errorDatabase + '.';
						RAISERROR(@msg, 16, 1);
					END
			END

		
		
		/* Find edition */
		IF(@IsExpress IS NULL AND CAST(SERVERPROPERTY('Edition') AS VARCHAR(50)) LIKE '%express%')
			 SET @isExpress = 1;
		
		/* Find Version */
		DECLARE @tempVersion NVARCHAR(100);
		
		SET @fullVersion = (SELECT CAST(LEFT(@version, CHARINDEX('.', @version, 0)-1) AS INT));
		SET @tempVersion = (SELECT RIGHT(@version, LEN(@version) - CHARINDEX('.', @version, 0)));
		SET @tempVersion = (SELECT RIGHT(@tempVersion, LEN(@tempVersion) - CHARINDEX('.', @tempVersion, 0)));
		SET @minorVersion = (SELECT LEFT(@tempVersion,CHARINDEX('.', @tempVersion, 0) -1));

		/* Check for Sparse Columns feature */
		IF 1 = (SELECT COUNT(*) FROM sys.all_columns AS ac WHERE ac.name = 'is_sparse' AND OBJECT_NAME(ac.object_id) = 'all_columns')
			 BEGIN
				 SET @hasSparse = 1;
			 END;

		/*Check for is_temp value on statistics*/
		IF 1 = (SELECT COUNT(*) FROM sys.all_columns AS ac WHERE ac.name = 'is_temporary' AND OBJECT_NAME(ac.object_id) = 'all_columns')
			 BEGIN
				 SET @hasTempStat = 1;
			 END;
		
		/* Print info */
		SET @msg = 'sp_OptiMiser';
		RAISERROR(@msg, 10, 1) WITH NOWAIT;
		SET @msg = '------------';
		RAISERROR(@msg, 10, 1) WITH NOWAIT;
		SET @msg = '';
		RAISERROR(@msg, 10, 1) WITH NOWAIT;
		SET @msg = 'Time:				' + CAST(GETDATE() AS NVARCHAR(50))
		RAISERROR(@msg, 10, 1) WITH NOWAIT;
		SET @msg = 'Express Edition:	' + CAST(@isExpress AS CHAR(1))
		RAISERROR(@msg, 10, 1) WITH NOWAIT;
		SET @msg = 'SQL Major Version:	' + CAST(@fullVersion AS VARCHAR(5));
		RAISERROR(@msg, 10, 1) WITH NOWAIT;
		SET @msg = 'SQL Minor Version:	' + CAST(@minorVersion AS VARCHAR(20));
		RAISERROR(@msg, 10, 1) WITH NOWAIT;
		SET @msg = 'Sparse Columns:		' + CAST(@hasSparse AS CHAR(1));
		RAISERROR(@msg, 10, 1) WITH NOWAIT;
		SET @msg = '';
		RAISERROR(@msg, 10, 1) WITH NOWAIT;
		SET @msg = 'Building results table...';
		RAISERROR(@msg, 10, 1) WITH NOWAIT;

		/*Build results table */
		IF OBJECT_ID(N'tempdb..#results') IS NOT NULL
			BEGIN
				DROP TABLE #results;
			END;

		CREATE TABLE #results
				([ID]			INT IDENTITY(1, 1) NOT NULL PRIMARY KEY,
				[check_num]		INT NOT NULL,
				[check_type]	NVARCHAR(50) NOT NULL,
				[db_name]		SYSNAME NOT NULL,
				[obj_type]		SYSNAME NOT NULL,
				[obj_name]		SYSNAME NOT NULL,
				[col_name]		SYSNAME NULL,
				[message]		NVARCHAR(500) NULL,
				[ref_link]		NVARCHAR(500) NULL);

		/* Header row */
		INSERT INTO #results ([check_num], [check_type], [obj_type], [db_name], [obj_name], [col_name], [message], [ref_link])
		SELECT	0,
				N'Let''s do this',
				N'Vroom, vroom',
				N'beep boop',
				N'Off to the races!',
				N'Ready, set, go!',
				N'Last Updated '+ @lastUpdated,
				N'http://expressdb.io';

		RAISERROR('Running size checks...', 10, 1) WITH NOWAIT;
		RAISERROR('', 10, 1) WITH NOWAIT;

		/* Check 1: Did you mean to use a time based format? */
		RAISERROR('Check 1 - Time based formats', 10, 1) WITH NOWAIT;
		BEGIN
			SET @checkSQL = N'';
			SELECT @checkSQL = @checkSQL + N'USE ' + [database_name] + N'; 
								INSERT INTO #results ([check_num], [check_type], [obj_type], [db_name], [obj_name], [col_name], [message], [ref_link])
								SELECT 1, 
								N''Data Formats'', 
								N''USER_TABLE'', 
								QUOTENAME(DB_NAME()),
								QUOTENAME(SCHEMA_NAME(t.schema_id)) + ''.'' + QUOTENAME(t.name), 
								QUOTENAME(c.name), 
								N''Columns storing date or time should use a temporal specific data type, but this column is using '' + ty.name + ''.'', 
								N''https://github.com/LowlyDBA/ExpressSQL/tree/master#time-based-formats''
								FROM sys.columns as c
									inner join sys.tables as t on t.object_id = c.object_id
									inner join sys.types as ty on ty.user_type_id = c.user_type_id
								WHERE c.is_identity = 0 --exclude identity cols
									AND t.is_ms_shipped = 0 --exclude sys table
									AND (c.name LIKE ''%date%'' OR c.name LIKE ''%time%'') 
									AND [c].[name] NOT LIKE ''%days%''
									AND ty.name NOT IN (''datetime'', ''datetime2'', ''datetimeoffset'', ''date'', ''smalldatetime'', ''time'');'
			FROM #Databases;
			EXEC sp_executesql @checkSQL;
		 END; --Check 1

		/* Check 2: Old School Variable Lengths (255/256) */
		RAISERROR('Check 2 - Archaic varchar Lengths', 10, 1) WITH NOWAIT;
			BEGIN
				SET @checkSQL = N'';
				SELECT @checkSQL = @checkSQL + N'USE ' + [database_name]  + N'; WITH archaic AS (
									SELECT	QUOTENAME(SCHEMA_NAME(t.schema_id)) + ''.'' + QUOTENAME(t.name) AS [obj_name],
											QUOTENAME(c.name) AS [col_name],
											N''Possible arbitrary variable length column in use. Is the '' + ty.name + N'' length of '' + CAST (c.max_length / 2 AS varchar(MAX)) + N'' based on requirements'' AS [message],
											N''https://goo.gl/uiltVb'' AS [ref_link]
									FROM sys.columns c
										inner join sys.tables as t on t.object_id = c.object_id
										inner join sys.types as ty on ty.user_type_id = c.user_type_id
									WHERE c.is_identity = 0 --exclude identity cols
										AND t.is_ms_shipped = 0 --exclude sys table
										AND ty.name = ''NVARCHAR''
										AND c.max_length IN (510, 512)
									UNION
									SELECT	QUOTENAME(SCHEMA_NAME(t.schema_id)) + ''.'' + QUOTENAME(t.name), 
											QUOTENAME(c.name), 
											N''Possible arbitrary variable length column in use. Is the '' + ty.name + N'' length of '' + CAST (c.max_length AS varchar(MAX)) + N'' based on requirements'', 
											N''https://goo.gl/uiltVb''
									FROM sys.columns as c
										inner join sys.tables as t on t.object_id = c.object_id
										inner join sys.types as ty on ty.user_type_id = c.user_type_id
									WHERE c.is_identity = 0 --exclude identity cols
										AND t.is_ms_shipped = 0 --exclude sys table
										AND ty.name = ''VARCHAR''
										AND c.max_length IN (255, 256))

								INSERT INTO #results ([check_num], [check_type], [obj_type], [db_name], [obj_name], [col_name], [message], [ref_link])
								SELECT	2, 
										N''Data Formats'',
										N''USER_TABLE'',
										QUOTENAME(DB_NAME()),
										[obj_name],
										[col_name],
										[message],
										[ref_link]
								FROM [archaic];'
				FROM #Databases;
				EXEC sp_executesql @checkSQL;
			END; --Check 2
			
			RAISERROR('Check 3 - Unspecified VARCHAR Length', 10, 1) WITH NOWAIT;
			BEGIN
				SET @checkSQL = N'';
				SELECT @checkSQL = @checkSQL + 'USE ' + [database_name] + ';
									WITH UnspecifiedVarChar AS (
										SELECT	QUOTENAME(SCHEMA_NAME(t.schema_id)) + ''.'' + QUOTENAME(t.name) AS [obj_name],
												QUOTENAME(c.name) AS [col_name],
												N''VARCHAR column without specified length, it should not have a length of '' + CAST (c.max_length AS varchar(10)) + '''' AS [message],
												N''https://github.com/LowlyDBA/ExpressSQL/tree/master#unspecified-varchar-length'' AS [ref_link]
										FROM sys.columns as c
											inner join sys.tables as t on t.object_id = c.object_id
											inner join sys.types as ty on ty.user_type_id = c.user_type_id
										WHERE c.is_identity = 0 	--exclude identity cols
											AND t.is_ms_shipped = 0 --exclude sys table
											AND ty.name IN (''VARCHAR'', ''NVARCHAR'')
											AND c.max_length = 1)

									INSERT INTO #results ([check_num], [check_type], [obj_type], [db_name], [obj_name], [col_name], [message], [ref_link])
									SELECT	3, 
											N''Data Formats'',
											N''USER_TABLE'',
											QUOTENAME(DB_NAME()),
											[obj_name],
											[col_name],
											[message],
											[ref_link]
									FROM [UnspecifiedVarChar];'
				FROM #Databases;
				EXEC sp_executesql @checkSQL;
			END; --Check 3
	
		/* Check 4: Mad MAX - Varchar(MAX) */
		RAISERROR('Check 4: Mad MAX VARCHAR', 10, 1) WITH NOWAIT;
			BEGIN
				SET @checkSQL = N'';
				SELECT @checkSQL = @checkSQL + N'USE ' + [database_name] + N';
								INSERT INTO #results ([check_num], [check_type], [obj_type], [db_name], [obj_name], [col_name], [message], [ref_link])
								SELECT 4,	
									N''Data Formats'', 
									N''USER_TABLE'',
									QUOTENAME(DB_NAME()),
									QUOTENAME(SCHEMA_NAME(t.schema_id)) + ''.'' + QUOTENAME(t.name), 
									QUOTENAME(c.name), 
									N''Column is NVARCHAR(MAX) which allows very large row sizes. Consider a character limit.'', 
									N''https://goo.gl/uiltVb''
								FROM sys.columns as c
									 inner join sys.tables as t on t.object_id = c.object_id
									 inner join sys.types as ty on ty.user_type_id = c.user_type_id
								WHERE t.is_ms_shipped = 0 --exclude sys table
									 AND ty.[name] = ''nvarchar''
									 AND c.max_length = -1;'
				FROM #Databases;
				EXEC sp_executesql @checkSQL;
			END; --Check 4
		
		/* Check 5: User DB or model db  Growth set past 10GB - ONLY IF EXPRESS*/
		RAISERROR('Check 5: Data file growth set past 10GB (EXPRESS)', 10, 1) WITH NOWAIT;
		IF(@isExpress = 1)
			BEGIN
				SET @checkSQL = N'';
				SELECT @checkSQL = @checkSQL + N'USE ' + [database_name] + N';
								INSERT INTO #results ([check_num], [check_type], [obj_type], [db_name], [obj_name], [col_name], [message], [ref_link])
								SELECT 5, 
									N''Database Growth'', 
									N''DATABASE'', 
									QUOTENAME(DB_NAME()),
									QUOTENAME(DB_NAME(database_id)), 
									NULL, 
									N''Database file '' + name + '' has a maximum growth set to '' + CASE 
																										WHEN max_size = -1 
																											THEN ''Unlimited''
																										WHEN max_size > 0
																											THEN CAST((max_size / 1024) * 8 AS VARCHAR(MAX))
																									END + '', which is over the user database maximum file size of 10GB.'', 
									N''http://''
								 FROM sys.master_files mf
								 WHERE (max_size > 1280000 OR max_size = -1) -- greater than 10GB or unlimited
									 AND [mf].[database_id] > 5
									 AND [mf].[data_space_id] > 0 -- limit doesn''t apply to log files;'
				FROM #Databases
				EXEC sp_executesql @checkSQL;
			END; --Check 5
		ELSE
			BEGIN
				RAISERROR('Skipping check 5...', 10, 1) WITH NOWAIT;
			END;

		/* Check 6: User DB or model db growth set to % */
		RAISERROR('Check 6: Data file growth set to %', 10, 1) WITH NOWAIT;
		BEGIN
			INSERT INTO #results ([check_num], [check_type], [obj_type], [db_name], [obj_name], [col_name], [message], [ref_link])
				SELECT 6,
						N'Database Growth',
						N'DATABASE',
						QUOTENAME(DB_NAME([sd].[database_id])),
						[mf].[name],
						NULL,
						N'Database file '+[mf].[name]+' has growth set to % instead of a fixed amount. This may grow quickly.',
						N'http://'
				FROM [sys].[master_files] AS [mf]
					INNER JOIN [sys].[databases] AS [sd] ON [sd].[database_id] = [mf].[database_id]
					INNER JOIN #Databases AS [d] ON [d].[database_name] = [sd].[name]
				WHERE [mf].[is_percent_growth] = 1
						AND [mf].[data_space_id] = 1 ; --ignore log files
		 END; --Check 6

		/* Check 7: Do you really need Nvarchar*/
		RAISERROR('Check 7: Use of NVARCHAR (EXPRESS)', 10, 1) WITH NOWAIT;
		IF(@isExpress = 1)
			BEGIN
				SET @checkSQL = N'';
				SELECT @checkSQL = @checkSQL + N'USE ' + [database_name] + N';
												INSERT INTO #results ([check_num], [check_type], [obj_type], [db_name], [obj_name], [col_name], [message], [ref_link])
												SELECT 7
													, N''Data Formats''
													, N''USER_TABLE''
													, DB_NAME()
													, QUOTENAME(SCHEMA_NAME([o].schema_id)) + ''.'' + QUOTENAME(OBJECT_NAME([o].object_id))
													, QUOTENAME([ac].[name])
													, N''nvarchar columns take 2x the space per char of varchar. Only use if you need Unicode characters.''
													, N''http://''
												FROM   [sys].[all_columns] AS [ac]
														INNER JOIN [sys].[types] AS [t] ON [t].[user_type_id] = [ac].[user_type_id]
														INNER JOIN [sys].[objects] AS [o] ON [o].object_id = [ac].object_id
												WHERE  [t].[name] = ''NVARCHAR''
														AND [o].[is_ms_shipped] = 0'
				FROM #Databases
				EXEC sp_executesql @checkSQL;
			 END; 
		ELSE
			BEGIN
				RAISERROR('Skipping check 7...', 10, 1) WITH NOWAIT;
			END; --Check 7

		/* Check 8: BIGINT for identity values - sure its needed ?  - ONLY IF EXPRESS*/
		RAISERROR('Check 8: BIGINT used for identity columns (EXPRESS)', 10, 1) WITH NOWAIT;
		IF(@isExpress = 1)
			BEGIN
				SET @checkSQL = N'';
				SELECT @checkSQL = @checkSQL + N'USE ' + [database_name] + N';
									INSERT INTO #results ([check_num], [check_type], [obj_type], [db_name], [obj_name], [col_name], [message], [ref_link])
									SELECT  8, 
												N''Data Formats'', 
												N''USER_TABLE'', 
												QUOTENAME(DB_NAME()),
												QUOTENAME(SCHEMA_NAME(t.schema_id)) + ''.'' + QUOTENAME(t.name), 
												QUOTENAME(c.name), 
												N''BIGINT used on IDENTITY column in SQL Express. If values will never exceed 2,147,483,647 use INT instead.'', 
												N''https://goo.gl/uiltVb''
										FROM sys.columns as c
											INNER JOIN sys.tables as t on t.object_id = c.object_id
											INNER JOIN sys.types as ty on ty.user_type_id = c.user_type_id
										WHERE t.is_ms_shipped = 0 --exclude sys table
											AND ty.name = ''BIGINT''
											AND c.is_identity = 1;'
				FROM #Databases
				EXEC sp_executesql @checkSQL;
			END; --Check 8
		ELSE --Skip check 
			BEGIN
				RAISERROR('Skipping check 8...', 10, 1) WITH NOWAIT;
			END;

		/* Check 9: Don't use FLOAT or REAL */
		RAISERROR('Check 9: FLOAT or REAL data types', 10, 1) WITH NOWAIT;
			BEGIN
				SET @checkSQL = N'';
				SELECT @checkSQL = @checkSQL + N'USE ' + [database_name] + N';
									INSERT INTO #results ([check_num], [check_type], [obj_type], [db_name], [obj_name], [col_name], [message], [ref_link])
									SELECT 9,
										N''Data Formats'',
										[o].[type_desc],
										QUOTENAME(DB_NAME()),
										QUOTENAME(SCHEMA_NAME(o.schema_id)) + ''.'' + QUOTENAME(o.name),
										QUOTENAME(ac.name),
										N''Best practice is to use DECIMAL/NUMERIC instead of '' + st.name + '' for non floating point math.'',
										N''https://goo.gl/uiltVb''
									FROM sys.all_columns AS ac
											INNER JOIN sys.objects AS o ON o.object_id = ac.object_id
											INNER JOIN sys.systypes AS st ON st.xtype = ac.system_type_id
									WHERE st.name IN(''FLOAT'', ''REAL'')
											AND o.type_desc = ''USER_TABLE'';'
				FROM #Databases
				EXEC sp_executesql @checkSQL;
			END; --Check 9

		/* Check 10: Don't use deprecated values (NTEXT, TEXT, IMAGE) */
		RAISERROR('Check 10: Deprecated data types', 10, 1) WITH NOWAIT;
			BEGIN
				SET @checkSQL = N'';
				SELECT @checkSQL = @checkSQL + N'USE ' + [database_name] + N';
									INSERT INTO #results ([check_num], [check_type], [obj_type], [db_name], [obj_name], [col_name], [message], [ref_link])
									SELECT 10,
											N''Data Formats'',
											QUOTENAME(DB_NAME()),
											[o].[type_desc],
											QUOTENAME(SCHEMA_NAME(o.schema_id)) + ''.'' + QUOTENAME(o.name),
											QUOTENAME(ac.name),
											N''Deprecated data type in use: '' + st.name + ''.'',
											N''https://goo.gl/u9SgEj''
									FROM sys.all_columns AS ac
											INNER JOIN sys.objects AS o ON o.object_id = ac.object_id
											INNER JOIN sys.systypes AS st ON st.xtype = ac.system_type_id
									WHERE st.name IN(''NEXT'', ''TEXT'', ''IMAGE'')
											AND o.type_desc = ''USER_TABLE'';'
				FROM #Databases
				EXEC sp_executesql @checkSQL;
			END; --Check 10

		/* Check 11: Non-default fill factor */
		RAISERROR('Check 11: Non-default fill factor (EXPRESS)', 10, 1) WITH NOWAIT;
		IF(@isExpress = 1)
			BEGIN
				SET @checkSQL = N'';
				SELECT @checkSQL = @checkSQL + N'USE ' + [database_name] + N';
									INSERT INTO #results ([check_num], [check_type], [obj_type], [db_name], [obj_name], [col_name], [message], [ref_link])
									SELECT 11,
											N''Fill Factor'',
											QUOTENAME(DB_NAME()),
											N''INDEX'',
											QUOTENAME(SCHEMA_NAME([o].[schema_id])) + ''.'' + QUOTENAME([o].[name]) + ''.'' + QUOTENAME([i].[name]),
											NULL,
											N''Non-default fill factor on this index. Not inherently bad, but will increase table size more quickly.'',
											N''http://''
									FROM [sys].[indexes] AS [i]
											INNER JOIN [sys].[objects] AS [o] ON [o].[object_id] = [i].[object_id]
									WHERE [i].[fill_factor] NOT IN(0, 100);'
				FROM #Databases;
				EXEC sp_executesql @checkSQL;
			END; --Check 11
		ELSE --Skip check
			BEGIN
				RAISERROR('Skipping check 11...', 10, 1) WITH NOWAIT;
			END;

		/* Check 12: Questionable number of indexes */
		RAISERROR('Check 12: Too many indexes', 10, 1) WITH NOWAIT;
		BEGIN
			SET @checkSQL = N'';
			SELECT @checkSQL = @checkSQL + N'USE ' + [database_name] + N';
									INSERT INTO #results ([check_num], [check_type], [obj_type], [db_name], [obj_name], [col_name], [message], [ref_link])
									SELECT 12,
											N''Lotsa Indexes'',
											N''INDEX'',
											QUOTENAME(DB_NAME()),
											QUOTENAME(SCHEMA_NAME(t.schema_id)) + ''.'' + QUOTENAME(t.name),
											NULL,
											''There are '' + CAST(COUNT(DISTINCT(i.index_id)) AS VARCHAR) + '' indexes on this table taking up '' + CAST(CAST(SUM(s.[used_page_count]) * 8 / 1024.00 AS DECIMAL(10, 2)) AS VARCHAR) + '' MB of space.'',
											''http''
									FROM sys.indexes AS i
											INNER JOIN sys.tables AS t ON i.object_id = t.object_id
											INNER JOIN sys.dm_db_partition_stats AS s ON s.object_id = i.object_id
																			AND s.index_id = i.index_id
									WHERE t.is_ms_shipped = 0 --exclude sys table
											AND i.type_desc = ''NONCLUSTERED'' --exclude clustered indexes from count
											AND DB_ID() > 4
									GROUP BY t.name,
												t.schema_id
									HAVING COUNT(DISTINCT(i.index_id)) > @IndexNumThreshold;'
			FROM #Databases;
			EXEC sp_executesql @checkSQL, N'@IndexNumThreshold TINYINT', @IndexNumThreshold = @IndexNumThreshold; 
		 END; -- Check 12

		/* Check 13: Should sparse columns be used? */
		/* https://docs.microsoft.com/en-us/sql/relational-databases/tables/use-sparse-columns?view=sql-server-2017 */
		RAISERROR('Check 13: Sparse column eligibility', 10, 1) WITH NOWAIT;
			IF @hasSparse = 1
				BEGIN
					IF OBJECT_ID('tempdb..#SparseTypes') IS NOT NULL
						BEGIN;
							DROP TABLE [#SparseTypes];
						END;
					IF OBJECT_ID('tempdb..#Stats') IS NOT NULL
						BEGIN;
							DROP TABLE [#Stats];
						END;
					IF OBJECT_ID('tempdb..#StatsHeaderStaging') IS NOT NULL
						BEGIN;
							DROP TABLE [#StatsHeaderStaging];
						END;
					IF OBJECT_ID('tempdb..#StatHistogramStaging') IS NOT NULL
						BEGIN;
							DROP TABLE [#StatHistogramStaging];
						END;
	
					CREATE TABLE #SparseTypes (
							[ID] INT IDENTITY(1,1) NOT NULL,
							[name] VARCHAR(20),
							[user_type_ID] INT,
							[scale] TINYINT NULL,
							[precision] TINYINT NOT NULL,
							[threshold_null_perc] TINYINT NOT NULL);

					CREATE CLUSTERED INDEX cidx_#sparsetypes ON #SparseTypes([ID]);

					/*	Reference values for when it makes sense to use the sparse feature based on 40% minimum space savings
						including if those recommendations change based on scale / precision. Conservative estimates are used
						when a column is in between the high and low values in the table.
						https://docs.microsoft.com/en-us/sql/relational-databases/tables/use-sparse-columns?view=sql-server-2017#estimated-space-savings-by-data-type */ 	
					INSERT INTO #SparseTypes ([name], [user_type_ID], [scale], [precision], [threshold_null_perc])
					VALUES	('BIT',104, 0,0, 98),
							('TINYINT',48, 0,0, 86),
							('SMALLINT',52, 0,0, 76),
							('INT',56, 0,0, 64),
							('BIGINT',127, 0,0, 52),
							('REAL',59, 0,0, 64),
							('FLOAT',62, 0,0, 52),
							('SMALLMONEY',122, 0,0, 64),
							('MONEY',60, 0,0, 52),
							('SMALLDATETIME',58, 0,0, 64),
							('DATETIME',61, 0,0, 52),
							('UNIQUEIDENTIFIER',36, 0,0, 43),
							('DATE',40, 0,0, 69),
							('DATETIME2',42, 0,0, 57),
							('DATETIME2',42, 7,0, 52),
							('TIME',41, 0,0, 69),
							('TIME',41, 7,0, 60),
							('DATETIMEOFFSET',43, 0,0, 52),
							('DATETIMEOFFSET',43, 7,0, 49),
							('VARCHAR',167, 0,0, 60),
							('CHAR',175, 0,0, 60),
							('NVARCHAR',231, 0,0, 60),
							('NCHAR',239, 0,0, 60),
							('VARBINARY',165, 0,0, 60),
							('BINARY',173, 0,0, 60),
							('XML',241, 0,0, 60),
							('HIERARCHYID',128, 0,0, 60),
							('DECIMAL', 106, NULL, 1, 60), 
							('DECIMAL', 106, NULL, 38, 42), 
							('NUMERIC', 108, NULL, 1, 60), 
							('NUMERIC', 108, NULL, 38, 42);

					CREATE TABLE #StatsHeaderStaging (
						 [name] SYSNAME 
						,[updated] DATETIME2(0)
						,[rows] BIGINT
						,[rows_sampled] BIGINT
						,[steps] INT
						,[density] DECIMAL(6,3)
						,[average_key_length] DECIMAL(5,2)
						,[string_index] VARCHAR(10)
						,[filter_expression] nvarchar(max)
						,[unfiltered_rows] BIGINT);
						
					--2016 SP1 CU4 adds extra column
					IF (@fullVersion = 13 AND @minorVersion >= 4446)
						BEGIN
							ALTER TABLE #StatsHeaderStaging
							ADD [persisted_sample_percent] INT;
						END
						
					CREATE TABLE #StatHistogramStaging (
						 [range_hi_key] NVARCHAR(MAX)
						,[range_rows] BIGINT
						,[eq_rows] DECIMAL(38,2)
						,[distinct_range_rows] BIGINT
						,[avg_range_rows] BIGINT);

					CREATE TABLE #Stats (
						 [stats_id] INT IDENTITY(1,1)
						,[db_name] SYSNAME
						,[stat_name] SYSNAME 
						,[stat_updated] DATETIME2(0)
						,[rows] BIGINT
						,[rows_sampled] BIGINT
						,[schema_name] SYSNAME
						,[table_name] SYSNAME NULL
						,[col_name] SYSNAME NULL
						,[eq_rows] BIGINT NULL
						,[null_perc] AS CAST([eq_rows] AS DECIMAL (38,2)) /[rows] * 100
						,[threshold_null_perc] SMALLINT);

					CREATE CLUSTERED INDEX cidx_#stats ON #Stats([stats_id]);

					DECLARE @db_name SYSNAME;
					DECLARE @tempStatSQL NVARCHAR(MAX) = N'';
					DECLARE @statSQL NVARCHAR(MAX) = 
						N'	USE ?;
							BEGIN
								DECLARE	@schemaName SYSNAME,
										@tableName SYSNAME, 
										@statName SYSNAME, 
										@colName SYSNAME, 
										@threshold_null_perc SMALLINT;

								DECLARE @DBCCSQL NVARCHAR(MAX) = N'''';
								DECLARE @DBCCStatSQL NVARCHAR(MAX) = N'''';
								DECLARE @DBCCHistSQL NVARCHAR(MAX) = N'''';

								DECLARE [DBCC_Cursor] CURSOR LOCAL FAST_FORWARD
								FOR SELECT DISTINCT	  sch.name	AS [schema_name]
													, t.name	AS [table_name]
													, s.name	AS [stat_name]
													, ac.name	AS [col_name]
													, threshold_null_perc 
									FROM [sys].[stats] AS [s] 
										INNER JOIN [sys].[stats_columns] AS [sc] on sc.stats_id = s.stats_id
										INNER JOIN [sys].[tables] AS [t] on t.object_id = s.object_id
										INNER JOIN [sys].[schemas] AS [sch] on sch.schema_id = t.schema_id
										INNER JOIN [sys].[all_columns] AS [ac] on ac.column_id = sc.column_id
																AND [ac].[object_id] = [t].[object_id]
																AND [ac].[object_id] = [sc].[object_id]
										INNER JOIN [sys].[types] AS [typ] ON [typ].[user_type_id] = [ac].[user_type_id]
										LEFT JOIN [sys].[indexes] AS [i] ON i.object_id = t.object_id
																AND i.name = s.name
										LEFT JOIN [sys].[index_columns] AS [ic] ON [ic].[object_id] = [i].[object_id]
																AND [ic].[column_id] = [ac].[column_id]
																AND ic.index_id = i.index_id
										INNER JOIN [#SparseTypes] AS [st] ON [st].[user_type_id] = [typ].[user_type_id]
																AND (typ.name NOT IN (''DECIMAL'', ''NUMERIC'', ''DATETIME2'', ''TIME'', ''DATETIMEOFFSET''))
																OR (typ.name IN (''DECIMAL'', ''NUMERIC'') AND st.precision = ac.precision AND st.precision = 1)
																OR (typ.name IN (''DECIMAL'', ''NUMERIC'') AND ac.precision > 1 AND st.precision = 38)
																OR (typ.name IN (''DATETIME2'', ''TIME'', ''DATETIMEOFFSET'') AND st.scale = ac.scale AND st.scale = 0)
																OR (typ.name IN (''DATETIME2'', ''TIME'', ''DATETIMEOFFSET'') AND ac.scale > 0 AND st.scale = 7)
									WHERE [sc].[stats_column_id] = 1 
										AND [s].[has_filter] = 0 
										AND [s].[no_recompute] = 0 
										AND [ac].[is_nullable] = 1 ';

					IF @hasTempStat = 1 
						BEGIN
							SET @statSQL = @statSQL + N'AND [s].[is_temporary] = 0 ';
						END
									
					SET @statSQL = @statSQL + N'
										AND ([ic].[index_column_id] = 1 OR [ic].[index_column_id] IS NULL)
										AND ([i].[type_desc] =''NONCLUSTERED'' OR [i].[type_desc] IS NULL)
								
								OPEN [DBCC_Cursor];

								FETCH NEXT FROM [DBCC_Cursor]
								INTO @schemaName, @tableName, @statName, @colName, @threshold_null_perc;

								WHILE @@FETCH_STATUS = 0
									BEGIN;
										/* Build DBCC statistics queries */
										SET @DBCCSQL = N''DBCC SHOW_STATISTICS('''''' + @schemaName + ''.'' + @tableName + '''''', '''''' + @statName + '''''')'';
										SET @DBCCStatSQL = @DBCCSQL + '' WITH STAT_HEADER, NO_INFOMSGS;'';
										SET @DBCCHistSQL = @DBCCSQL + '' WITH HISTOGRAM, NO_INFOMSGS;'';

										/* Stat Header */
										INSERT INTO #StatsHeaderStaging 
										EXEC sp_executeSQL @DBCCStatSQL;

										/* Histogram */
										INSERT INTO #StatHistogramStaging 
										EXEC sp_executesql @DBCCHistSQL;		
										
										INSERT INTO #Stats  
										SELECT	  QUOTENAME(DB_NAME())
												, [head].[name]
												, [head].[updated]
												, [head].[rows]
												, [head].[rows_Sampled]
												, @schemaName
												, @tableName
												, @colName
												, [hist].[eq_rows]
												, @threshold_null_perc
										FROM #StatsHeaderStaging head 
											CROSS APPLY #StatHistogramStaging hist
										WHERE hist.RANGE_HI_KEY IS NULL
											AND hist.eq_rows > 0
											AND head.Unfiltered_rows > 0
											AND head.rows > 1000;

										TRUNCATE TABLE #StatsHeaderStaging; 
										TRUNCATE TABLE #StatHistogramStaging;

										FETCH NEXT FROM DBCC_Cursor 
										INTO @schemaName, @tableName, @statName, @colName, @threshold_null_perc;
									END;
								CLOSE [DBCC_Cursor];
								DEALLOCATE [DBCC_Cursor];
							END;'

					DECLARE [DB_Cursor] CURSOR LOCAL FAST_FORWARD
					FOR SELECT QUOTENAME([database_name])
						FROM #Databases;

					OPEN [DB_Cursor];

					FETCH NEXT FROM [DB_Cursor]
					INTO @db_name

					/* Run stat query for each database */
					WHILE @@FETCH_STATUS = 0
						BEGIN
							SET @tempStatSQL = REPLACE(@statSQL, N'?', @db_name);

							EXEC sp_executeSQL @tempStatSQL;

							FETCH NEXT FROM [DB_Cursor]
							INTO @db_name;
						END;
					CLOSE [DB_Cursor];
					DEALLOCATE [DB_Cursor];
					
					INSERT INTO #results ([check_num], [check_type], [obj_type], [db_name], [obj_name], [col_name], [message], [ref_link])
					SELECT	13, 
							N'Feature', 
							N'USER_TABLE', 
							[db_name], 
							QUOTENAME([schema_name]) + '.' + QUOTENAME([table_name]), 
							QUOTENAME([col_name]), 
							N'Candidate for converting to a space-saving sparse column based on NULL distribution of more than ' + CAST(threshold_null_perc AS VARCHAR(3))+ ' percent.', 
							N'http://'
					FROM #stats
					WHERE [null_perc] >= [threshold_null_perc];
				END; --Check 13
			ELSE 
				BEGIN;
					RAISERROR('Skipping check 13 - sparse columns not available in this version.', 10, 1) WITH NOWAIT;
				END;

		/* Check 14: numeric or decimal with 0 scale */
		RAISERROR('Check 14: NUMERIC or DECIMAL with scale of 0', 10, 1) WITH NOWAIT;
		BEGIN
			SET @checkSQL = N'';
			SELECT @checkSQL = @checkSQL + N'USE ' + [database_name] + N';
								INSERT INTO #results ([check_num], [check_type], [obj_type], [db_name], [obj_name], [col_name], [message], [ref_link])
								SELECT 14,
										N''Data Formats'',
										QUOTENAME(DB_NAME()),
										[o].[type_desc],
										QUOTENAME(SCHEMA_NAME(o.schema_id)) + ''.'' + QUOTENAME(o.name),
										QUOTENAME(ac.name),
										N''Column is '' + UPPER(st.name) + ''('' + CAST(ac.precision AS VARCHAR) + '','' + CAST(ac.scale AS VARCHAR) + '')'' 
											+ '' . Consider using an INT variety for space reduction since the scale is 0.'',
										N''https://goo.gl/agh5CA''
								FROM sys.objects AS o
										INNER JOIN sys.all_columns AS ac ON ac.object_id = o.object_id
										INNER JOIN sys.systypes AS st ON st.xtype = ac.system_type_id
								WHERE ac.scale = 0
										AND st.name IN(''DECIMAL'', ''NUMERIC'');'
			FROM #Databases
			EXEC sp_executesql @checkSQL;
		 END; --Check 14
		
		/* Wrap it up */
		SELECT * 
		FROM #results
		ORDER BY check_num, db_name, obj_type, obj_name, col_name;

		RAISERROR('', 10, 1) WITH NOWAIT;
		RAISERROR('Done!', 10, 1) WITH NOWAIT;

	END TRY
	 
	BEGIN CATCH;
		BEGIN
			DECLARE @ErrorNumber INT = ERROR_NUMBER();
			DECLARE @ErrorLine INT = ERROR_LINE();
			DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
			DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
			DECLARE @ErrorState INT = ERROR_STATE();
			
			IF (@debug = 1)
				BEGIN
					PRINT 'Actual error number: ' + CAST(@ErrorNumber AS VARCHAR(10));
					PRINT 'Actual line number: ' + CAST(@ErrorLine AS VARCHAR(10));
				END
 
			RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState);
		END
	 END CATCH;
GO