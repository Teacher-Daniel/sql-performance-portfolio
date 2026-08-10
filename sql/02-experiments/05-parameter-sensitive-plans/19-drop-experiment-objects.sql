/*
Experiment 05 - Drop experiment objects

Purpose:
Remove every database and server object created by Experiment 05 while
preserving the original telemetry data and automatic statistics.

Cleanup includes:
- Original-query experimental index and procedures.
- Equality-only fixture table and procedures.
- High/extreme-skew fixture table and procedures.
- Any remaining Experiment05_* Extended Events sessions.
- Restoration of Query Store capture mode to AUTO.

Historical Query Store records are intentionally retained as monitoring
telemetry and will follow the configured Query Store retention policy.

The script is safe to execute more than once.
*/

USE FleetTelemetryLab;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

DECLARE
    @StartedAt datetime2(7) = SYSDATETIME(),
    @OriginalCaptureMode nvarchar(60),
    @QueryStoreModeChanged bit = 0,
    @EventSessionName sysname,
    @DynamicSql nvarchar(max),
    @TelemetryEventObjectId int =
        OBJECT_ID(N'telemetry.TelemetryEvent'),
    @TelemetryEventRows bigint;

DECLARE @CleanupObjects TABLE
(
    ActionOrder int IDENTITY(1,1) PRIMARY KEY,
    ObjectType nvarchar(30) NOT NULL,
    ObjectName nvarchar(300) NOT NULL,
    ExistedBefore bit NOT NULL,
    ExistsAfter bit NULL
);

DECLARE @RemovedEventSessions TABLE
(
    EventSessionName sysname PRIMARY KEY
);

IF COALESCE
(
    CONVERT(sysname, SERVERPROPERTY(N'InstanceName')),
    N'MSSQLSERVER'
) <> N'SQL2025LAB'
BEGIN
    THROW 51000,
        'Safety check failed: execute this script on SQL2025LAB.',
        1;
END;

IF DB_NAME() <> N'FleetTelemetryLab'
BEGIN
    THROW 51001,
        'Safety check failed: the current database must be FleetTelemetryLab.',
        1;
END;

IF @TelemetryEventObjectId IS NULL
BEGIN
    THROW 51002,
        'The original table telemetry.TelemetryEvent does not exist.',
        1;
END;

/*
Record the initial object state for the cleanup report.
*/
INSERT INTO @CleanupObjects
(
    ObjectType,
    ObjectName,
    ExistedBefore
)
SELECT
    source.ObjectType,
    source.ObjectName,
    CASE
        WHEN OBJECT_ID(source.ObjectName) IS NOT NULL
        THEN 1
        ELSE 0
    END
FROM
(
    VALUES
        (
            N'PROCEDURE',
            N'telemetry.usp_EventTypeSummary_NoPsp'
        ),
        (
            N'PROCEDURE',
            N'telemetry.usp_EventTypeSummary_Psp'
        ),
        (
            N'PROCEDURE',
            N'telemetry.usp_PspEqualitySummary_NoPsp'
        ),
        (
            N'PROCEDURE',
            N'telemetry.usp_PspEqualitySummary_Psp'
        ),
        (
            N'PROCEDURE',
            N'telemetry.usp_PspHighSkewSummary_NoPsp'
        ),
        (
            N'PROCEDURE',
            N'telemetry.usp_PspHighSkewSummary_Psp'
        ),
        (
            N'TABLE',
            N'telemetry.PspEqualityEvent'
        ),
        (
            N'TABLE',
            N'telemetry.PspHighSkewEvent'
        )
) AS source
(
    ObjectType,
    ObjectName
);

INSERT INTO @CleanupObjects
(
    ObjectType,
    ObjectName,
    ExistedBefore
)
SELECT
    N'INDEX',
    N'telemetry.TelemetryEvent.IX_TelemetryEvent_EventType_EventTime',
    CASE
        WHEN EXISTS
        (
            SELECT 1
            FROM sys.indexes AS i
            WHERE i.object_id = @TelemetryEventObjectId
              AND i.name =
                  N'IX_TelemetryEvent_EventType_EventTime'
        )
        THEN 1
        ELSE 0
    END;

/*
Restore Query Store capture mode.
*/
SELECT
    @OriginalCaptureMode =
        qso.query_capture_mode_desc
FROM sys.database_query_store_options AS qso;

IF @OriginalCaptureMode <> N'AUTO'
BEGIN
    ALTER DATABASE FleetTelemetryLab
    SET QUERY_STORE
    (
        QUERY_CAPTURE_MODE = AUTO
    );

    SET @QueryStoreModeChanged = 1;
END;

/*
Remove any server-level event session belonging to Experiment 05.

The catalog-derived name is protected with QUOTENAME before it is
placed into dynamic DDL.
*/
WHILE EXISTS
(
    SELECT 1
    FROM sys.server_event_sessions AS ses
    WHERE ses.name LIKE N'Experiment05[_]%'
)
BEGIN
    SELECT TOP (1)
        @EventSessionName = ses.name
    FROM sys.server_event_sessions AS ses
    WHERE ses.name LIKE N'Experiment05[_]%'
    ORDER BY ses.name;

    IF EXISTS
    (
        SELECT 1
        FROM sys.dm_xe_sessions AS active_session
        WHERE active_session.name = @EventSessionName
    )
    BEGIN
        SET @DynamicSql =
            N'ALTER EVENT SESSION '
            + QUOTENAME(@EventSessionName)
            + N' ON SERVER STATE = STOP;';

        EXEC sys.sp_executesql
            @DynamicSql;
    END;

    SET @DynamicSql =
        N'DROP EVENT SESSION '
        + QUOTENAME(@EventSessionName)
        + N' ON SERVER;';

    EXEC sys.sp_executesql
        @DynamicSql;

    INSERT INTO @RemovedEventSessions
    (
        EventSessionName
    )
    VALUES
    (
        @EventSessionName
    );
END;

/*
Remove database objects atomically.
*/
BEGIN TRY
    BEGIN TRANSACTION;

    DROP PROCEDURE IF EXISTS
        telemetry.usp_EventTypeSummary_NoPsp;

    DROP PROCEDURE IF EXISTS
        telemetry.usp_EventTypeSummary_Psp;

    DROP PROCEDURE IF EXISTS
        telemetry.usp_PspEqualitySummary_NoPsp;

    DROP PROCEDURE IF EXISTS
        telemetry.usp_PspEqualitySummary_Psp;

    DROP PROCEDURE IF EXISTS
        telemetry.usp_PspHighSkewSummary_NoPsp;

    DROP PROCEDURE IF EXISTS
        telemetry.usp_PspHighSkewSummary_Psp;

    DROP TABLE IF EXISTS
        telemetry.PspEqualityEvent;

    DROP TABLE IF EXISTS
        telemetry.PspHighSkewEvent;

    IF EXISTS
    (
        SELECT 1
        FROM sys.indexes AS i
        WHERE i.object_id = @TelemetryEventObjectId
          AND i.name =
              N'IX_TelemetryEvent_EventType_EventTime'
    )
    BEGIN
        DROP INDEX
            IX_TelemetryEvent_EventType_EventTime
        ON telemetry.TelemetryEvent;
    END;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
    BEGIN
        ROLLBACK TRANSACTION;
    END;

    THROW;
END CATCH;

/*
Record the final object state.
*/
UPDATE cleanup
SET cleanup.ExistsAfter =
    CASE
        WHEN OBJECT_ID(cleanup.ObjectName) IS NOT NULL
        THEN 1
        ELSE 0
    END
FROM @CleanupObjects AS cleanup
WHERE cleanup.ObjectType <> N'INDEX';

UPDATE cleanup
SET cleanup.ExistsAfter =
    CASE
        WHEN EXISTS
        (
            SELECT 1
            FROM sys.indexes AS i
            WHERE i.object_id = @TelemetryEventObjectId
              AND i.name =
                  N'IX_TelemetryEvent_EventType_EventTime'
        )
        THEN 1
        ELSE 0
    END
FROM @CleanupObjects AS cleanup
WHERE cleanup.ObjectType = N'INDEX';

SELECT
    @TelemetryEventRows =
        COUNT_BIG(*)
FROM telemetry.TelemetryEvent;

/*
Final validation.
*/
IF EXISTS
(
    SELECT 1
    FROM @CleanupObjects AS cleanup
    WHERE cleanup.ExistsAfter <> 0
)
BEGIN
    THROW 51010,
        'One or more Experiment 05 database objects remain.',
        1;
END;

IF EXISTS
(
    SELECT 1
    FROM sys.server_event_sessions AS ses
    WHERE ses.name LIKE N'Experiment05[_]%'
)
BEGIN
    THROW 51011,
        'One or more Experiment 05 event sessions remain.',
        1;
END;

IF @TelemetryEventRows <> 1000000
BEGIN
    THROW 51012,
        'The original TelemetryEvent row count changed.',
        1;
END;

IF EXISTS
(
    SELECT 1
    FROM sys.indexes AS i
    WHERE i.object_id = @TelemetryEventObjectId
      AND i.index_id > 1
      AND i.is_hypothetical = 0
)
BEGIN
    THROW 51013,
        'An unexpected nonclustered index remains on TelemetryEvent.',
        1;
END;

IF NOT EXISTS
(
    SELECT 1
    FROM sys.stats AS s
    INNER JOIN sys.stats_columns AS sc
        ON sc.object_id = s.object_id
       AND sc.stats_id = s.stats_id
    INNER JOIN sys.columns AS c
        ON c.object_id = sc.object_id
       AND c.column_id = sc.column_id
    WHERE s.object_id = @TelemetryEventObjectId
      AND sc.stats_column_id = 1
      AND c.name = N'EventType'
      AND s.auto_created = 1
)
BEGIN
    THROW 51014,
        'The original automatic EventType statistic is unavailable.',
        1;
END;

IF NOT EXISTS
(
    SELECT 1
    FROM sys.database_query_store_options AS qso
    WHERE qso.actual_state_desc = N'READ_WRITE'
      AND qso.desired_state_desc = N'READ_WRITE'
      AND qso.query_capture_mode_desc = N'AUTO'
)
BEGIN
    THROW 51015,
        'Query Store was not restored to READ_WRITE and AUTO.',
        1;
END;

/*
Result set 1:
Cleanup summary. Every ExistsAfter value must be zero.
*/
SELECT
    cleanup.ActionOrder,
    cleanup.ObjectType,
    cleanup.ObjectName,
    cleanup.ExistedBefore,
    cleanup.ExistsAfter
FROM @CleanupObjects AS cleanup
ORDER BY cleanup.ActionOrder;

/*
Result set 2:
Event sessions removed by this execution.

An empty result is expected when all diagnostic scripts cleaned up
successfully.
*/
SELECT
    removed.EventSessionName
FROM @RemovedEventSessions AS removed
ORDER BY removed.EventSessionName;

/*
Result set 3:
Any remaining Experiment 05 objects.

An empty result is expected.
*/
SELECT
    SCHEMA_NAME(o.schema_id) AS SchemaName,
    o.name AS ObjectName,
    o.type_desc AS ObjectType
FROM sys.objects AS o
WHERE o.schema_id = SCHEMA_ID(N'telemetry')
  AND o.name IN
  (
      N'usp_EventTypeSummary_NoPsp',
      N'usp_EventTypeSummary_Psp',
      N'usp_PspEqualitySummary_NoPsp',
      N'usp_PspEqualitySummary_Psp',
      N'usp_PspHighSkewSummary_NoPsp',
      N'usp_PspHighSkewSummary_Psp',
      N'PspEqualityEvent',
      N'PspHighSkewEvent'
  )
ORDER BY o.name;

/*
Result set 4:
Final TelemetryEvent indexes.

Only the original clustered primary key is expected.
*/
SELECT
    i.index_id AS IndexId,
    i.name AS IndexName,
    i.type_desc AS IndexType,
    i.is_unique AS IsUnique,
    i.is_disabled AS IsDisabled
FROM sys.indexes AS i
WHERE i.object_id = @TelemetryEventObjectId
  AND i.index_id > 0
ORDER BY i.index_id;

/*
Result set 5:
The original automatic EventType statistic.
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
WHERE s.object_id = @TelemetryEventObjectId
  AND sc.stats_column_id = 1
  AND c.name = N'EventType'
ORDER BY
    s.auto_created DESC,
    s.user_created DESC,
    s.stats_id;

/*
Result set 6:
Final Query Store state.
*/
SELECT
    @OriginalCaptureMode AS OriginalCaptureMode,
    @QueryStoreModeChanged AS QueryStoreModeChanged,
    qso.actual_state_desc AS FinalActualState,
    qso.desired_state_desc AS FinalDesiredState,
    qso.query_capture_mode_desc AS FinalCaptureMode
FROM sys.database_query_store_options AS qso;

/*
Result set 7:
Cleanup timing and preservation of the original row count.
*/
SELECT
    @TelemetryEventRows AS TelemetryEventRows,
    DATEDIFF_BIG
    (
        millisecond,
        @StartedAt,
        SYSDATETIME()
    ) AS CleanupMilliseconds;
GO
