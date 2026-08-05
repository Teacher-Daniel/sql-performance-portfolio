/*
Experiment 04 - Compare common and rare literals

Both queries use:

- The same table.
- The same columns.
- The same date interval.
- The same available index.
- OPTION (RECOMPILE).

Only EventType frequency changes.
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
      AND name = N'IX_TelemetryEvent_EventType_EventTime'
      AND is_disabled = 0
)
BEGIN
    THROW 51000, 'The expected experimental index does not exist.', 1;
END;
GO

SET STATISTICS IO ON;
SET STATISTICS TIME ON;
GO

PRINT N'Experiment 04 - Common value with experimental index: EventType 1';

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

PRINT N'Experiment 04 - Rare value with experimental index: EventType 5';

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
