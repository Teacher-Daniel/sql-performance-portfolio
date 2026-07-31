/*
Purpose:
    Validate the SQL Server performance lab configuration.

Expected target:
    SQL Server 2025 Standard Developer Edition.

Requirements:
    The executing login must have permission to read server-level
    configuration and service information.
*/

SET NOCOUNT ON;

PRINT '1. SQL Server build and edition';

SELECT
    SERVERPROPERTY('ServerName') AS ServerName,
    SERVERPROPERTY('ProductVersion') AS ProductVersion,
    SERVERPROPERTY('ProductLevel') AS ProductLevel,
    SERVERPROPERTY('ProductUpdateLevel') AS ProductUpdateLevel,
    SERVERPROPERTY('ProductUpdateReference') AS ProductUpdateReference,
    SERVERPROPERTY('Edition') AS Edition,
    SERVERPROPERTY('Collation') AS Collation,
    CASE CONVERT(int, SERVERPROPERTY('IsIntegratedSecurityOnly'))
        WHEN 1 THEN 'Windows Authentication'
        ELSE 'Mixed Mode'
    END AS AuthenticationMode;

PRINT '2. Instance configuration';

SELECT
    name,
    value AS ConfiguredValue,
    value_in_use AS ValueInUse
FROM sys.configurations
WHERE name IN
(
    'cost threshold for parallelism',
    'max degree of parallelism',
    'max server memory (MB)'
)
ORDER BY name;

PRINT '3. TempDB configuration';

SELECT
    file_id AS FileId,
    name AS LogicalName,
    type_desc AS FileType,
    CAST(size / 128.0 AS decimal(10, 2)) AS SizeMB,
    CASE
        WHEN is_percent_growth = 0
        THEN CAST(growth / 128.0 AS decimal(10, 2))
    END AS GrowthMB,
    is_percent_growth AS IsPercentGrowth,
    physical_name AS PhysicalName
FROM tempdb.sys.database_files
ORDER BY file_id;

PRINT '4. SQL Server services';

SELECT
    servicename AS ServiceName,
    startup_type_desc AS StartupType,
    status_desc AS ServiceStatus,
    instant_file_initialization_enabled AS InstantFileInitialization
FROM sys.dm_server_services
WHERE servicename LIKE 'SQL Server (%'
   OR servicename LIKE 'SQL Server Agent (%'
ORDER BY servicename;

PRINT '5. Host resources visible to SQL Server';

SELECT
    cpu_count AS LogicalProcessorCount,
    scheduler_count AS OnlineSchedulerCount,
    CAST(physical_memory_kb / 1024.0 AS decimal(10, 2))
        AS PhysicalMemoryMB,
    sqlserver_start_time AS SQLServerStartTime
FROM sys.dm_os_sys_info;

PRINT 'Environment validation complete.';
