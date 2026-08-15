/*
Experiment 06 - No-supporting-index join baseline

Purpose:
Capture selective and broad executions of the Device-to-TelemetryEvent
join before creating an index on TelemetryEvent.DeviceId.

The two statements use the same join and aggregate shape at different
cardinalities. OPTION (RECOMPILE) allows each literal to be estimated
and optimized independently.

VehicleIdChecksum deliberately references fleet.Device so that the
trusted foreign key cannot make the referenced table removable from
the execution plan.

This script does not modify permanent data, schema, indexes,
statistics, or database configuration.
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

IF OBJECT_ID(N'fleet.Device', N'U') IS NULL
BEGIN
    THROW 51002, 'The table fleet.Device does not exist.', 1;
END;

IF OBJECT_ID(N'telemetry.TelemetryEvent', N'U') IS NULL
BEGIN
    THROW 51003, 'The table telemetry.TelemetryEvent does not exist.', 1;
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.foreign_keys AS fk
    WHERE fk.parent_object_id =
          OBJECT_ID(N'telemetry.TelemetryEvent')
      AND fk.referenced_object_id =
          OBJECT_ID(N'fleet.Device')
      AND fk.is_disabled = 0
      AND fk.is_not_trusted = 0
)
BEGIN
    THROW 51004, 'Baseline invalid: the required trusted foreign key is unavailable.', 1;
END;
GO

IF EXISTS
(
    SELECT 1
    FROM sys.indexes AS i
    WHERE i.object_id =
          OBJECT_ID(N'telemetry.TelemetryEvent')
      AND i.index_id > 1
      AND i.is_hypothetical = 0
)
BEGIN
    THROW 51005, 'Baseline invalid: an unexpected nonclustered index exists.', 1;
END;
GO

DECLARE @DeviceRows bigint;
DECLARE @TelemetryEventRows bigint;

SELECT
    @DeviceRows = SUM(ps.row_count)
FROM sys.dm_db_partition_stats AS ps
WHERE ps.object_id = OBJECT_ID(N'fleet.Device')
  AND ps.index_id IN (0, 1);

SELECT
    @TelemetryEventRows = SUM(ps.row_count)
FROM sys.dm_db_partition_stats AS ps
WHERE ps.object_id =
      OBJECT_ID(N'telemetry.TelemetryEvent')
  AND ps.index_id IN (0, 1);

IF ISNULL(@DeviceRows, 0) <> 40000
BEGIN
    THROW 51006, 'Baseline invalid: fleet.Device must contain 40,000 rows.', 1;
END;

IF ISNULL(@TelemetryEventRows, 0) <> 1000000
BEGIN
    THROW 51007, 'Baseline invalid: telemetry.TelemetryEvent must contain 1,000,000 rows.', 1;
END;
GO

SET STATISTICS IO ON;
SET STATISTICS TIME ON;
GO

PRINT N'Experiment 06 - Selective join without a supporting index: 1 device';

SELECT
    COUNT_BIG(*) AS JoinedEventCount,
    SUM(CONVERT(bigint, d.VehicleId))
        AS VehicleIdChecksum
FROM fleet.Device AS d
INNER JOIN telemetry.TelemetryEvent AS te
    ON te.DeviceId = d.DeviceId
WHERE d.DeviceId <= 1
OPTION (RECOMPILE);
GO

PRINT N'Experiment 06 - Broad join without a supporting index: 40,000 devices';

SELECT
    COUNT_BIG(*) AS JoinedEventCount,
    SUM(CONVERT(bigint, d.VehicleId))
        AS VehicleIdChecksum
FROM fleet.Device AS d
INNER JOIN telemetry.TelemetryEvent AS te
    ON te.DeviceId = d.DeviceId
WHERE d.DeviceId <= 40000
OPTION (RECOMPILE);
GO

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO
