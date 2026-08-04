/*
    Experiment 02: Key Lookup and covering indexes
    Step 03: Measure the noncovering-index plan

    The DeviceId index supports the predicate, but SQL Server must
    retrieve EventTime, SpeedKph, and BatteryVoltage from the
    clustered index for every qualifying row.
*/

USE [FleetTelemetryLab];
GO

SET NOCOUNT ON;

DECLARE @ExpectedInstance sysname = N'SQL2025LAB';

IF CONVERT(sysname, SERVERPROPERTY('InstanceName')) <> @ExpectedInstance
BEGIN
    THROW 55200,
        'Safety check failed: execute this script only on SQL2025LAB.',
        1;
END;

IF DB_NAME() <> N'FleetTelemetryLab'
BEGIN
    THROW 55201,
        'Safety check failed: the current database must be FleetTelemetryLab.',
        1;
END;

IF INDEXPROPERTY
(
    OBJECT_ID(N'telemetry.TelemetryEvent'),
    N'IX_TelemetryEvent_DeviceId',
    N'IndexID'
) IS NULL
BEGIN
    THROW 55202,
        'The experimental DeviceId index does not exist.',
        1;
END;

SET STATISTICS IO ON;
SET STATISTICS TIME ON;

PRINT 'Experiment 02 - Noncovering index with Key Lookup';

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
