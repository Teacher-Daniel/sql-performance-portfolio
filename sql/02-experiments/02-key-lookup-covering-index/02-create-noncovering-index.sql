/*
    Experiment 02: Key Lookup and covering indexes
    Step 02: Create a deliberately noncovering index

    DeviceId supports the search predicate, but the columns required
    by the aggregations are intentionally omitted.
*/

USE [FleetTelemetryLab];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @ExpectedInstance sysname = N'SQL2025LAB';
DECLARE @StartedAt datetime2(3) = SYSDATETIME();

IF CONVERT(sysname, SERVERPROPERTY('InstanceName')) <> @ExpectedInstance
BEGIN
    THROW 55100,
        'Safety check failed: execute this script only on SQL2025LAB.',
        1;
END;

IF DB_NAME() <> N'FleetTelemetryLab'
BEGIN
    THROW 55101,
        'Safety check failed: the current database must be FleetTelemetryLab.',
        1;
END;

IF INDEXPROPERTY
(
    OBJECT_ID(N'telemetry.TelemetryEvent'),
    N'IX_TelemetryEvent_DeviceId',
    N'IndexID'
) IS NOT NULL
BEGIN
    THROW 55102,
        'IX_TelemetryEvent_DeviceId already exists.',
        1;
END;

CREATE NONCLUSTERED INDEX IX_TelemetryEvent_DeviceId
    ON telemetry.TelemetryEvent (DeviceId)
    WITH
    (
        SORT_IN_TEMPDB = ON,
        ONLINE = OFF,
        MAXDOP = 2
    );

SELECT
    I.name AS IndexName,
    I.type_desc AS IndexType,
    I.is_unique AS IsUnique,
    I.is_disabled AS IsDisabled,
    C.name AS ExplicitColumn,
    IC.key_ordinal AS KeyOrdinal,
    IC.is_included_column AS IsIncludedColumn
FROM sys.indexes AS I
INNER JOIN sys.index_columns AS IC
    ON IC.object_id = I.object_id
   AND IC.index_id = I.index_id
INNER JOIN sys.columns AS C
    ON C.object_id = IC.object_id
   AND C.column_id = IC.column_id
WHERE I.object_id = OBJECT_ID(N'telemetry.TelemetryEvent')
  AND I.name = N'IX_TelemetryEvent_DeviceId'
  AND
  (
      IC.key_ordinal > 0
      OR IC.is_included_column = 1
  )
ORDER BY
    IC.is_included_column,
    IC.key_ordinal,
    IC.index_column_id;

SELECT
    SUM(P.row_count) AS IndexRowCount,
    CONVERT
    (
        decimal(12, 2),
        SUM(P.reserved_page_count) * 8.0 / 1024.0
    ) AS ReservedSpaceMB,
    CONVERT
    (
        decimal(12, 2),
        SUM(P.used_page_count) * 8.0 / 1024.0
    ) AS UsedSpaceMB
FROM sys.dm_db_partition_stats AS P
WHERE P.object_id = OBJECT_ID(N'telemetry.TelemetryEvent')
  AND P.index_id = INDEXPROPERTY
  (
      OBJECT_ID(N'telemetry.TelemetryEvent'),
      N'IX_TelemetryEvent_DeviceId',
      N'IndexID'
  );

SELECT
    DATEDIFF
    (
        MILLISECOND,
        @StartedAt,
        SYSDATETIME()
    ) AS IndexCreationElapsedMilliseconds;
GO
