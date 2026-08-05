/*
Experiment 03 - Composite index column order baseline

Purpose:
Capture the unoptimized execution of a query combining:

- An equality predicate on DeviceId.
- A range predicate on EventTime.

No supporting nonclustered index should exist.

The query will later be tested with the same covering columns but
opposite composite-key orders.
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

IF EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'telemetry.TelemetryEvent')
      AND index_id > 1
)
BEGIN
    THROW 51003, 'Baseline invalid: an unexpected nonclustered index exists.', 1;
END;
GO

SET STATISTICS IO ON;
SET STATISTICS TIME ON;
GO

PRINT N'Experiment 03 - Composite index column order baseline';

SELECT
    COUNT_BIG(*) AS EventCount,
    SUM(CONVERT(bigint, SpeedKph)) AS TotalSpeedKph,
    CONVERT
    (
        decimal(10,2),
        AVG(CONVERT(decimal(10,4), BatteryVoltage))
    ) AS AverageBatteryVoltage,
    MAX(EventTime) AS LatestEventTime
FROM telemetry.TelemetryEvent
WHERE DeviceId = 10000
  AND EventTime >= '2024-12-01T00:00:00'
  AND EventTime <  '2025-01-01T00:00:00';
GO

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO