/*
Experiment 05 - Create equality-only PSP fixture

Purpose:
Create an independent 1,000,000-row experimental table whose
SensitivityKey materializes the original date-window predicate.

The resulting stored procedures use one equality predicate only:

    SensitivityKey = @SensitivityKey

This makes the workload eligible for PSP while preserving the
original common and rare result sets.

The source telemetry.TelemetryEvent table is not modified.
*/

USE FleetTelemetryLab;

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @CreationStartedAt datetime2(7);
DECLARE @CreationMilliseconds bigint;

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
        THROW 51002, 'The source telemetry table does not exist.', 1;
    END;

    IF
    (
        SELECT d.compatibility_level
        FROM sys.databases AS d
        WHERE d.database_id = DB_ID()
    ) < 160
    BEGIN
        THROW 51003, 'PSP requires compatibility level 160 or later.', 1;
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

    IF OBJECT_ID
    (
        N'telemetry.PspEqualityEvent',
        N'U'
    ) IS NOT NULL
    BEGIN
        THROW 51005, 'The equality-only fixture table already exists.', 1;
    END;

    IF OBJECT_ID
    (
        N'telemetry.usp_PspEqualitySummary_NoPsp',
        N'P'
    ) IS NOT NULL
    OR OBJECT_ID
    (
        N'telemetry.usp_PspEqualitySummary_Psp',
        N'P'
    ) IS NOT NULL
    BEGIN
        THROW 51006, 'One or more equality-only procedures already exist.', 1;
    END;

    IF
    (
        SELECT SUM(dps.row_count)
        FROM sys.dm_db_partition_stats AS dps
        WHERE dps.object_id =
              OBJECT_ID(N'telemetry.TelemetryEvent')
          AND dps.index_id IN (0, 1)
    ) <> 1000000
    BEGIN
        THROW 51007, 'The source table must contain exactly 1,000,000 rows.', 1;
    END;

    SET @CreationStartedAt = SYSDATETIME();

    BEGIN TRANSACTION;

    /*
    SensitivityKey distribution:

    0 = Every row outside the selected 24-hour interval.
    1-5 = Original EventType inside that interval.

    PayloadPadding keeps the clustered table sufficiently wide for
    the scan-versus-Key-Lookup cost choice to remain observable.
    */

    SELECT
        IDENTITY(bigint, 1, 1) AS PspEventId,
        CONVERT
        (
            tinyint,
            CASE
                WHEN te.EventTime >=
                     '2024-12-06T00:00:00'
                 AND te.EventTime <
                     '2024-12-07T00:00:00'
                THEN te.EventType
                ELSE 0
            END
        ) AS SensitivityKey,
        te.EventTime,
        te.SpeedKph,
        te.BatteryVoltage,
        CONVERT
        (
            char(32),
            REPLICATE('X', 32)
        ) AS PayloadPadding
    INTO telemetry.PspEqualityEvent
    FROM telemetry.TelemetryEvent AS te;

    ALTER TABLE telemetry.PspEqualityEvent
    ADD CONSTRAINT PK_telemetry_PspEqualityEvent
        PRIMARY KEY CLUSTERED
        (
            PspEventId
        );

    CREATE NONCLUSTERED INDEX
        IX_PspEqualityEvent_SensitivityKey
    ON telemetry.PspEqualityEvent
    (
        SensitivityKey
    );

    /*
    Validate the materialized common and rare populations before
    committing the fixture.
    */

    IF
    (
        SELECT COUNT_BIG(*)
        FROM telemetry.PspEqualityEvent
        WHERE SensitivityKey = 1
    ) <> 3870
    BEGIN
        THROW 51008, 'Unexpected common-value fixture cardinality.', 1;
    END;

    IF
    (
        SELECT COUNT_BIG(*)
        FROM telemetry.PspEqualityEvent
        WHERE SensitivityKey = 5
    ) <> 216
    BEGIN
        THROW 51009, 'Unexpected rare-value fixture cardinality.', 1;
    END;

    EXEC sys.sp_executesql N'
CREATE PROCEDURE telemetry.usp_PspEqualitySummary_NoPsp
    @SensitivityKey tinyint
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
    FROM telemetry.PspEqualityEvent
    WHERE SensitivityKey = @SensitivityKey
    OPTION
    (
        USE HINT(''DISABLE_PARAMETER_SENSITIVE_PLAN'')
    );
END;';

    EXEC sys.sp_executesql N'
CREATE PROCEDURE telemetry.usp_PspEqualitySummary_Psp
    @SensitivityKey tinyint
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
    FROM telemetry.PspEqualityEvent
    WHERE SensitivityKey = @SensitivityKey;
END;';

    COMMIT TRANSACTION;

    SET @CreationMilliseconds =
        DATEDIFF_BIG
        (
            millisecond,
            @CreationStartedAt,
            SYSDATETIME()
        );
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
    BEGIN
        ROLLBACK TRANSACTION;
    END;

    THROW;
END CATCH;

/*
Result set 1:
Total fixture creation time.
*/

SELECT
    @CreationMilliseconds AS FixtureCreationMilliseconds;

/*
Result set 2:
Materialized equality-key distribution.
*/

SELECT
    pe.SensitivityKey,
    COUNT_BIG(*) AS EventCount,
    CONVERT
    (
        decimal(9,4),
        COUNT_BIG(*) * 100.0 / 1000000.0
    ) AS Percentage
FROM telemetry.PspEqualityEvent AS pe
GROUP BY pe.SensitivityKey
ORDER BY pe.SensitivityKey;

/*
Result set 3:
Clustered and nonclustered index characteristics.
*/

SELECT
    i.name AS IndexName,
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
WHERE i.object_id =
      OBJECT_ID(N'telemetry.PspEqualityEvent')
GROUP BY
    i.name,
    i.type_desc
ORDER BY
    MIN(i.index_id);

/*
Result set 4:
Full-scan statistics belonging to the equality-key index.
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
WHERE s.object_id =
      OBJECT_ID(N'telemetry.PspEqualityEvent')
  AND s.name =
      N'IX_PspEqualityEvent_SensitivityKey';

/*
Result set 5:
Equality-only procedures and PSP behavior.
*/

SELECT
    SCHEMA_NAME(p.schema_id) AS SchemaName,
    p.name AS ProcedureName,
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
      N'usp_PspEqualitySummary_NoPsp',
      N'usp_PspEqualitySummary_Psp'
  )
ORDER BY p.name;

/*
Result set 6:
Exact histogram for SensitivityKey.
*/

DBCC SHOW_STATISTICS
(
    N'telemetry.PspEqualityEvent',
    N'IX_PspEqualityEvent_SensitivityKey'
)
WITH HISTOGRAM;
