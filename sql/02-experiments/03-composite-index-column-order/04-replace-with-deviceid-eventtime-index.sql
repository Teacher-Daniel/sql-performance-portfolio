/*
Experiment 03 - Replace with equality-first composite index

Original key order:
(EventTime, DeviceId)

New key order:
(DeviceId, EventTime)

Both indexes include the same columns. Composite-key order is the only
intentional design difference.
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

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'telemetry.TelemetryEvent')
      AND name = N'IX_TelemetryEvent_EventTime_DeviceId'
      AND is_disabled = 0
)
BEGIN
    THROW 51003, 'The expected EventTime-leading index does not exist.', 1;
END;
GO

IF EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'telemetry.TelemetryEvent')
      AND name = N'IX_TelemetryEvent_DeviceId_EventTime'
)
BEGIN
    THROW 51004, 'The DeviceId-leading index already exists.', 1;
END;
GO

IF EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'telemetry.TelemetryEvent')
      AND index_id > 1
      AND name <> N'IX_TelemetryEvent_EventTime_DeviceId'
)
BEGIN
    THROW 51005, 'An unexpected nonclustered index exists.', 1;
END;
GO

DECLARE @IndexCreationStartedAt datetime2(7) = SYSDATETIME();

CREATE NONCLUSTERED INDEX IX_TelemetryEvent_DeviceId_EventTime
ON telemetry.TelemetryEvent
(
    DeviceId,
    EventTime
)
INCLUDE
(
    SpeedKph,
    BatteryVoltage
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

DROP INDEX IX_TelemetryEvent_EventTime_DeviceId
ON telemetry.TelemetryEvent;

SELECT
    expected.IndexName,
    CASE
        WHEN i.index_id IS NULL THEN N'REMOVED'
        ELSE N'PRESENT'
    END AS IndexStatus
FROM
(
    VALUES
        (1, N'IX_TelemetryEvent_EventTime_DeviceId'),
        (2, N'IX_TelemetryEvent_DeviceId_EventTime')
) AS expected(SortOrder, IndexName)
LEFT JOIN sys.indexes AS i
    ON i.object_id = OBJECT_ID(N'telemetry.TelemetryEvent')
   AND i.name = expected.IndexName
ORDER BY expected.SortOrder;

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
WHERE i.object_id = OBJECT_ID(N'telemetry.TelemetryEvent')
  AND i.name = N'IX_TelemetryEvent_DeviceId_EventTime'
ORDER BY
    ic.is_included_column,
    ic.key_ordinal,
    ic.index_column_id;

SELECT
    SUM(ps.row_count) AS IndexRowCount,
    CONVERT(decimal(12,2), SUM(ps.reserved_page_count) * 8.0 / 1024.0)
        AS ReservedSpaceMB,
    CONVERT(decimal(12,2), SUM(ps.used_page_count) * 8.0 / 1024.0)
        AS UsedSpaceMB
FROM sys.dm_db_partition_stats AS ps
INNER JOIN sys.indexes AS i
    ON i.object_id = ps.object_id
   AND i.index_id = ps.index_id
WHERE i.object_id = OBJECT_ID(N'telemetry.TelemetryEvent')
  AND i.name = N'IX_TelemetryEvent_DeviceId_EventTime';

SELECT
    @IndexCreationElapsedMilliseconds
        AS IndexCreationElapsedMilliseconds;
GO
