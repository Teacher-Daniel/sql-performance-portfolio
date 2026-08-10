/*
Experiment 05 - Capture extreme-skew PSP eligibility event

Purpose:
Capture the documented query_with_parameter_sensitivity event while
recompiling the equality-only 999,999-to-1 procedure.

Expected behavior:
- PSP identifies one interesting equality predicate.
- PSP optimization is reported as supported.
- No skipped-reason event is produced.
- The captured T-SQL stack resolves to the target procedure.

The temporary server-level event session is stopped and removed
before this script finishes.

This script does not modify permanent table data.
*/

USE FleetTelemetryLab;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

DECLARE
    @SessionName sysname =
        N'Experiment05_ExtremePspEligibility',
    @ProcedureId int =
        OBJECT_ID(N'telemetry.usp_PspHighSkewSummary_Psp'),
    @TargetData xml;

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

IF @ProcedureId IS NULL
BEGIN
    THROW 51002,
        'The high-skew PSP-eligible procedure does not exist.',
        1;
END;

IF EXISTS
(
    SELECT 1
    FROM sys.server_event_sessions AS ses
    WHERE ses.name = @SessionName
)
BEGIN
    THROW 51003,
        'The diagnostic event session already exists.',
        1;
END;

BEGIN TRY
    /*
    Capture:
    - The reason PSP was skipped.
    - Whether SQL Server found an interesting sensitive predicate.
    - The T-SQL stack that caused compilation.
    */
    CREATE EVENT SESSION
        [Experiment05_ExtremePspEligibility]
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
        [Experiment05_ExtremePspEligibility]
    ON SERVER
    STATE = START;

    EXEC sys.sp_recompile
        N'telemetry.usp_PspHighSkewSummary_Psp';

    RAISERROR
    (
        'Diagnostic execution: compile the extreme-skew common value.',
        10,
        1
    ) WITH NOWAIT;

    EXEC telemetry.usp_PspHighSkewSummary_Psp
        @SkewKey = 1;

    /*
    Allow the ring-buffer target to receive the events.
    */
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
        [Experiment05_ExtremePspEligibility]
    ON SERVER
    STATE = STOP;

    DROP EVENT SESSION
        [Experiment05_ExtremePspEligibility]
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
            [Experiment05_ExtremePspEligibility]
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
            [Experiment05_ExtremePspEligibility]
        ON SERVER;
    END;

    THROW;
END CATCH;

IF @TargetData IS NULL
BEGIN
    THROW 51004,
        'The diagnostic ring buffer returned no target data.',
        1;
END;

/*
Result set 1:
Return every payload field from the relevant PSP events.

For a skipped-reason event, DataText normally contains the
human-readable reason.
*/
;WITH CapturedEvents AS
(
    SELECT
        event_node.query('.') AS EventXml
    FROM @TargetData.nodes
    (
        '/RingBufferTarget/event'
    ) AS captured(event_node)
),
RelevantEvents AS
(
    SELECT
        ce.EventXml.value
        (
            '(/event/@name)[1]',
            'sysname'
        ) AS EventName,
        ce.EventXml.value
        (
            '(/event/@timestamp)[1]',
            'nvarchar(50)'
        ) AS EventTimestamp,
        ce.EventXml.value
        (
            '(/event/action
                [@name="sql_text"]
                /value/text())[1]',
            'nvarchar(max)'
        ) AS SqlText,
        ce.EventXml
    FROM CapturedEvents AS ce
    WHERE ce.EventXml.value
          (
              '(/event/@name)[1]',
              'sysname'
          ) IN
          (
              N'parameter_sensitive_plan_optimization_skipped_reason',
              N'query_with_parameter_sensitivity'
          )
)
SELECT
    re.EventName,
    re.EventTimestamp,
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
    re.SqlText
FROM RelevantEvents AS re
OUTER APPLY re.EventXml.nodes
(
    '/event/data'
) AS payload(data_node)
ORDER BY
    re.EventTimestamp,
    re.EventName,
    DataName;

/*
Result set 2:
Resolve every captured T-SQL stack frame automatically.

MatchesTargetProcedure identifies the frame belonging to
telemetry.usp_PspHighSkewSummary_Psp.
*/
;WITH CapturedEvents AS
(
    SELECT
        event_node.query('.') AS EventXml
    FROM @TargetData.nodes
    (
        '/RingBufferTarget/event'
    ) AS captured(event_node)
),
RelevantEvents AS
(
    SELECT
        ce.EventXml.value
        (
            '(/event/@name)[1]',
            'sysname'
        ) AS EventName,
        ce.EventXml.value
        (
            '(/event/@timestamp)[1]',
            'nvarchar(50)'
        ) AS EventTimestamp,
        ce.EventXml
    FROM CapturedEvents AS ce
    WHERE ce.EventXml.value
          (
              '(/event/@name)[1]',
              'sysname'
          ) IN
          (
              N'parameter_sensitive_plan_optimization_skipped_reason',
              N'query_with_parameter_sensitivity'
          )
),
StackFrames AS
(
    SELECT
        re.EventName,
        re.EventTimestamp,
        frame_node.value
        (
            '(@level)[1]',
            'int'
        ) AS FrameLevel,
        frame_node.value
        (
            '(@handle)[1]',
            'nvarchar(130)'
        ) AS HandleText,
        frame_node.value
        (
            '(@line)[1]',
            'int'
        ) AS LineNumber,
        frame_node.value
        (
            '(@offsetStart)[1]',
            'int'
        ) AS OffsetStart,
        frame_node.value
        (
            '(@offsetEnd)[1]',
            'int'
        ) AS OffsetEnd
    FROM RelevantEvents AS re
    CROSS APPLY re.EventXml.nodes
    (
        '/event/action
            [@name="tsql_stack"]
            /value/frames/frame'
    ) AS stack(frame_node)
),
ResolvedFrames AS
(
    SELECT
        sf.EventName,
        sf.EventTimestamp,
        sf.FrameLevel,
        sf.LineNumber,
        sf.OffsetStart,
        sf.OffsetEnd,
        sql_text.dbid AS DatabaseId,
        sql_text.objectid AS ObjectId,
        sql_text.text AS BatchText
    FROM StackFrames AS sf
    OUTER APPLY
    (
        SELECT
            TRY_CONVERT
            (
                varbinary(64),
                sf.HandleText,
                1
            ) AS SqlHandle
    ) AS converted
    OUTER APPLY sys.dm_exec_sql_text
    (
        converted.SqlHandle
    ) AS sql_text
)
SELECT
    rf.EventName,
    rf.EventTimestamp,
    rf.FrameLevel,
    rf.LineNumber,
    CASE
        WHEN rf.DatabaseId IS NOT NULL
         AND rf.ObjectId IS NOT NULL
        THEN OBJECT_SCHEMA_NAME
             (
                 rf.ObjectId,
                 rf.DatabaseId
             )
    END AS SchemaName,
    CASE
        WHEN rf.DatabaseId IS NOT NULL
         AND rf.ObjectId IS NOT NULL
        THEN OBJECT_NAME
             (
                 rf.ObjectId,
                 rf.DatabaseId
             )
    END AS ObjectName,
    CASE
        WHEN rf.ObjectId = @ProcedureId
        THEN 1
        ELSE 0
    END AS MatchesTargetProcedure,
    CASE
        WHEN rf.BatchText IS NULL
        THEN NULL
        WHEN rf.OffsetStart < 0
        THEN rf.BatchText
        ELSE SUBSTRING
             (
                 rf.BatchText,
                 (rf.OffsetStart / 2) + 1,
                 (
                     (
                         CASE
                             WHEN rf.OffsetEnd < 0
                             THEN DATALENGTH(rf.BatchText)
                             ELSE rf.OffsetEnd
                         END
                         - rf.OffsetStart
                     ) / 2
                 ) + 1
             )
    END AS FrameText
FROM ResolvedFrames AS rf
ORDER BY
    rf.EventTimestamp,
    rf.EventName,
    rf.FrameLevel;

/*
Result set 3:
Confirm that the temporary event session was removed.

An empty result is expected.
*/
SELECT
    ses.name AS RemainingEventSession
FROM sys.server_event_sessions AS ses
WHERE ses.name = @SessionName;

/*
Result set 4:
Confirm that Query Store remains unchanged.
*/
SELECT
    qso.actual_state_desc AS ActualState,
    qso.desired_state_desc AS DesiredState,
    qso.query_capture_mode_desc AS CaptureMode
FROM sys.database_query_store_options AS qso;
GO
