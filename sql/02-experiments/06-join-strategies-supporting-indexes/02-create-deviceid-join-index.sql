/*
Experiment 06 - Create the DeviceId join-supporting index

Purpose:
Create a minimal nonclustered index on TelemetryEvent.DeviceId.

The index has no INCLUDE columns. Its only experimental purpose is to
provide a seekable and ordered access path for the join key, without
repeating the covering-index comparison from Experiment 02.

This script modifies the database by creating one experimental index.
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

IF OBJECT_ID(N'telemetry.TelemetryEvent', N'U') IS NULL
BEGIN
    THROW 51002, 'The table telemetry.TelemetryEvent does not exist.', 1;
END;
GO

IF EXISTS
(
    SELECT 1
    FROM sys.indexes AS i
    WHERE i.object_id =
          OBJECT_ID(N'telemetry.TelemetryEvent')
      AND i.name =
          N'IX_TelemetryEvent_DeviceId_JoinExperiment'
)
BEGIN
    THROW 51003, 'The experimental join index already exists.', 1;
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
    THROW 51004, 'Creation aborted: an unexpected nonclustered index exists.', 1;
END;
GO

DECLARE @StartedAt datetime2(7) = SYSDATETIME();

CREATE NONCLUSTERED INDEX
    IX_TelemetryEvent_DeviceId_JoinExperiment
ON telemetry.TelemetryEvent
(
    DeviceId
)
WITH
(
    SORT_IN_TEMPDB = ON,
    ONLINE = OFF,
    MAXDOP = 2
);

DECLARE @IndexCreationElapsedMilliseconds bigint =
    DATEDIFF_BIG
    (
        MILLISECOND,
        @StartedAt,
        SYSDATETIME()
    );

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
    THROW 51005, 'Index creation failed validation.', 1;
END;

/*
Result set 1:
Explicit index key definition.
*/
SELECT
    i.name AS IndexName,
    i.type_desc AS IndexType,
    i.is_unique AS IsUnique,
    i.is_disabled AS IsDisabled,
    c.name AS ExplicitColumn,
    ic.key_ordinal AS KeyOrdinal,
    ic.is_included_column AS IsIncludedColumn
FROM sys.indexes AS i
INNER JOIN sys.index_columns AS ic
    ON ic.object_id = i.object_id
   AND ic.index_id = i.index_id
INNER JOIN sys.columns AS c
    ON c.object_id = ic.object_id
   AND c.column_id = ic.column_id
WHERE i.object_id = @TelemetryEventObjectId
  AND i.index_id = @ExperimentalIndexId
  AND
  (
      ic.key_ordinal > 0
      OR ic.is_included_column = 1
  )
ORDER BY
    ic.is_included_column,
    ic.key_ordinal,
    ic.index_column_id;

/*
Result set 2:
Index-associated statistics created during the build.
*/
SELECT
    s.name AS StatisticsName,
    sp.last_updated AS LastUpdated,
    sp.rows AS TableRows,
    sp.rows_sampled AS RowsSampled,
    sp.steps AS HistogramSteps,
    sp.modification_counter AS ModificationCounter
FROM sys.stats AS s
OUTER APPLY sys.dm_db_stats_properties
(
    s.object_id,
    s.stats_id
) AS sp
WHERE s.object_id = @TelemetryEventObjectId
  AND s.stats_id = @ExperimentalIndexId;

/*
Result set 3:
Row count and allocated size.
*/
SELECT
    SUM(ps.row_count) AS IndexRowCount,
    CONVERT
    (
        decimal(12,2),
        SUM(ps.reserved_page_count) * 8.0 / 1024.0
    ) AS ReservedSpaceMB,
    CONVERT
    (
        decimal(12,2),
        SUM(ps.used_page_count) * 8.0 / 1024.0
    ) AS UsedSpaceMB
FROM sys.dm_db_partition_stats AS ps
WHERE ps.object_id = @TelemetryEventObjectId
  AND ps.index_id = @ExperimentalIndexId;

/*
Result set 4:
Measured build duration.
*/
SELECT
    @IndexCreationElapsedMilliseconds
        AS IndexCreationElapsedMilliseconds;
GO
