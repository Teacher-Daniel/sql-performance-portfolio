/*
Experiment 02 - Cleanup

Purpose:
Remove the experimental DeviceId index and restore FleetTelemetryLab
to its original unoptimized index state.

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

DECLARE @IndexExistedBeforeCleanup bit =
    CASE
        WHEN EXISTS
        (
            SELECT 1
            FROM sys.indexes
            WHERE object_id = OBJECT_ID(N'telemetry.TelemetryEvent')
              AND name = N'IX_TelemetryEvent_DeviceId'
        )
        THEN 1
        ELSE 0
    END;

DECLARE @CleanupStartedAt datetime2(7) = SYSDATETIME();

DROP INDEX IF EXISTS IX_TelemetryEvent_DeviceId
ON telemetry.TelemetryEvent;

DECLARE @CleanupElapsedMilliseconds bigint =
    DATEDIFF_BIG
    (
        MILLISECOND,
        @CleanupStartedAt,
        SYSDATETIME()
    );

SELECT
    N'IX_TelemetryEvent_DeviceId' AS IndexName,
    CASE
        WHEN EXISTS
        (
            SELECT 1
            FROM sys.indexes
            WHERE object_id = OBJECT_ID(N'telemetry.TelemetryEvent')
              AND name = N'IX_TelemetryEvent_DeviceId'
        )
        THEN N'PRESENT'
        ELSE N'REMOVED'
    END AS IndexStatus,
    @IndexExistedBeforeCleanup AS IndexExistedBeforeCleanup,
    @CleanupElapsedMilliseconds AS CleanupElapsedMilliseconds;
GO
