/*
Experiment 06 - Inspect join environment

Purpose:
Inspect the live schema, relationship, indexes, statistics, row counts,
and deterministic Device-to-TelemetryEvent distribution used to design
the join-strategy experiment.

This script does not intentionally modify permanent data, schema,
indexes, statistics, or database configuration.
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

DECLARE @DeviceObjectId int =
    OBJECT_ID(N'fleet.Device');

DECLARE @TelemetryEventObjectId int =
    OBJECT_ID(N'telemetry.TelemetryEvent');

IF EXISTS
(
    SELECT 1
    FROM sys.indexes AS i
    WHERE i.object_id = @TelemetryEventObjectId
      AND i.name =
          N'IX_TelemetryEvent_DeviceId_JoinExperiment'
)
BEGIN
    THROW 51004, 'The experimental join index already exists.', 1;
END;

/*
Result set 1:
Server and database environment.
*/
SELECT
    CONVERT(sysname, SERVERPROPERTY(N'ServerName'))
        AS ServerName,
    CONVERT(nvarchar(128), SERVERPROPERTY(N'ProductVersion'))
        AS ProductVersion,
    DB_NAME() AS DatabaseName,
    d.compatibility_level AS CompatibilityLevel
FROM sys.databases AS d
WHERE d.database_id = DB_ID();

/*
Result set 2:
Parallelism settings that can influence physical join selection.
*/
SELECT
    c.name AS ConfigurationName,
    c.value AS ConfiguredValue,
    c.value_in_use AS ValueInUse
FROM sys.configurations AS c
WHERE c.name IN
(
    N'cost threshold for parallelism',
    N'max degree of parallelism'
)
ORDER BY c.name;

/*
Result set 3:
Trusted foreign-key relationship used by the experiment.
*/
SELECT
    fk.name AS ForeignKeyName,
    SCHEMA_NAME(parent_table.schema_id)
        AS ParentSchema,
    parent_table.name AS ParentTable,
    parent_column.name AS ParentColumn,
    SCHEMA_NAME(referenced_table.schema_id)
        AS ReferencedSchema,
    referenced_table.name AS ReferencedTable,
    referenced_column.name AS ReferencedColumn,
    fk.is_disabled AS IsDisabled,
    fk.is_not_trusted AS IsNotTrusted
FROM sys.foreign_keys AS fk
INNER JOIN sys.foreign_key_columns AS fkc
    ON fkc.constraint_object_id = fk.object_id
INNER JOIN sys.tables AS parent_table
    ON parent_table.object_id = fk.parent_object_id
INNER JOIN sys.columns AS parent_column
    ON parent_column.object_id = fkc.parent_object_id
   AND parent_column.column_id = fkc.parent_column_id
INNER JOIN sys.tables AS referenced_table
    ON referenced_table.object_id =
       fk.referenced_object_id
INNER JOIN sys.columns AS referenced_column
    ON referenced_column.object_id =
       fkc.referenced_object_id
   AND referenced_column.column_id =
       fkc.referenced_column_id
WHERE fk.parent_object_id =
      @TelemetryEventObjectId
  AND fk.referenced_object_id =
      @DeviceObjectId;

/*
Result set 4:
Current indexes and their explicit key or included columns.
*/
SELECT
    SCHEMA_NAME(t.schema_id) AS SchemaName,
    t.name AS TableName,
    i.index_id AS IndexId,
    i.name AS IndexName,
    i.type_desc AS IndexType,
    i.is_unique AS IsUnique,
    i.is_disabled AS IsDisabled,
    c.name AS ColumnName,
    ic.key_ordinal AS KeyOrdinal,
    ic.is_included_column AS IsIncluded
FROM sys.tables AS t
INNER JOIN sys.indexes AS i
    ON i.object_id = t.object_id
LEFT JOIN sys.index_columns AS ic
    ON ic.object_id = i.object_id
   AND ic.index_id = i.index_id
   AND
   (
       ic.key_ordinal > 0
       OR ic.is_included_column = 1
   )
LEFT JOIN sys.columns AS c
    ON c.object_id = ic.object_id
   AND c.column_id = ic.column_id
WHERE t.object_id IN
(
    @DeviceObjectId,
    @TelemetryEventObjectId
)
  AND i.index_id > 0
  AND i.is_hypothetical = 0
ORDER BY
    SchemaName,
    TableName,
    i.index_id,
    ic.is_included_column,
    ic.key_ordinal,
    ic.index_column_id;

/*
Result set 5:
Statistics whose leading column is DeviceId.
*/
SELECT
    SCHEMA_NAME(t.schema_id) AS SchemaName,
    t.name AS TableName,
    s.stats_id AS StatsId,
    s.name AS StatisticsName,
    s.auto_created AS IsAutoCreated,
    s.user_created AS IsUserCreated,
    sp.last_updated AS LastUpdated,
    sp.rows AS TableRows,
    sp.rows_sampled AS RowsSampled,
    sp.steps AS HistogramSteps,
    sp.modification_counter AS ModificationCounter
FROM sys.tables AS t
INNER JOIN sys.stats AS s
    ON s.object_id = t.object_id
INNER JOIN sys.stats_columns AS sc
    ON sc.object_id = s.object_id
   AND sc.stats_id = s.stats_id
   AND sc.stats_column_id = 1
INNER JOIN sys.columns AS c
    ON c.object_id = sc.object_id
   AND c.column_id = sc.column_id
OUTER APPLY sys.dm_db_stats_properties
(
    s.object_id,
    s.stats_id
) AS sp
WHERE t.object_id IN
(
    @DeviceObjectId,
    @TelemetryEventObjectId
)
  AND c.name = N'DeviceId'
ORDER BY
    SchemaName,
    TableName,
    s.stats_id;

/*
Result set 6:
Current base-table row counts.
*/
SELECT
    SCHEMA_NAME(t.schema_id) AS SchemaName,
    t.name AS TableName,
    SUM(ps.row_count) AS TableRows
FROM sys.tables AS t
INNER JOIN sys.dm_db_partition_stats AS ps
    ON ps.object_id = t.object_id
   AND ps.index_id IN (0, 1)
WHERE t.object_id IN
(
    @DeviceObjectId,
    @TelemetryEventObjectId
)
GROUP BY
    t.schema_id,
    t.name
ORDER BY
    SchemaName,
    TableName;

/*
Result set 7:
Confirm uniform event allocation across every device.
*/
;WITH EventsPerDevice AS
(
    SELECT
        te.DeviceId,
        COUNT_BIG(*) AS EventCount
    FROM telemetry.TelemetryEvent AS te
    GROUP BY te.DeviceId
)
SELECT
    COUNT_BIG(*) AS DevicesRepresented,
    MIN(epd.DeviceId) AS MinimumDeviceId,
    MAX(epd.DeviceId) AS MaximumDeviceId,
    MIN(epd.EventCount) AS MinimumEventsPerDevice,
    MAX(epd.EventCount) AS MaximumEventsPerDevice,
    SUM(epd.EventCount) AS TotalEvents
FROM EventsPerDevice AS epd;

/*
Result set 8:
Confirm deterministic cumulative cardinalities for candidate cutoffs.
*/
SELECT
    SUM
    (
        CONVERT
        (
            bigint,
            CASE WHEN te.DeviceId <= 1
                THEN 1 ELSE 0 END
        )
    ) AS EventsForFirstDevice,
    SUM
    (
        CONVERT
        (
            bigint,
            CASE WHEN te.DeviceId <= 10
                THEN 1 ELSE 0 END
        )
    ) AS EventsForFirst10Devices,
    SUM
    (
        CONVERT
        (
            bigint,
            CASE WHEN te.DeviceId <= 100
                THEN 1 ELSE 0 END
        )
    ) AS EventsForFirst100Devices,
    SUM
    (
        CONVERT
        (
            bigint,
            CASE WHEN te.DeviceId <= 1000
                THEN 1 ELSE 0 END
        )
    ) AS EventsForFirst1000Devices,
    COUNT_BIG(*) AS EventsForAllDevices
FROM telemetry.TelemetryEvent AS te;
GO
