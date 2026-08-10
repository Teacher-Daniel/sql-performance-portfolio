/*
Experiment 05 - Validate extreme-skew plan separation

Purpose:
Verify that independently optimized equality predicates produce
different physical access strategies after escalating the experimental
distribution to 999,999 common rows and one rare row.

The common value should favor a clustered-index scan.
The rare value should favor a nonclustered seek with one Key Lookup.

OPTION (RECOMPILE) prevents cached-plan reuse and PSP from affecting
this validation stage.

This script does not modify permanent data.
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
    THROW 51000,
        'Safety check failed: execute this script on SQL2025LAB.',
        1;
END;
GO

IF DB_NAME() <> N'FleetTelemetryLab'
BEGIN
    THROW 51001,
        'Safety check failed: the current database must be FleetTelemetryLab.',
        1;
END;
GO

IF OBJECT_ID
(
    N'telemetry.PspHighSkewEvent',
    N'U'
) IS NULL
BEGIN
    THROW 51002,
        'The table telemetry.PspHighSkewEvent does not exist.',
        1;
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes AS i
    WHERE i.object_id =
        OBJECT_ID(N'telemetry.PspHighSkewEvent')
      AND i.name = N'IX_PspHighSkewEvent_SkewKey'
      AND i.is_disabled = 0
)
BEGIN
    THROW 51003,
        'The required nonclustered index does not exist or is disabled.',
        1;
END;
GO

DECLARE
    @TotalRows bigint,
    @CommonRows bigint,
    @RareRows bigint;

SELECT
    @TotalRows = COUNT_BIG(*),
    @CommonRows = SUM
    (
        CONVERT
        (
            bigint,
            CASE
                WHEN phe.SkewKey = 1
                THEN 1
                ELSE 0
            END
        )
    ),
    @RareRows = SUM
    (
        CONVERT
        (
            bigint,
            CASE
                WHEN phe.SkewKey = 5
                THEN 1
                ELSE 0
            END
        )
    )
FROM telemetry.PspHighSkewEvent AS phe;

IF @TotalRows <> 1000000
   OR @CommonRows <> 999999
   OR @RareRows <> 1
BEGIN
    THROW 51004,
        'The extreme-skew fixture does not contain the expected distribution.',
        1;
END;
GO

/*
Warm both access paths before retaining the measured executions.

These initialization statements use the same query shape and literals
as the measured statements. Their plans will also appear in the saved
plan file.
*/

RAISERROR
(
    'Initialization 1: independently optimize the common equality value.',
    10,
    1
) WITH NOWAIT;

SELECT
    COUNT_BIG(*) AS EventCount,
    SUM(CONVERT(bigint, SpeedKph)) AS TotalSpeedKph,
    CONVERT
    (
        decimal(10,2),
        AVG(CONVERT(decimal(10,4), BatteryVoltage))
    ) AS AverageBatteryVoltage,
    MAX(EventTime) AS LatestEventTime
FROM telemetry.PspHighSkewEvent
WHERE SkewKey = 1
OPTION (RECOMPILE);

RAISERROR
(
    'Initialization 2: independently optimize the rare equality value.',
    10,
    1
) WITH NOWAIT;

SELECT
    COUNT_BIG(*) AS EventCount,
    SUM(CONVERT(bigint, SpeedKph)) AS TotalSpeedKph,
    CONVERT
    (
        decimal(10,2),
        AVG(CONVERT(decimal(10,4), BatteryVoltage))
    ) AS AverageBatteryVoltage,
    MAX(EventTime) AS LatestEventTime
FROM telemetry.PspHighSkewEvent
WHERE SkewKey = 5
OPTION (RECOMPILE);
GO

SET STATISTICS IO ON;
SET STATISTICS TIME ON;
GO

RAISERROR
(
    'Measurement 1: independently optimized common equality value.',
    10,
    1
) WITH NOWAIT;

SELECT
    COUNT_BIG(*) AS EventCount,
    SUM(CONVERT(bigint, SpeedKph)) AS TotalSpeedKph,
    CONVERT
    (
        decimal(10,2),
        AVG(CONVERT(decimal(10,4), BatteryVoltage))
    ) AS AverageBatteryVoltage,
    MAX(EventTime) AS LatestEventTime
FROM telemetry.PspHighSkewEvent
WHERE SkewKey = 1
OPTION (RECOMPILE);

RAISERROR
(
    'Measurement 2: independently optimized rare equality value.',
    10,
    1
) WITH NOWAIT;

SELECT
    COUNT_BIG(*) AS EventCount,
    SUM(CONVERT(bigint, SpeedKph)) AS TotalSpeedKph,
    CONVERT
    (
        decimal(10,2),
        AVG(CONVERT(decimal(10,4), BatteryVoltage))
    ) AS AverageBatteryVoltage,
    MAX(EventTime) AS LatestEventTime
FROM telemetry.PspHighSkewEvent
WHERE SkewKey = 5
OPTION (RECOMPILE);
GO

SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;
GO
