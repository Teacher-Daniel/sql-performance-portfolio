/*
    Experiment 02: Key Lookup and covering indexes
    Step 01: Capture the original baseline

    The query aggregates 500 events belonging to 20 devices.
    No index on DeviceId should exist at this point.
*/

USE [FleetTelemetryLab];
GO

SET NOCOUNT ON;

DECLARE @ExpectedInstance sysname = N'SQL2025LAB';

IF CONVERT(sysname, SERVERPROPERTY('InstanceName')) <> @ExpectedInstance
BEGIN
    THROW 55000,
        'Safety check failed: execute this script only on SQL2025LAB.',
        1;
END;

IF DB_NAME() <> N'FleetTelemetryLab'
BEGIN
    THROW 55001,
        'Safety check failed: the current database must be FleetTelemetryLab.',
        1;
END;

SET STATISTICS IO ON;
SET STATISTICS TIME ON;

PRINT 'Experiment 02 - Baseline without a DeviceId index';

SELECT
    COUNT_BIG(*) AS EventCount,
    SUM(CONVERT(bigint, SpeedKph)) AS TotalSpeedKph,
    CONVERT
    (
        decimal(10, 2),
        AVG(CONVERT(decimal(10, 4), BatteryVoltage))
    ) AS AverageBatteryVoltage,
    MAX(EventTime) AS LatestEventTime
FROM telemetry.TelemetryEvent
WHERE DeviceId BETWEEN 10000 AND 10019;

SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;
GO
