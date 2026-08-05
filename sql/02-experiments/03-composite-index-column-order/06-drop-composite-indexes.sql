/*
Experiment 03 - Cleanup

Purpose:
Remove either experimental composite index and restore
FleetTelemetryLab to its original unoptimized index state.

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

DECLARE @EventTimeLeadingIndexExisted bit =
    CASE
        WHEN EXISTS
        (
            SELECT 1
            FROM sys.indexes
            WHERE object_id = OBJECT_ID(N'telemetry.TelemetryEvent')
              AND name = N'IX_TelemetryEvent_EventTime_DeviceId'
        )
        THEN 1
        ELSE 0
    END;

DECLARE @DeviceIdLeadingIndexExisted bit =
    CASE
        WHEN EXISTS
        (
            SELECT 1
            FROM sys.indexes
            WHERE object_id = OBJECT_ID(N'telemetry.TelemetryEvent')
              AND name = N'IX_TelemetryEvent_DeviceId_EventTime'
        )
        THEN 1
        ELSE 0
    END;

DECLARE @CleanupStartedAt datetime2(7) = SYSDATETIME();

DROP INDEX IF EXISTS IX_TelemetryEvent_EventTime_DeviceId
ON telemetry.TelemetryEvent;

DROP INDEX IF EXISTS IX_TelemetryEvent_DeviceId_EventTime
ON telemetry.TelemetryEvent;

DECLARE @CleanupElapsedMilliseconds bigint =
    DATEDIFF_BIG
    (
        MILLISECOND,
        @CleanupStartedAt,
        SYSDATETIME()
    );

SELECT
    expected.IndexName,
    expected.IndexExistedBeforeCleanup,
    CASE
        WHEN i.index_id IS NULL THEN N'REMOVED'
        ELSE N'PRESENT'
    END AS IndexStatus
FROM
(
    VALUES
        (
            1,
            N'IX_TelemetryEvent_EventTime_DeviceId',
            @EventTimeLeadingIndexExisted
        ),
        (
            2,
            N'IX_TelemetryEvent_DeviceId_EventTime',
            @DeviceIdLeadingIndexExisted
        )
) AS expected
(
    SortOrder,
    IndexName,
    IndexExistedBeforeCleanup
)
LEFT JOIN sys.indexes AS i
    ON i.object_id = OBJECT_ID(N'telemetry.TelemetryEvent')
   AND i.name = expected.IndexName
ORDER BY expected.SortOrder;

SELECT
    @CleanupElapsedMilliseconds AS CleanupElapsedMilliseconds;
GO
