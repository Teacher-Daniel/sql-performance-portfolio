/*
Experiment 05 - Create PSP test objects

Purpose:
Create the noncovering index and two stored procedures required
to compare classic parameter sniffing with PSP optimization.

All preflight checks and permanent changes execute in one batch.
If an error occurs after the transaction begins, all changes made
by this script are rolled back.
*/

USE FleetTelemetryLab;

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @IndexCreationStartedAt datetime2(7);
DECLARE @IndexCreationMilliseconds bigint;

BEGIN TRY
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

    IF OBJECT_ID(N'telemetry.TelemetryEvent', N'U') IS NULL
    BEGIN
        THROW 51002, 'The table telemetry.TelemetryEvent does not exist.', 1;
    END;

    IF
    (
        SELECT d.compatibility_level
        FROM sys.databases AS d
        WHERE d.database_id = DB_ID()
    ) < 160
    BEGIN
        THROW 51003, 'PSP requires database compatibility level 160 or later.', 1;
    END;

    IF NOT EXISTS
    (
        SELECT 1
        FROM sys.database_scoped_configurations AS dsc
        WHERE dsc.name =
              N'PARAMETER_SENSITIVE_PLAN_OPTIMIZATION'
          AND CONVERT(nvarchar(60), dsc.value)
              IN (N'1', N'ON')
    )
    BEGIN
        THROW 51004, 'PARAMETER_SENSITIVE_PLAN_OPTIMIZATION must be enabled.', 1;
    END;

    IF NOT EXISTS
    (
        SELECT 1
        FROM sys.database_scoped_configurations AS dsc
        WHERE dsc.name = N'PARAMETER_SNIFFING'
          AND CONVERT(nvarchar(60), dsc.value)
              IN (N'1', N'ON')
    )
    BEGIN
        THROW 51005, 'PARAMETER_SNIFFING must be enabled.', 1;
    END;

    IF NOT EXISTS
    (
        SELECT 1
        FROM sys.database_query_store_options AS qso
        WHERE qso.actual_state_desc = N'READ_WRITE'
    )
    BEGIN
        THROW 51006, 'Query Store must be in READ_WRITE state.', 1;
    END;

    IF EXISTS
    (
        SELECT 1
        FROM sys.indexes AS i
        WHERE i.object_id =
              OBJECT_ID(N'telemetry.TelemetryEvent')
          AND i.index_id > 1
    )
    BEGIN
        THROW 51007, 'An unexpected nonclustered index already exists.', 1;
    END;

    IF OBJECT_ID
    (
        N'telemetry.usp_EventTypeSummary_NoPsp',
        N'P'
    ) IS NOT NULL
    OR OBJECT_ID
    (
        N'telemetry.usp_EventTypeSummary_Psp',
        N'P'
    ) IS NOT NULL
    BEGIN
        THROW 51008, 'One or more experiment procedures already exist.', 1;
    END;

    BEGIN TRANSACTION;

    SET @IndexCreationStartedAt = SYSDATETIME();

    CREATE NONCLUSTERED INDEX
        IX_TelemetryEvent_EventType_EventTime
    ON telemetry.TelemetryEvent
    (
        EventType,
        EventTime
    );

    SET @IndexCreationMilliseconds =
        DATEDIFF_BIG
        (
            millisecond,
            @IndexCreationStartedAt,
            SYSDATETIME()
        );

    /*
    Dynamic batches allow CREATE PROCEDURE to participate in the
    same transaction without introducing GO batch separators.
    */

    EXEC sys.sp_executesql N'
CREATE PROCEDURE telemetry.usp_EventTypeSummary_NoPsp
    @EventType tinyint
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        COUNT_BIG(*) AS EventCount,
        SUM(CONVERT(bigint, SpeedKph)) AS TotalSpeedKph,
        CONVERT
        (
            decimal(10,2),
            AVG(CONVERT(decimal(10,4), BatteryVoltage))
        ) AS AverageBatteryVoltage,
        MAX(EventTime) AS LatestEventTime
    FROM telemetry.TelemetryEvent
    WHERE EventType = @EventType
      AND EventTime >= ''2024-12-06T00:00:00''
      AND EventTime <  ''2024-12-07T00:00:00''
    OPTION
    (
        USE HINT(''DISABLE_PARAMETER_SENSITIVE_PLAN'')
    );
END;';

    EXEC sys.sp_executesql N'
CREATE PROCEDURE telemetry.usp_EventTypeSummary_Psp
    @EventType tinyint
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        COUNT_BIG(*) AS EventCount,
        SUM(CONVERT(bigint, SpeedKph)) AS TotalSpeedKph,
        CONVERT
        (
            decimal(10,2),
            AVG(CONVERT(decimal(10,4), BatteryVoltage))
        ) AS AverageBatteryVoltage,
        MAX(EventTime) AS LatestEventTime
    FROM telemetry.TelemetryEvent
    WHERE EventType = @EventType
      AND EventTime >= ''2024-12-06T00:00:00''
      AND EventTime <  ''2024-12-07T00:00:00'';
END;';

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
    BEGIN
        ROLLBACK TRANSACTION;
    END;

    THROW;
END CATCH;

SELECT
    @IndexCreationMilliseconds AS IndexCreationMilliseconds;

DECLARE @ObjectId int =
    OBJECT_ID(N'telemetry.TelemetryEvent');

/*
Result set 1:
Index characteristics.
*/

SELECT
    i.name AS IndexName,
    i.index_id AS IndexId,
    i.type_desc AS IndexType,
    SUM(dps.row_count) AS IndexRows,
    CONVERT
    (
        decimal(10,2),
        SUM(dps.reserved_page_count) * 8.0 / 1024.0
    ) AS ReservedMB,
    CONVERT
    (
        decimal(10,2),
        SUM(dps.used_page_count) * 8.0 / 1024.0
    ) AS UsedMB
FROM sys.indexes AS i
INNER JOIN sys.dm_db_partition_stats AS dps
    ON dps.object_id = i.object_id
   AND dps.index_id = i.index_id
WHERE i.object_id = @ObjectId
  AND i.name =
      N'IX_TelemetryEvent_EventType_EventTime'
GROUP BY
    i.name,
    i.index_id,
    i.type_desc;

/*
Result set 2:
Full-scan statistics created with the index.
*/

SELECT
    s.stats_id AS StatsId,
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
  AND s.name =
      N'IX_TelemetryEvent_EventType_EventTime';

/*
Result set 3:
Created procedures and their PSP behavior.
*/

SELECT
    SCHEMA_NAME(p.schema_id) AS SchemaName,
    p.name AS ProcedureName,
    p.create_date AS CreatedAt,
    p.modify_date AS ModifiedAt,
    CASE
        WHEN sm.definition LIKE
             N'%DISABLE_PARAMETER_SENSITIVE_PLAN%'
        THEN 1
        ELSE 0
    END AS DisablesPsp
FROM sys.procedures AS p
INNER JOIN sys.sql_modules AS sm
    ON sm.object_id = p.object_id
WHERE p.schema_id = SCHEMA_ID(N'telemetry')
  AND p.name IN
  (
      N'usp_EventTypeSummary_NoPsp',
      N'usp_EventTypeSummary_Psp'
  )
ORDER BY p.name;

/*
Result set 4:
Histogram for the leading index key.
*/

DBCC SHOW_STATISTICS
(
    N'telemetry.TelemetryEvent',
    N'IX_TelemetryEvent_EventType_EventTime'
)
WITH HISTOGRAM;