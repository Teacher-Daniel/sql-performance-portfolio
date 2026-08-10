/*
Experiment 05 - Validate equality-only plan separation

Purpose:
Compile the common and rare equality values independently and
confirm that they produce different cost-based execution plans.

OPTION (RECOMPILE) prevents cached-plan reuse in this validation.

Expected behavior:
- SensitivityKey 1 uses a Clustered Index Scan.
- SensitivityKey 5 uses an Index Seek and Key Lookup.
*/

USE FleetTelemetryLab;

SET NOCOUNT ON;
SET XACT_ABORT ON;
SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;

IF COALESCE
(
    CONVERT(sysname, SERVERPROPERTY(N'InstanceName')),
    N'MSSQLSERVER'
) <> N'SQL2025LAB'
BEGIN
    THROW 51000, 'Safety check failed: execute this script on SQL2025LAB.', 1;
END;

IF DB_NAME() <> N'FleetTelemetryLab'
BEGIN
    THROW 51001, 'Safety check failed: the current database must be FleetTelemetryLab.', 1;
END;

IF OBJECT_ID
(
    N'telemetry.PspEqualityEvent',
    N'U'
) IS NULL
BEGIN
    THROW 51002, 'The equality-only fixture table does not exist.', 1;
END;

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes AS i
    WHERE i.object_id =
          OBJECT_ID(N'telemetry.PspEqualityEvent')
      AND i.name =
          N'IX_PspEqualityEvent_SensitivityKey'
      AND i.is_disabled = 0
)
BEGIN
    THROW 51003, 'The equality-key index does not exist or is disabled.', 1;
END;

/*
Initialization pair:
Compile both literal forms and warm their relevant pages.
*/

PRINT N'Initialization 1: common equality value.';

SELECT
    COUNT_BIG(*) AS EventCount,
    SUM(CONVERT(bigint, SpeedKph)) AS TotalSpeedKph,
    CONVERT
    (
        decimal(10,2),
        AVG(CONVERT(decimal(10,4), BatteryVoltage))
    ) AS AverageBatteryVoltage,
    MAX(EventTime) AS LatestEventTime
FROM telemetry.PspEqualityEvent
WHERE SensitivityKey = 1
OPTION (RECOMPILE);

PRINT N'Initialization 2: rare equality value.';

SELECT
    COUNT_BIG(*) AS EventCount,
    SUM(CONVERT(bigint, SpeedKph)) AS TotalSpeedKph,
    CONVERT
    (
        decimal(10,2),
        AVG(CONVERT(decimal(10,4), BatteryVoltage))
    ) AS AverageBatteryVoltage,
    MAX(EventTime) AS LatestEventTime
FROM telemetry.PspEqualityEvent
WHERE SensitivityKey = 5
OPTION (RECOMPILE);

/*
Measured pair:
Retain these warm-cache measurements.
*/

SET STATISTICS IO ON;
SET STATISTICS TIME ON;

PRINT N'Measurement 1: independently optimized common value.';

SELECT
    COUNT_BIG(*) AS EventCount,
    SUM(CONVERT(bigint, SpeedKph)) AS TotalSpeedKph,
    CONVERT
    (
        decimal(10,2),
        AVG(CONVERT(decimal(10,4), BatteryVoltage))
    ) AS AverageBatteryVoltage,
    MAX(EventTime) AS LatestEventTime
FROM telemetry.PspEqualityEvent
WHERE SensitivityKey = 1
OPTION (RECOMPILE);

PRINT N'Measurement 2: independently optimized rare value.';

SELECT
    COUNT_BIG(*) AS EventCount,
    SUM(CONVERT(bigint, SpeedKph)) AS TotalSpeedKph,
    CONVERT
    (
        decimal(10,2),
        AVG(CONVERT(decimal(10,4), BatteryVoltage))
    ) AS AverageBatteryVoltage,
    MAX(EventTime) AS LatestEventTime
FROM telemetry.PspEqualityEvent
WHERE SensitivityKey = 5
OPTION (RECOMPILE);

SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;
