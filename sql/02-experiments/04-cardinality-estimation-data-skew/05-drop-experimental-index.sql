/*
Experiment 04 - Cleanup

Purpose:
Remove the experimental EventType/EventTime index and its associated
index statistics while preserving the original automatic EventType
statistics.

This script is safe to execute more than once.
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

DECLARE @IndexExistedBeforeCleanup bit =
    CASE
        WHEN EXISTS
        (
            SELECT 1
            FROM sys.indexes
            WHERE object_id = @ObjectId
              AND name = N'IX_TelemetryEvent_EventType_EventTime'
        )
        THEN 1
        ELSE 0
    END;

DECLARE @CleanupStartedAt datetime2(7) = SYSDATETIME();

DROP INDEX IF EXISTS IX_TelemetryEvent_EventType_EventTime
ON telemetry.TelemetryEvent;

DECLARE @CleanupElapsedMilliseconds bigint =
    DATEDIFF_BIG
    (
        MILLISECOND,
        @CleanupStartedAt,
        SYSDATETIME()
    );

SELECT
    N'IX_TelemetryEvent_EventType_EventTime' AS IndexName,
    @IndexExistedBeforeCleanup AS IndexExistedBeforeCleanup,
    CASE
        WHEN EXISTS
        (
            SELECT 1
            FROM sys.indexes
            WHERE object_id = @ObjectId
              AND name = N'IX_TelemetryEvent_EventType_EventTime'
        )
        THEN N'PRESENT'
        ELSE N'REMOVED'
    END AS IndexStatus;

SELECT
    s.name AS RemainingEventTypeStatistics,
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

SELECT
    @CleanupElapsedMilliseconds AS CleanupElapsedMilliseconds;
GO
