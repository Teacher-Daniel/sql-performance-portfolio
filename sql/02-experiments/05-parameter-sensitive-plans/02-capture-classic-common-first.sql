/*
Experiment 05 - Classic parameter sniffing: common value first

Purpose:
Compile the non-PSP procedure for the common EventType value and
then execute the rare value using the same cached plan.

Expected behavior:
- EventType 1 compiles a Clustered Index Scan.
- EventType 5 reuses that scan plan.
- Both executions read the complete clustered index.
*/

USE FleetTelemetryLab;

SET NOCOUNT ON;
SET XACT_ABORT ON;

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

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes AS i
    WHERE i.object_id =
          OBJECT_ID(N'telemetry.TelemetryEvent')
      AND i.name =
          N'IX_TelemetryEvent_EventType_EventTime'
      AND i.is_disabled = 0
)
BEGIN
    THROW 51002, 'The experimental index does not exist or is disabled.', 1;
END;

IF OBJECT_ID
(
    N'telemetry.usp_EventTypeSummary_NoPsp',
    N'P'
) IS NULL
BEGIN
    THROW 51003, 'The non-PSP procedure does not exist.', 1;
END;

IF OBJECT_DEFINITION
(
    OBJECT_ID(N'telemetry.usp_EventTypeSummary_NoPsp')
) NOT LIKE N'%DISABLE_PARAMETER_SENSITIVE_PLAN%'
BEGIN
    THROW 51004, 'The procedure does not contain the PSP-disabling hint.', 1;
END;

/*
Mark only this procedure for recompilation.

The next execution will compile for EventType 1 without clearing
the complete instance or database plan cache.
*/

EXEC sys.sp_recompile
    N'telemetry.usp_EventTypeSummary_NoPsp';

SET STATISTICS IO ON;
SET STATISTICS TIME ON;

PRINT N'Execution 1: common value compiles the cached plan.';

EXEC telemetry.usp_EventTypeSummary_NoPsp
    @EventType = 1;

PRINT N'Execution 2: rare value reuses the common-value plan.';

EXEC telemetry.usp_EventTypeSummary_NoPsp
    @EventType = 5;

SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;

/*
Result set 3:
Inspect the cached statement and its compiled parameter value.
*/

;WITH XMLNAMESPACES
(
    DEFAULT
    'http://schemas.microsoft.com/sqlserver/2004/07/showplan'
),
CachedPlanData AS
(
    SELECT
        qs.creation_time AS PlanCreationTime,
        qs.last_execution_time AS LastExecutionTime,
        qs.execution_count AS ExecutionCount,
        qs.plan_generation_num AS PlanGenerationNumber,
        qs.last_logical_reads AS LastLogicalReads,
        qs.min_logical_reads AS MinimumLogicalReads,
        qs.max_logical_reads AS MaximumLogicalReads,
        CONVERT
        (
            decimal(12,2),
            qs.last_worker_time / 1000.0
        ) AS LastCpuMilliseconds,
        CONVERT
        (
            decimal(12,2),
            qs.last_elapsed_time / 1000.0
        ) AS LastElapsedMilliseconds,
        qp.query_plan AS QueryPlan
    FROM sys.dm_exec_query_stats AS qs
    CROSS APPLY sys.dm_exec_sql_text
    (
        qs.sql_handle
    ) AS st
    CROSS APPLY sys.dm_exec_query_plan
    (
        qs.plan_handle
    ) AS qp
    WHERE st.dbid = DB_ID()
      AND st.objectid =
          OBJECT_ID
          (
              N'telemetry.usp_EventTypeSummary_NoPsp'
          )
)
SELECT
    cpd.PlanCreationTime,
    cpd.LastExecutionTime,
    cpd.ExecutionCount,
    cpd.PlanGenerationNumber,
    cpd.QueryPlan.value
    (
        '(//ParameterList/ColumnReference
          [@Column="@EventType"]
          /@ParameterCompiledValue)[1]',
        'nvarchar(128)'
    ) AS ParameterCompiledValue,
    cpd.LastLogicalReads,
    cpd.MinimumLogicalReads,
    cpd.MaximumLogicalReads,
    cpd.LastCpuMilliseconds,
    cpd.LastElapsedMilliseconds,
    cpd.QueryPlan
FROM CachedPlanData AS cpd;

/*
Persist current Query Store information to disk before the next
compilation-order test.
*/

EXEC sys.sp_query_store_flush_db;
