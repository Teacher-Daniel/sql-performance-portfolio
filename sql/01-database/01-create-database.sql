/*
Purpose:
    Create the FleetTelemetryLab database and configure its
    reproducible performance-lab settings.

Safety:
    - Must run against the SQL2025LAB instance.
    - Requires SQL Server 2025.
    - Stops if the database already exists.
    - Never drops or overwrites an existing database.
*/

USE [master];
GO

SET NOCOUNT ON;
GO

IF CONVERT(int, SERVERPROPERTY('ProductMajorVersion')) <> 17
   OR CONVERT(sysname, SERVERPROPERTY('InstanceName')) <> N'SQL2025LAB'
BEGIN
    THROW 50001,
        'Run this script on the SQL Server 2025 instance SQL2025LAB.',
        1;
END;
GO

IF DB_ID(N'FleetTelemetryLab') IS NOT NULL
BEGIN
    THROW 50002,
        'FleetTelemetryLab already exists. This script will not overwrite it.',
        1;
END;
GO

CREATE DATABASE [FleetTelemetryLab];
GO

ALTER DATABASE [FleetTelemetryLab]
MODIFY FILE
(
    NAME = N'FleetTelemetryLab',
    SIZE = 256 MB,
    FILEGROWTH = 128 MB
);
GO

ALTER DATABASE [FleetTelemetryLab]
MODIFY FILE
(
    NAME = N'FleetTelemetryLab_log',
    SIZE = 128 MB,
    FILEGROWTH = 64 MB
);
GO

ALTER DATABASE [FleetTelemetryLab]
SET COMPATIBILITY_LEVEL = 170;
GO

ALTER DATABASE [FleetTelemetryLab]
SET RECOVERY SIMPLE;
GO

ALTER DATABASE [FleetTelemetryLab]
SET AUTO_CLOSE OFF;
GO

ALTER DATABASE [FleetTelemetryLab]
SET AUTO_SHRINK OFF;
GO

ALTER DATABASE [FleetTelemetryLab]
SET PAGE_VERIFY CHECKSUM;
GO

ALTER DATABASE [FleetTelemetryLab]
SET AUTO_CREATE_STATISTICS ON;
GO

ALTER DATABASE [FleetTelemetryLab]
SET AUTO_UPDATE_STATISTICS ON;
GO

ALTER DATABASE [FleetTelemetryLab]
SET AUTO_UPDATE_STATISTICS_ASYNC OFF;
GO

ALTER DATABASE [FleetTelemetryLab]
SET QUERY_STORE = ON;
GO

ALTER DATABASE [FleetTelemetryLab]
SET QUERY_STORE
(
    OPERATION_MODE = READ_WRITE,
    CLEANUP_POLICY =
    (
        STALE_QUERY_THRESHOLD_DAYS = 30
    ),
    DATA_FLUSH_INTERVAL_SECONDS = 900,
    INTERVAL_LENGTH_MINUTES = 15,
    MAX_STORAGE_SIZE_MB = 256,
    QUERY_CAPTURE_MODE = AUTO,
    SIZE_BASED_CLEANUP_MODE = AUTO,
    MAX_PLANS_PER_QUERY = 200,
    WAIT_STATS_CAPTURE_MODE = ON
);
GO

USE [FleetTelemetryLab];
GO

ALTER DATABASE SCOPED CONFIGURATION
SET LEGACY_CARDINALITY_ESTIMATION = OFF;
GO

ALTER DATABASE SCOPED CONFIGURATION
SET PARAMETER_SNIFFING = ON;
GO

PRINT 'Database configuration';

SELECT
    name AS DatabaseName,
    compatibility_level AS CompatibilityLevel,
    recovery_model_desc AS RecoveryModel,
    collation_name AS Collation,
    page_verify_option_desc AS PageVerification,
    is_auto_close_on AS IsAutoClose,
    is_auto_shrink_on AS IsAutoShrink,
    is_auto_create_stats_on AS IsAutoCreateStatistics,
    is_auto_update_stats_on AS IsAutoUpdateStatistics,
    is_auto_update_stats_async_on AS IsAsyncStatisticsUpdate
FROM sys.databases
WHERE name = N'FleetTelemetryLab';

PRINT 'Database files';

SELECT
    name AS LogicalName,
    type_desc AS FileType,
    CAST(size / 128.0 AS decimal(10, 2)) AS SizeMB,
    CASE
        WHEN is_percent_growth = 0
        THEN CAST(growth / 128.0 AS decimal(10, 2))
    END AS GrowthMB,
    is_percent_growth AS IsPercentGrowth,
    physical_name AS PhysicalName
FROM sys.database_files
ORDER BY file_id;

PRINT 'Query Store configuration';

SELECT
    actual_state_desc AS ActualState,
    desired_state_desc AS DesiredState,
    query_capture_mode_desc AS CaptureMode,
    current_storage_size_mb AS CurrentStorageMB,
    max_storage_size_mb AS MaximumStorageMB,
    interval_length_minutes AS IntervalLengthMinutes,
    stale_query_threshold_days AS StaleQueryThresholdDays
FROM sys.database_query_store_options;

PRINT 'FleetTelemetryLab created successfully.';
GO
