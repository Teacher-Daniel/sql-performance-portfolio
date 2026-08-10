/*
Experiment 05 - Inspect PSP environment

Purpose:
Verify compatibility level, parameter-related database configuration,
Query Store state, baseline indexes, statistics, test objects, and
the common/rare cardinalities used by this experiment.

This script does not modify the database.
*/

USE FleetTelemetryLab;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF COALESCE
(
    CONVERT(sysname, SERVERPROPERTY(N'InstanceName')),
    N'MSSQLSERVER'
) <> N'SQL2025LAB'
BEGIN
    THROW 51000, 'Safety check failed: execute this script on SQL2025LAB.', 1;
END;
GO

IF DB_NAME() <> N'FleetTelemetryLab'
BEGIN
    THROW 51001, 'Safety check failed: the current database must be FleetTelemetryLab.', 1;
END;
GO

IF OBJECT_ID(N'telemetry.TelemetryEvent', N'U') IS NULL
BEGIN
    THROW 51002, 'The table telemetry.TelemetryEvent does not exist.', 1;
END;
GO

DECLARE @ObjectId int =
    OBJECT_ID(N'telemetry.TelemetryEvent');

/*
Result set 1:
Server and database environment.
*/
SELECT
    CONVERT(sysname, SERVERPROPERTY(N'ServerName')) AS ServerName,
    CONVERT(nvarchar(128), SERVERPROPERTY(N'ProductVersion'))
        AS ProductVersion,
    DB_NAME() AS DatabaseName,
    d.compatibility_level AS CompatibilityLevel
FROM sys.databases AS d
WHERE d.database_id = DB_ID();

/*
Result set 2:
PSP and parameter-sniffing configuration.
*/
SELECT
    dsc.name AS ConfigurationName,
    dsc.value AS ConfigurationValue,
    dsc.value_for_secondary AS ValueForSecondary
FROM sys.database_scoped_configurations AS dsc
WHERE dsc.name IN
(
    N'PARAMETER_SENSITIVE_PLAN_OPTIMIZATION',
    N'PARAMETER_SNIFFING'
)
ORDER BY dsc.name;

/*
Result set 3:
Query Store configuration.
*/
SELECT
    qso.actual_state_desc AS ActualState,
    qso.desired_state_desc AS DesiredState,
    qso.query_capture_mode_desc AS CaptureMode,
    qso.current_storage_size_mb AS CurrentStorageMB,
    qso.max_storage_size_mb AS MaximumStorageMB,
    qso.interval_length_minutes AS IntervalLengthMinutes,
    qso.stale_query_threshold_days AS StaleQueryThresholdDays
FROM sys.database_query_store_options AS qso;

/*
Result set 4:
No experimental nonclustered index should exist.
An empty result is expected.
*/
SELECT
    i.name AS IndexName,
    i.type_desc AS IndexType,
    i.is_unique AS IsUnique,
    i.is_disabled AS IsDisabled
FROM sys.indexes AS i
WHERE i.object_id = @ObjectId
  AND i.index_id > 1
ORDER BY i.name;

/*
Result set 5:
The original automatic EventType statistic should remain.
*/
SELECT
    s.stats_id AS StatsId,
    s.name AS StatisticsName,
    s.auto_created AS IsAutoCreated,
    s.user_created AS IsUserCreated,
    sp.last_updated AS LastUpdated,
    sp.rows AS TableRows,
    sp.rows_sampled AS RowsSampled,
    sp.steps AS HistogramSteps
FROM sys.stats AS s
INNER JOIN sys.stats_columns AS sc
    ON sc.object_id = s.object_id
   AND sc.stats_id = s.stats_id
INNER JOIN sys.columns AS c
    ON c.object_id = sc.object_id
   AND c.column_id = sc.column_id
OUTER APPLY sys.dm_db_stats_properties
(
    s.object_id,
    s.stats_id
) AS sp
WHERE s.object_id = @ObjectId
  AND sc.stats_column_id = 1
  AND c.name = N'EventType'
ORDER BY
    s.auto_created DESC,
    s.user_created DESC,
    s.stats_id;

/*
Result set 6:
No procedures from this experiment should exist.
An empty result is expected.
*/
SELECT
    SCHEMA_NAME(p.schema_id) AS SchemaName,
    p.name AS ProcedureName,
    p.create_date AS CreatedAt,
    p.modify_date AS ModifiedAt
FROM sys.procedures AS p
WHERE p.schema_id = SCHEMA_ID(N'telemetry')
  AND p.name IN
  (
      N'usp_EventTypeSummary_NoPsp',
      N'usp_EventTypeSummary_Psp'
  )
ORDER BY p.name;

/*
Result set 7:
Confirm the deterministic common and rare cardinalities.
*/
SELECT
    te.EventType,
    COUNT_BIG(*) AS EventCount
FROM telemetry.TelemetryEvent AS te
WHERE te.EventType IN (1, 5)
  AND te.EventTime >= '2024-12-06T00:00:00'
  AND te.EventTime <  '2024-12-07T00:00:00'
GROUP BY te.EventType
ORDER BY te.EventType;
GO
