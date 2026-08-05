/*
Experiment 03 - Measure range-first composite index

Expected index:
(EventTime, DeviceId)
INCLUDE (SpeedKph, BatteryVoltage)

The query is identical to the baseline query.
*/

USE FleetTelemetryLab;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'telemetry.TelemetryEvent')
      AND name = N'IX_TelemetryEvent_EventTime_DeviceId'
      AND is_disabled = 0
)
BEGIN
    THROW 51000, 'The expected EventTime-leading index does not exist.', 1;
END;
GO

SET STATISTICS IO ON;
SET STATISTICS TIME ON;
GO

PRINT N'Experiment 03 - Range-first index: EventTime, DeviceId';

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
