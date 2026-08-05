/*
Experiment 04 - No-index cardinality baseline

Purpose:
Capture common-value and rare-value executions before creating the
experimental noncovering index.

OPTION (RECOMPILE) ensures that each literal is estimated independently
and prevents cached-plan reuse from becoming an experimental variable.
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

PRINT N'Experiment 04 - Common value baseline: EventType 1';

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
WHERE EventType = 1
  AND EventTime >= '2024-12-06T00:00:00'
  AND EventTime <  '2024-12-07T00:00:00'
OPTION (RECOMPILE);
GO

PRINT N'Experiment 04 - Rare value baseline: EventType 5';

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
WHERE EventType = 5
  AND EventTime >= '2024-12-06T00:00:00'
  AND EventTime <  '2024-12-07T00:00:00'
OPTION (RECOMPILE);
GO

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO
