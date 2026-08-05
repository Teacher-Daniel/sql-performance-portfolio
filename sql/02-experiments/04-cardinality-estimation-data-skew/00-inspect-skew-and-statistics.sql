/*
Experiment 04 - Inspect data skew and existing statistics

Purpose:
- Verify the baseline nonclustered-index state.
- Inspect the EventType distribution.
- Determine whether statistics already exist for EventType.
- Display the histogram if an applicable statistic exists.

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

DECLARE @ObjectId int =
    OBJECT_ID(N'telemetry.TelemetryEvent');

/*
Result set 1:
No experimental nonclustered indexes should exist.
An empty result is expected.
*/
SELECT
    i.name AS IndexName,
    i.type_desc AS IndexType,
    i.is_unique AS IsUnique,
    i.is_disabled AS IsDisabled
FROM sys.indexes AS i
WHERE i.object_id = @ObjectId
  AND i.index_id > 1
ORDER BY i.name;

/*
Result set 2:
Existing statistics containing EventType.
This result may be empty.
*/
SELECT
    s.stats_id AS StatsId,
    s.name AS StatisticsName,
    sc.stats_column_id AS StatisticsColumnOrder,
    s.auto_created AS IsAutoCreated,
    s.user_created AS IsUserCreated,
    s.no_recompute AS NoRecompute,
    s.has_filter AS HasFilter,
    sp.last_updated AS LastUpdated,
    sp.rows AS TableRows,
    sp.rows_sampled AS RowsSampled,
    sp.steps AS HistogramSteps,
    c.name AS ColumnName
FROM sys.stats AS s
INNER JOIN sys.stats_columns AS sc
    ON sc.object_id = s.object_id
   AND sc.stats_id = s.stats_id
INNER JOIN sys.columns AS c
    ON c.object_id = sc.object_id
   AND c.column_id = sc.column_id
OUTER APPLY sys.dm_db_stats_properties
(
    s.object_id,
    s.stats_id
) AS sp
WHERE s.object_id = @ObjectId
  AND c.name = N'EventType'
ORDER BY
    s.stats_id,
    sc.stats_column_id;

/*
Result set 3:
Actual EventType distribution.
*/
SELECT
    te.EventType,
    COUNT_BIG(*) AS EventCount,
    CONVERT
    (
        decimal(9,4),
        COUNT_BIG(*) * 100.0
        / SUM(COUNT_BIG(*)) OVER ()
    ) AS PercentageOfTable,
    MIN(te.TelemetryEventId) AS MinimumTelemetryEventId,
    MAX(te.TelemetryEventId) AS MaximumTelemetryEventId
FROM telemetry.TelemetryEvent AS te
GROUP BY te.EventType
ORDER BY te.EventType;

/*
Result set 4:
Histogram for a statistic whose leading column is EventType,
if one already exists.
*/
DECLARE @EventTypeStatsId int;
DECLARE @EventTypeStatsName sysname;

SELECT TOP (1)
    @EventTypeStatsId = s.stats_id,
    @EventTypeStatsName = s.name
FROM sys.stats AS s
INNER JOIN sys.stats_columns AS sc
    ON sc.object_id = s.object_id
   AND sc.stats_id = s.stats_id
INNER JOIN sys.columns AS c
    ON c.object_id = sc.object_id
   AND c.column_id = sc.column_id
WHERE s.object_id = @ObjectId
  AND sc.stats_column_id = 1
  AND c.name = N'EventType'
ORDER BY
    s.user_created DESC,
    s.auto_created DESC,
    s.stats_id;

IF @EventTypeStatsId IS NULL
BEGIN
    SELECT
        N'NONE' AS StatisticsName,
        N'No leading-column EventType statistic exists.'
            AS HistogramStatus;
END;
ELSE
BEGIN
    SELECT
        @EventTypeStatsName AS StatisticsName,
        @EventTypeStatsId AS StatsId;

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
        @EventTypeStatsId
    ) AS hist
    ORDER BY hist.step_number;
END;
GO
