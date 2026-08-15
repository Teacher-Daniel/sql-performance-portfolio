/*
Experiment 06 - Capture index-supported join strategies

Purpose:
Repeat the selective and broad baseline queries after creating the
minimal nonclustered index on TelemetryEvent.DeviceId.

The statements intentionally match the baseline query shape. No join
hint is used, so each physical strategy remains an optimizer choice.

OPTION (RECOMPILE) allows each literal to be estimated and optimized
independently.
*/

USE FleetTelemetryLab;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
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

DECLARE @TelemetryEventObjectId int =
    OBJECT_ID(N'telemetry.TelemetryEvent');

DECLARE @ExperimentalIndexId int =
    INDEXPROPERTY
    (
        @TelemetryEventObjectId,
        N'IX_TelemetryEvent_DeviceId_JoinExperiment',
        N'IndexID'
    );

IF @ExperimentalIndexId IS NULL
BEGIN
    THROW 51004, 'The required experimental join index does not exist.', 1;
END;

IF EXISTS
(
    SELECT 1
    FROM sys.indexes AS i
    WHERE i.object_id = @TelemetryEventObjectId
      AND i.index_id = @ExperimentalIndexId
      AND
      (
          i.type <> 2
          OR i.is_disabled = 1
          OR i.is_hypothetical = 1
      )
)
BEGIN
    THROW 51005, 'The experimental join index is not usable.', 1;
END;

IF EXISTS
(
    SELECT 1
    FROM sys.indexes AS i
    WHERE i.object_id = @TelemetryEventObjectId
      AND i.index_id > 1
      AND i.index_id <> @ExperimentalIndexId
      AND i.is_hypothetical = 0
)
BEGIN
    THROW 51006, 'Validation failed: an unexpected nonclustered index exists.', 1;
END;

IF NOT EXISTS
(
    SELECT 1
    FROM sys.index_columns AS ic
    INNER JOIN sys.columns AS c
        ON c.object_id = ic.object_id
       AND c.column_id = ic.column_id
    WHERE ic.object_id = @TelemetryEventObjectId
      AND ic.index_id = @ExperimentalIndexId
      AND c.name = N'DeviceId'
      AND ic.key_ordinal = 1
      AND ic.is_included_column = 0
)
OR EXISTS
(
    SELECT 1
    FROM sys.index_columns AS ic
    INNER JOIN sys.columns AS c
        ON c.object_id = ic.object_id
       AND c.column_id = ic.column_id
    WHERE ic.object_id = @TelemetryEventObjectId
      AND ic.index_id = @ExperimentalIndexId
      AND
      (
          ic.key_ordinal > 0
          OR ic.is_included_column = 1
      )
      AND NOT
      (
          c.name = N'DeviceId'
          AND ic.key_ordinal = 1
          AND ic.is_included_column = 0
      )
)
BEGIN
    THROW 51007, 'The experimental join index has an unexpected definition.', 1;
END;

DECLARE @ExperimentalIndexRows bigint;

SELECT
    @ExperimentalIndexRows = SUM(ps.row_count)
FROM sys.dm_db_partition_stats AS ps
WHERE ps.object_id = @TelemetryEventObjectId
  AND ps.index_id = @ExperimentalIndexId;

IF ISNULL(@ExperimentalIndexRows, 0) <> 1000000
BEGIN
    THROW 51008, 'The experimental join index must contain 1,000,000 rows.', 1;
END;
GO

SET STATISTICS IO ON;
SET STATISTICS TIME ON;
GO

PRINT N'Experiment 06 - Selective join with the supporting index: 1 device';

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

PRINT N'Experiment 06 - Broad join with the supporting index: 40,000 devices';

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
