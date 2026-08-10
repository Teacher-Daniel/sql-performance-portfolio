/*
Experiment 05 - Diagnose PSP eligibility

Purpose:
Capture the documented PSP diagnostic events while recompiling
and executing the PSP-eligible procedure.

The temporary server-level event session is stopped and removed
before this script finishes.
*/

USE FleetTelemetryLab;

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @SessionName sysname =
    N'Experiment05_PspEligibility';

DECLARE @TargetData xml;

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

IF OBJECT_ID
(
    N'telemetry.usp_EventTypeSummary_Psp',
    N'P'
) IS NULL
BEGIN
    THROW 51002, 'The PSP-eligible procedure does not exist.', 1;
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
    /*
    Capture:
    - The reason PSP was skipped.
    - Whether SQL Server found an interesting sensitive predicate.
    */

    CREATE EVENT SESSION
        [Experiment05_PspEligibility]
    ON SERVER
    ADD EVENT
        sqlserver.parameter_sensitive_plan_optimization_skipped_reason
    (
        ACTION
        (
            sqlserver.database_id,
            sqlserver.database_name,
            sqlserver.sql_text
            ,sqlserver.tsql_stack --Inclusión posterior
        )
    ),
    ADD EVENT
        sqlserver.query_with_parameter_sensitivity
    (
        ACTION
        (
            sqlserver.database_id,
            sqlserver.database_name,
            sqlserver.sql_text
            ,sqlserver.tsql_stack --Inclusión posterior
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
        [Experiment05_PspEligibility]
    ON SERVER
    STATE = START;

    EXEC sys.sp_recompile
        N'telemetry.usp_EventTypeSummary_Psp';

    EXEC telemetry.usp_EventTypeSummary_Psp
        @EventType = 1;

    EXEC telemetry.usp_EventTypeSummary_Psp
        @EventType = 5;

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
        [Experiment05_PspEligibility]
    ON SERVER
    STATE = STOP;

    DROP EVENT SESSION
        [Experiment05_PspEligibility]
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
            [Experiment05_PspEligibility]
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
            [Experiment05_PspEligibility]
        ON SERVER;
    END;

    THROW;
END CATCH;

IF @TargetData IS NULL
BEGIN
    THROW 51004, 'The diagnostic ring buffer returned no target data.', 1;
END;

/*
Result set 1:
Return every payload field from the relevant PSP events.

DataText normally contains the human-readable skipped reason.
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
--Inicio: Inclusión posterior.
        CONVERT
        (
            nvarchar(max),
            ce.EventXml.query
            (
                '(/event/action
                  [@name="tsql_stack"])[1]'
            )
        ) AS TsqlStack,
--Fin: Inclusión posterior.
        ce.EventXml
    FROM CapturedEvents AS ce
    WHERE CONVERT
          (
              nvarchar(max),
              ce.EventXml
          ) LIKE N'%TelemetryEvent%'
       OR CONVERT
          (
              nvarchar(max),
              ce.EventXml
          ) LIKE N'%usp_EventTypeSummary_Psp%'
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
    re.TsqlStack,--Inclusión posterior.
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
Confirm that the temporary event session was removed.

An empty result is expected.
*/

SELECT
    ses.name AS RemainingEventSession
FROM sys.server_event_sessions AS ses
WHERE ses.name = @SessionName;
