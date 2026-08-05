/*
Experiment 04 - Create noncovering skew index

Purpose:
Provide a selective access path for EventType and EventTime while
intentionally omitting SpeedKph and BatteryVoltage.

The optimizer must choose between:

- A seek followed by clustered Key Lookups.
- A clustered-index scan.

Cardinality estimates should influence that choice.
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

IF OBJECT_ID(N'telemetry.TelemetryEvent', N'U') IS NULL
BEGIN
    THROW 51002, 'The table telemetry.TelemetryEvent does not exist.', 1;
END;
GO

IF EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'telemetry.TelemetryEvent')
      AND index_id > 1
)
BEGIN
    THROW 51003, 'An unexpected nonclustered index already exists.', 1;
END;
GO

DECLARE @IndexCreationStartedAt datetime2(7) = SYSDATETIME();

CREATE NONCLUSTERED INDEX IX_TelemetryEvent_EventType_EventTime
ON telemetry.TelemetryEvent
(
    EventType,
    EventTime
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
        @IndexCreationStartedAt,
        SYSDATETIME()
    );

DECLARE @ObjectId int =
    OBJECT_ID(N'telemetry.TelemetryEvent');

DECLARE @IndexId int =
(
    SELECT i.index_id
    FROM sys.indexes AS i
    WHERE i.object_id = @ObjectId
      AND i.name = N'IX_TelemetryEvent_EventType_EventTime'
);

SELECT
    i.name AS IndexName,
    i.type_desc AS IndexType,
    i.is_unique AS IsUnique,
    i.is_disabled AS IsDisabled,
    c.name AS ExplicitColumn,
    ic.key_ordinal AS KeyOrdinal,
    ic.is_included_column AS IncludedColumn
FROM sys.indexes AS i
INNER JOIN sys.index_columns AS ic
    ON ic.object_id = i.object_id
   AND ic.index_id = i.index_id
INNER JOIN sys.columns AS c
    ON c.object_id = ic.object_id
   AND c.column_id = ic.column_id
WHERE i.object_id = @ObjectId
  AND i.index_id = @IndexId
ORDER BY
    ic.key_ordinal,
    ic.index_column_id;

SELECT
    SUM(ps.row_count) AS IndexRowCount,
    CONVERT(decimal(12,2), SUM(ps.reserved_page_count) * 8.0 / 1024.0)
        AS ReservedSpaceMB,
    CONVERT(decimal(12,2), SUM(ps.used_page_count) * 8.0 / 1024.0)
        AS UsedSpaceMB
FROM sys.dm_db_partition_stats AS ps
WHERE ps.object_id = @ObjectId
  AND ps.index_id = @IndexId;

SELECT
    s.name AS StatisticsName,
    s.auto_created AS IsAutoCreated,
    s.user_created AS IsUserCreated,
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
WHERE s.object_id = @ObjectId
  AND s.stats_id = @IndexId;

SELECT
    hist.step_number AS StepNumber,
    hist.range_high_key AS RangeHighKey,
    hist.equal_rows AS EqualRows,
    hist.range_rows AS RangeRows,
    hist.distinct_range_rows AS DistinctRangeRows,
    hist.average_range_rows AS AverageRangeRows
FROM sys.dm_db_stats_histogram
(
    @ObjectId,
    @IndexId
) AS hist
ORDER BY hist.step_number;

SELECT
    @IndexCreationElapsedMilliseconds
        AS IndexCreationElapsedMilliseconds;
GO
