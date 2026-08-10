/*
Experiment 05 - Capture extreme-skew classic common-first reuse

Purpose:
Demonstrate ordinary parameter sniffing and cached-plan reuse for the
999,999-to-1 distribution while PSP is disabled by a query-level hint.

Execution order:
1. The common value compiles a clustered-index scan.
2. The rare value reuses that same cached scan.

The procedure still permits parameter sniffing and ordinary plan reuse.
Only Parameter Sensitive Plan optimization is disabled.

This script does not modify permanent data.
*/

USE FleetTelemetryLab;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

DECLARE
    @ProcedureId int =
        OBJECT_ID(N'telemetry.usp_PspHighSkewSummary_NoPsp'),
    @TotalRows bigint,
    @CommonRows bigint,
    @RareRows bigint;

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

IF OBJECT_ID
(
    N'telemetry.PspHighSkewEvent',
    N'U'
) IS NULL
BEGIN
    THROW 51002,
        'The table telemetry.PspHighSkewEvent does not exist.',
        1;
END;

IF @ProcedureId IS NULL
BEGIN
    THROW 51003,
        'The classic high-skew procedure does not exist.',
        1;
END;

IF OBJECT_DEFINITION(@ProcedureId)
    NOT LIKE N'%DISABLE_PARAMETER_SENSITIVE_PLAN%'
BEGIN
    THROW 51004,
        'The classic procedure does not contain the PSP-disabling hint.',
        1;
END;

SELECT
    @TotalRows = COUNT_BIG(*),
    @CommonRows = SUM
    (
        CONVERT
        (
            bigint,
            CASE
                WHEN phe.SkewKey = 1 THEN 1
                ELSE 0
            END
        )
    ),
    @RareRows = SUM
    (
        CONVERT
        (
            bigint,
            CASE
                WHEN phe.SkewKey = 5 THEN 1
                ELSE 0
            END
        )
    )
FROM telemetry.PspHighSkewEvent AS phe;

IF @TotalRows <> 1000000
   OR @CommonRows <> 999999
   OR @RareRows <> 1
BEGIN
    THROW 51005,
        'The extreme-skew fixture does not contain the expected distribution.',
        1;
END;

EXEC sys.sp_recompile
    N'telemetry.usp_PspHighSkewSummary_NoPsp';

SET STATISTICS IO ON;
SET STATISTICS TIME ON;

RAISERROR
(
    'Execution 1: common value compiles the classic cached scan plan.',
    10,
    1
) WITH NOWAIT;

EXEC telemetry.usp_PspHighSkewSummary_NoPsp
    @SkewKey = 1;

RAISERROR
(
    'Execution 2: rare value reuses the common-value scan plan.',
    10,
    1
) WITH NOWAIT;

EXEC telemetry.usp_PspHighSkewSummary_NoPsp
    @SkewKey = 5;

SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;

/*
Result set 1:
Inspect the single cached procedure plan.

Expected:
- Execution count: 2
- Compiled parameter: (1)
- No PSP markers
- Last execution corresponds to the rare value
*/
SELECT
    ps.cached_time AS PlanCreationTime,
    ps.last_execution_time AS LastExecutionTime,
    ps.execution_count AS ExecutionCount,
    plan_data.query_plan.value
    (
        '(//*[local-name()="ColumnReference"]
            [@Column="@SkewKey"]
            [@ParameterCompiledValue][1]
            /@ParameterCompiledValue)[1]',
        'nvarchar(128)'
    ) AS ParameterCompiledValue,
    ps.last_logical_reads AS LastLogicalReads,
    ps.min_logical_reads AS MinimumLogicalReads,
    ps.max_logical_reads AS MaximumLogicalReads,
    CONVERT
    (
        decimal(18,2),
        ps.last_worker_time / 1000.0
    ) AS LastCpuMilliseconds,
    CONVERT
    (
        decimal(18,2),
        ps.last_elapsed_time / 1000.0
    ) AS LastElapsedMilliseconds,
    CASE
        WHEN CONVERT
             (
                 nvarchar(max),
                 plan_data.query_plan
             ) LIKE N'%ParameterSensitivePredicate%'
          OR CONVERT
             (
                 nvarchar(max),
                 plan_data.query_plan
             ) LIKE N'%QueryVariantID%'
        THEN 1
        ELSE 0
    END AS HasPspMarkers,
    plan_data.query_plan AS QueryPlan
FROM sys.dm_exec_procedure_stats AS ps
CROSS APPLY sys.dm_exec_query_plan
(
    ps.plan_handle
) AS plan_data
WHERE ps.database_id = DB_ID()
  AND ps.object_id = @ProcedureId;
GO
