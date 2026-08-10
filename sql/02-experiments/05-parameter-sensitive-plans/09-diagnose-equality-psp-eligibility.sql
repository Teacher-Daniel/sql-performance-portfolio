/*
Experiment 05 - Diagnose equality-only PSP eligibility

Purpose:
Capture the documented PSP diagnostic events for the equality-only
procedure and resolve every T-SQL stack handle automatically.

The temporary Extended Events session is removed before this
script finishes.
*/

USE FleetTelemetryLab;

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @SessionName sysname =
    N'Experiment05_EqualityPspDiagnosis';

DECLARE @ProcedureObjectId int =
    OBJECT_ID(N'telemetry.usp_PspEqualitySummary_Psp');

DECLARE @TargetData xml;

DECLARE @Events table
(
    EventOrdinal int IDENTITY(1,1) NOT NULL,
    EventName sysname NULL,
    EventTimestamp nvarchar(50) NULL,
    EventXml xml NOT NULL
);

DECLARE @Frames table
(
    EventOrdinal int NOT NULL,
    FrameLevel int NULL,
    SqlHandle varbinary(64) NULL,
    LineNumber int NULL,
    OffsetStart int NULL,
    OffsetEnd int NULL
);

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

IF @ProcedureObjectId IS NULL
BEGIN
    THROW 51002, 'The equality-only PSP procedure does not exist.', 1;
END;

IF EXISTS
(
    SELECT 1
    FROM sys.server_event_sessions AS ses
    WHERE ses.name = @SessionName
)
BEGIN
    THROW 51003, 'The diagnostic event session already exists.', 1;
END;

BEGIN TRY
    CREATE EVENT SESSION
        [Experiment05_EqualityPspDiagnosis]
    ON SERVER
    ADD EVENT
        sqlserver.parameter_sensitive_plan_optimization_skipped_reason
    (
        ACTION
        (
            sqlserver.database_id,
            sqlserver.database_name,
            sqlserver.sql_text,
            sqlserver.tsql_stack
        )
    ),
    ADD EVENT
        sqlserver.query_with_parameter_sensitivity
    (
        ACTION
        (
            sqlserver.database_id,
            sqlserver.database_name,
            sqlserver.sql_text,
            sqlserver.tsql_stack
        )
    )
    ADD TARGET package0.ring_buffer
    (
        SET max_memory = 4096
    )
    WITH
    (
        MAX_MEMORY = 4096 KB,
        EVENT_RETENTION_MODE = ALLOW_SINGLE_EVENT_LOSS,
        MAX_DISPATCH_LATENCY = 1 SECONDS,
        TRACK_CAUSALITY = OFF,
        STARTUP_STATE = OFF
    );

    ALTER EVENT SESSION
        [Experiment05_EqualityPspDiagnosis]
    ON SERVER
    STATE = START;

    EXEC sys.sp_recompile
        N'telemetry.usp_PspEqualitySummary_Psp';

    EXEC telemetry.usp_PspEqualitySummary_Psp
        @SensitivityKey = 1;

    EXEC telemetry.usp_PspEqualitySummary_Psp
        @SensitivityKey = 5;

    WAITFOR DELAY '00:00:01';

    SELECT
        @TargetData =
            TRY_CONVERT(xml, target.target_data)
    FROM sys.dm_xe_sessions AS session
    INNER JOIN sys.dm_xe_session_targets AS target
        ON target.event_session_address =
           session.address
    WHERE session.name = @SessionName
      AND target.target_name = N'ring_buffer';

    ALTER EVENT SESSION
        [Experiment05_EqualityPspDiagnosis]
    ON SERVER
    STATE = STOP;

    DROP EVENT SESSION
        [Experiment05_EqualityPspDiagnosis]
    ON SERVER;
END TRY
BEGIN CATCH
    IF EXISTS
    (
        SELECT 1
        FROM sys.dm_xe_sessions AS session
        WHERE session.name = @SessionName
    )
    BEGIN
        ALTER EVENT SESSION
            [Experiment05_EqualityPspDiagnosis]
        ON SERVER
        STATE = STOP;
    END;

    IF EXISTS
    (
        SELECT 1
        FROM sys.server_event_sessions AS ses
        WHERE ses.name = @SessionName
    )
    BEGIN
        DROP EVENT SESSION
            [Experiment05_EqualityPspDiagnosis]
        ON SERVER;
    END;

    THROW;
END CATCH;

IF @TargetData IS NULL
BEGIN
    THROW 51004, 'The diagnostic ring buffer returned no target data.', 1;
END;

/*
Materialize the captured events.
*/

INSERT INTO @Events
(
    EventName,
    EventTimestamp,
    EventXml
)
SELECT
    event_node.value
    (
        '(@name)[1]',
        'sysname'
    ),
    event_node.value
    (
        '(@timestamp)[1]',
        'nvarchar(50)'
    ),
    event_node.query('.')
FROM @TargetData.nodes
(
    '/RingBufferTarget/event'
) AS captured(event_node);

/*
Materialize and decode every T-SQL stack frame.
*/

INSERT INTO @Frames
(
    EventOrdinal,
    FrameLevel,
    SqlHandle,
    LineNumber,
    OffsetStart,
    OffsetEnd
)
SELECT
    event.EventOrdinal,
    frame_node.value
    (
        '(@level)[1]',
        'int'
    ),
    TRY_CONVERT
    (
        varbinary(64),
        frame_node.value
        (
            '(@handle)[1]',
            'varchar(130)'
        ),
        1
    ),
    frame_node.value
    (
        '(@line)[1]',
        'int'
    ),
    frame_node.value
    (
        '(@offsetStart)[1]',
        'int'
    ),
    frame_node.value
    (
        '(@offsetEnd)[1]',
        'int'
    )
FROM @Events AS event
CROSS APPLY event.EventXml.nodes
(
    '/event/action
      [@name="tsql_stack"]
      /value/frames/frame'
) AS stack(frame_node);

/*
Result set 1:
Event payloads.

MatchesTargetProcedure identifies events whose stack contains the
equality-only PSP procedure.
*/

SELECT
    event.EventOrdinal,
    event.EventName,
    event.EventTimestamp,
    payload.data_node.value
    (
        '(@name)[1]',
        'sysname'
    ) AS DataName,
    NULLIF
    (
        payload.data_node.value
        (
            '(value/text())[1]',
            'nvarchar(4000)'
        ),
        N''
    ) AS DataValue,
    NULLIF
    (
        payload.data_node.value
        (
            '(text/text())[1]',
            'nvarchar(4000)'
        ),
        N''
    ) AS DataText,
    CONVERT
    (
        bit,
        CASE
            WHEN EXISTS
            (
                SELECT 1
                FROM @Frames AS frame
                OUTER APPLY sys.dm_exec_sql_text
                (
                    frame.SqlHandle
                ) AS text_info
                WHERE frame.EventOrdinal =
                      event.EventOrdinal
                  AND text_info.dbid = DB_ID()
                  AND text_info.objectid =
                      @ProcedureObjectId
            )
            THEN 1
            ELSE 0
        END
    ) AS MatchesTargetProcedure
FROM @Events AS event
OUTER APPLY event.EventXml.nodes
(
    '/event/data'
) AS payload(data_node)
ORDER BY
    event.EventOrdinal,
    DataName;

/*
Result set 2:
Resolved stack frames and their exact statement text.
*/

SELECT
    frame.EventOrdinal,
    frame.FrameLevel,
    frame.LineNumber,
    text_info.dbid AS DatabaseId,
    DB_NAME(text_info.dbid) AS DatabaseName,
    text_info.objectid AS ObjectId,
    OBJECT_SCHEMA_NAME
    (
        text_info.objectid,
        text_info.dbid
    ) AS SchemaName,
    OBJECT_NAME
    (
        text_info.objectid,
        text_info.dbid
    ) AS ObjectName,
    CASE
        WHEN frame.OffsetStart < 0
          OR frame.OffsetEnd < 0
        THEN text_info.text
        ELSE SUBSTRING
             (
                 text_info.text,
                 frame.OffsetStart / 2 + 1,
                 (frame.OffsetEnd - frame.OffsetStart)
                 / 2 + 1
             )
    END AS FrameText
FROM @Frames AS frame
OUTER APPLY sys.dm_exec_sql_text
(
    frame.SqlHandle
) AS text_info
ORDER BY
    frame.EventOrdinal,
    frame.FrameLevel;

/*
Result set 3:
Confirm removal of the temporary event session.

An empty result is expected.
*/

SELECT
    ses.name AS RemainingEventSession
FROM sys.server_event_sessions AS ses
WHERE ses.name = @SessionName;
