/*
Experiment 05 - Capture high-skew PSP threshold result

Purpose:
Determine whether an equality-only distribution containing 720,000
common rows and 216 rare rows exceeds SQL Server's internal PSP
skewness threshold.

Observed and asserted behavior:
- Independently optimized literals produce different physical plans.
- The common value compiles a clustered-index scan.
- The rare value reuses that cached scan.
- Query Store contains no dispatcher or query variants.
- The companion Extended Events diagnostic records
  SkewnessThresholdNotMet.

Query Store capture mode is temporarily changed from AUTO to ALL when
necessary and restored before the script finishes.

This script does not modify permanent table data.
*/

USE FleetTelemetryLab;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

DECLARE
    @ProcedureId int =
        OBJECT_ID(N'telemetry.usp_PspHighSkewSummary_Psp'),
    @OriginalCaptureMode nvarchar(60),
    @CaptureModeChanged bit = 0,
    @DispatcherCount int = 0,
    @VariantCount int = 0,
    @Attempt tinyint = 0;

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

IF
(
    SELECT d.compatibility_level
    FROM sys.databases AS d
    WHERE d.database_id = DB_ID()
) < 160
BEGIN
    THROW 51002,
        'PSP requires database compatibility level 160 or higher.',
        1;
END;

IF NOT EXISTS
(
    SELECT 1
    FROM sys.database_scoped_configurations AS dsc
    WHERE dsc.name =
        N'PARAMETER_SENSITIVE_PLAN_OPTIMIZATION'
      AND UPPER
          (
              CONVERT(nvarchar(60), dsc.value)
          ) IN
          (
              N'1',
              N'ON'
          )
)
BEGIN
    THROW 51003,
        'Parameter Sensitive Plan optimization is not enabled.',
        1;
END;

IF NOT EXISTS
(
    SELECT 1
    FROM sys.database_scoped_configurations AS dsc
    WHERE dsc.name = N'PARAMETER_SNIFFING'
      AND UPPER
          (
              CONVERT(nvarchar(60), dsc.value)
          ) IN
          (
              N'1',
              N'ON'
          )
)
BEGIN
    THROW 51004,
        'Parameter sniffing is not enabled.',
        1;
END;

IF OBJECT_ID
(
    N'telemetry.PspHighSkewEvent',
    N'U'
) IS NULL
BEGIN
    THROW 51005,
        'The table telemetry.PspHighSkewEvent does not exist.',
        1;
END;

IF @ProcedureId IS NULL
BEGIN
    THROW 51006,
        'The PSP-eligible high-skew procedure does not exist.',
        1;
END;

IF OBJECT_DEFINITION(@ProcedureId)
    LIKE N'%DISABLE_PARAMETER_SENSITIVE_PLAN%'
BEGIN
    THROW 51007,
        'The PSP-eligible procedure unexpectedly disables PSP.',
        1;
END;

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes AS i
    WHERE i.object_id =
        OBJECT_ID(N'telemetry.PspHighSkewEvent')
      AND i.name = N'IX_PspHighSkewEvent_SkewKey'
      AND i.is_disabled = 0
)
BEGIN
    THROW 51008,
        'The required high-skew nonclustered index is unavailable.',
        1;
END;

SELECT
    @OriginalCaptureMode = qso.query_capture_mode_desc
FROM sys.database_query_store_options AS qso;

IF NOT EXISTS
(
    SELECT 1
    FROM sys.database_query_store_options AS qso
    WHERE qso.actual_state_desc = N'READ_WRITE'
)
BEGIN
    THROW 51009,
        'Query Store must be in READ_WRITE state.',
        1;
END;

IF @OriginalCaptureMode NOT IN
(
    N'AUTO',
    N'ALL'
)
BEGIN
    THROW 51010,
        'Query Store capture mode must initially be AUTO or ALL.',
        1;
END;

BEGIN TRY
    IF @OriginalCaptureMode = N'AUTO'
    BEGIN
        ALTER DATABASE FleetTelemetryLab
        SET QUERY_STORE
        (
            QUERY_CAPTURE_MODE = ALL
        );

        SET @CaptureModeChanged = 1;
    END;

    EXEC sys.sp_recompile
        N'telemetry.usp_PspHighSkewSummary_Psp';

    RAISERROR
    (
        'Initialization 1: compile the common high-skew value.',
        10,
        1
    ) WITH NOWAIT;

    EXEC telemetry.usp_PspHighSkewSummary_Psp
        @SkewKey = 1;

    RAISERROR
    (
        'Initialization 2: test the rare value against the cached plan.',
        10,
        1
    ) WITH NOWAIT;

    EXEC telemetry.usp_PspHighSkewSummary_Psp
        @SkewKey = 5;

    SET STATISTICS IO ON;
    SET STATISTICS TIME ON;

    RAISERROR
    (
        'Measurement 1: common value uses the cached scan plan.',
        10,
        1
    ) WITH NOWAIT;

    EXEC telemetry.usp_PspHighSkewSummary_Psp
        @SkewKey = 1;

    RAISERROR
    (
        'Measurement 2: rare value reuses the cached scan plan.',
        10,
        1
    ) WITH NOWAIT;

    EXEC telemetry.usp_PspHighSkewSummary_Psp
        @SkewKey = 5;

    SET STATISTICS TIME OFF;
    SET STATISTICS IO OFF;

    /*
    Allow Query Store a short period to expose the dispatcher and
    both executed variants.
    */
    WHILE @Attempt < 10
    BEGIN
        SELECT
            @DispatcherCount =
                COUNT(DISTINCT qsp.plan_id)
        FROM sys.query_store_query AS parent_query
        INNER JOIN sys.query_store_plan AS qsp
            ON qsp.query_id = parent_query.query_id
        WHERE parent_query.object_id = @ProcedureId
          AND qsp.plan_type = 1;

        SELECT
            @VariantCount =
                COUNT(DISTINCT qsv.query_variant_query_id)
        FROM sys.query_store_query_variant AS qsv
        INNER JOIN sys.query_store_query AS parent_query
            ON parent_query.query_id =
               qsv.parent_query_id
        INNER JOIN sys.query_store_plan AS variant_plan
            ON variant_plan.query_id =
               qsv.query_variant_query_id
           AND variant_plan.plan_type = 2
        WHERE parent_query.object_id = @ProcedureId;

        IF @DispatcherCount >= 1
           AND @VariantCount >= 2
        BEGIN
            BREAK;
        END;

        WAITFOR DELAY '00:00:01';

        SET @Attempt += 1;
    END;

    IF @CaptureModeChanged = 1
    BEGIN
        ALTER DATABASE FleetTelemetryLab
        SET QUERY_STORE
        (
            QUERY_CAPTURE_MODE = AUTO
        );

        SET @CaptureModeChanged = 0;
    END;

    IF @DispatcherCount <> 0
       OR @VariantCount <> 0
    BEGIN
        THROW 51011,
            'Unexpected PSP objects were found; the observed threshold behavior changed.',
            1;
    END;
END TRY
BEGIN CATCH
    SET STATISTICS TIME OFF;
    SET STATISTICS IO OFF;

    IF @CaptureModeChanged = 1
    BEGIN
        ALTER DATABASE FleetTelemetryLab
        SET QUERY_STORE
        (
            QUERY_CAPTURE_MODE = AUTO
        );
    END;

    THROW;
END CATCH;

/*
Result set 1:
Confirm the expected PSP objects were discovered.
*/
SELECT
    @DispatcherCount AS DispatcherPlanCount,
    @VariantCount AS QueryVariantCount;

/*
Result set 2:
Return the dispatcher and every associated query variant.

The QueryPlan column is XML so each plan can be opened directly
from the SSMS results grid.
*/
;WITH ParentQueries AS
(
    SELECT
        q.query_id AS ParentQueryId
    FROM sys.query_store_query AS q
    WHERE q.object_id = @ProcedureId
),
RelevantPlans AS
(
    SELECT
        N'Dispatcher' AS RelationshipType,
        qsp.plan_type_desc AS PlanType,
        qsp.plan_id AS PlanId,
        qsp.query_id AS QueryId,
        CONVERT(bigint, NULL) AS QueryVariantQueryId,
        pq.ParentQueryId,
        qsp.plan_id AS DispatcherPlanId,
        qsp.is_parallel_plan AS IsParallelPlan,
        qsp.count_compiles AS CompileCount,
        qsp.query_plan AS QueryPlanText
    FROM ParentQueries AS pq
    INNER JOIN sys.query_store_plan AS qsp
        ON qsp.query_id = pq.ParentQueryId
    WHERE qsp.plan_type = 1

    UNION ALL

    SELECT
        N'Query variant' AS RelationshipType,
        variant_plan.plan_type_desc AS PlanType,
        variant_plan.plan_id AS PlanId,
        variant_plan.query_id AS QueryId,
        qsv.query_variant_query_id AS QueryVariantQueryId,
        qsv.parent_query_id AS ParentQueryId,
        qsv.dispatcher_plan_id AS DispatcherPlanId,
        variant_plan.is_parallel_plan AS IsParallelPlan,
        variant_plan.count_compiles AS CompileCount,
        variant_plan.query_plan AS QueryPlanText
    FROM ParentQueries AS pq
    INNER JOIN sys.query_store_query_variant AS qsv
        ON qsv.parent_query_id = pq.ParentQueryId
    INNER JOIN sys.query_store_plan AS variant_plan
        ON variant_plan.query_id =
           qsv.query_variant_query_id
       AND variant_plan.plan_type = 2
),
PlanDetails AS
(
    SELECT
        rp.RelationshipType,
        rp.PlanType,
        rp.PlanId,
        rp.QueryId,
        rp.QueryVariantQueryId,
        rp.ParentQueryId,
        rp.DispatcherPlanId,
        rp.IsParallelPlan,
        rp.CompileCount,
        TRY_CONVERT(xml, rp.QueryPlanText)
            AS QueryPlan
    FROM RelevantPlans AS rp
)
SELECT
    pd.RelationshipType,
    pd.PlanType,
    pd.PlanId,
    pd.QueryId,
    pd.QueryVariantQueryId,
    pd.ParentQueryId,
    pd.DispatcherPlanId,
    pd.IsParallelPlan,
    pd.CompileCount,
    pd.QueryPlan.value
    (
        '(//*[local-name()="ColumnReference"]
            [@ParameterCompiledValue][1]
            /@ParameterCompiledValue)[1]',
        'nvarchar(128)'
    ) AS ParameterCompiledValue,
    pd.QueryPlan.value
    (
        '((//*[local-name()="RelOp"]
            [
                @PhysicalOp="Clustered Index Scan"
                or @PhysicalOp="Index Seek"
            ])[1]/@PhysicalOp)[1]',
        'nvarchar(60)'
    ) AS PrincipalAccessOperator,
    CASE
        WHEN CONVERT(nvarchar(max), pd.QueryPlan)
             LIKE N'%ParameterSensitivePredicate%'
        THEN 1
        ELSE 0
    END AS HasParameterSensitivePredicate,
    CASE
        WHEN CONVERT(nvarchar(max), pd.QueryPlan)
             LIKE N'%PLAN PER VALUE%'
        THEN 1
        ELSE 0
    END AS HasPlanPerValue,
    runtime_data.ExecutionCount,
    runtime_data.LastExecutionTime,
    pd.QueryPlan
FROM PlanDetails AS pd
OUTER APPLY
(
    SELECT
        SUM(CONVERT(bigint, qrs.count_executions))
            AS ExecutionCount,
        MAX(qrs.last_execution_time)
            AS LastExecutionTime
    FROM sys.query_store_runtime_stats AS qrs
    WHERE qrs.plan_id = pd.PlanId
) AS runtime_data
ORDER BY
    CASE pd.RelationshipType
        WHEN N'Dispatcher' THEN 0
        ELSE 1
    END,
    pd.QueryVariantQueryId,
    pd.PlanId;

/*
Result set 3:
Confirm that Query Store returned to its original capture mode.
*/
SELECT
    @OriginalCaptureMode AS OriginalCaptureMode,
    qso.actual_state_desc AS FinalActualState,
    qso.desired_state_desc AS FinalDesiredState,
    qso.query_capture_mode_desc AS FinalCaptureMode
FROM sys.database_query_store_options AS qso;
GO
