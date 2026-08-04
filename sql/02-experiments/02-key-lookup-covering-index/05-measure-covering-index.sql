/*
Experiment 02 - Covering index measurement

This is the same query used for the clustered-scan baseline and the
noncovering-index measurement. Only the index design has changed.
*/

USE FleetTelemetryLab;
GO

SET NOCOUNT ON;
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
GO

PRINT N'Experiment 02 - Covering index without Key Lookup';

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
WHERE DeviceId BETWEEN 10000 AND 10019;
GO

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO
