/*
Experiment 05 - Equality-only PSP skew threshold not met

Purpose:
Execute an equality-only parameter-sensitive query with PSP enabled
and document that SQL Server does not create a dispatcher because
the internal skewness threshold is not met.

Observed behavior:
- Independent compilation produces different common and rare plans.
- PSP-enabled common-first compilation caches a scan.
- The rare value reuses the same scan.
- Both values perform 7,898 logical reads.
- Query Store contains no dispatcher or variants.
- Extended Events reports SkewnessThresholdNotMet.
*/

USE FleetTelemetryLab;

SET NOCOUNT ON;
SET XACT_ABORT ON;
SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;

DECLARE @CaptureModeChanged bit = 0;

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

IF
(
    SELECT d.compatibility_level
    FROM sys.databases AS d
    WHERE d.database_id = DB_ID()
) < 160
BEGIN
    THROW 51002, 'PSP requires compatibility level 160 or later.', 1;
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
    THROW 51003, 'PARAMETER_SENSITIVE_PLAN_OPTIMIZATION must be enabled.', 1;
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
    THROW 51004, 'PARAMETER_SNIFFING must be enabled.', 1;
END;

IF OBJECT_ID
(
    N'telemetry.PspEqualityEvent',
    N'U'
) IS NULL
BEGIN
    THROW 51005, 'The equality-only fixture table does not exist.', 1;
END;

IF OBJECT_ID
(
    N'telemetry.usp_PspEqualitySummary_Psp',
    N'P'
) IS NULL
BEGIN
    THROW 51006, 'The equality-only PSP procedure does not exist.', 1;
END;

IF OBJECT_DEFINITION
(
    OBJECT_ID(N'telemetry.usp_PspEqualitySummary_Psp')
) LIKE N'%DISABLE_PARAMETER_SENSITIVE_PLAN%'
BEGIN
    THROW 51007, 'The equality-only PSP procedure unexpectedly disables PSP.', 1;
END;

IF NOT EXISTS
(
    SELECT 1
    FROM sys.database_query_store_options AS qso
    WHERE qso.actual_state_desc = N'READ_WRITE'
)
BEGIN
    THROW 51008, 'Query Store must be in READ_WRITE state.', 1;
END;

IF
(
    SELECT qso.query_capture_mode_desc
    FROM sys.database_query_store_options AS qso
) <> N'AUTO'
BEGIN
    THROW 51009, 'Query Store capture mode must initially be AUTO.', 1;
END;

BEGIN TRY
    ALTER DATABASE FleetTelemetryLab
    SET QUERY_STORE
    (
        QUERY_CAPTURE_MODE = ALL
    );

    SET @CaptureModeChanged = 1;

    /*
    Remove only the cached plans belonging to this procedure.
    */

    EXEC sys.sp_recompile
        N'telemetry.usp_PspEqualitySummary_Psp';

    /*
    Initialization pair:
    Create the dispatcher and the common and rare variants.
    */

    PRINT N'Initialization 1: compile the common equality value';

    EXEC telemetry.usp_PspEqualitySummary_Psp
        @SensitivityKey = 1;

    PRINT N'Initialization 2: rare value reuses the common-value plan..';

    EXEC telemetry.usp_PspEqualitySummary_Psp
        @SensitivityKey = 5;

    /*
    Measured pair:
    Reuse both variants with warm data pages.
    */

    SET STATISTICS IO ON;
    SET STATISTICS TIME ON;

    PRINT N'Measurement 1: common value uses the cached scan.';

    EXEC telemetry.usp_PspEqualitySummary_Psp
        @SensitivityKey = 1;

    PRINT N'Measurement 2: rare value reuses the cached scan.';

    EXEC telemetry.usp_PspEqualitySummary_Psp
        @SensitivityKey = 5;

    SET STATISTICS TIME OFF;
    SET STATISTICS IO OFF;

    EXEC sys.sp_query_store_flush_db;

    /*
    Result set 5:
    Search Query Store for a dispatcher and query variants.

    An empty result is expected because the PSP skewness threshold
    was not met.
    */
    ;WITH XMLNAMESPACES
    (
        DEFAULT
        'http://schemas.microsoft.com/sqlserver/2004/07/showplan'
    ),
    ParentQueries AS
    (
        SELECT
            q.query_id AS ParentQueryId
        FROM sys.query_store_query AS q
        WHERE q.object_id =
              OBJECT_ID
              (
                  N'telemetry.usp_PspEqualitySummary_Psp'
              )
    ),
    RelevantPlans AS
    (
        /*
        Dispatcher plans belong to the parent query.
        */

        SELECT
            p.plan_id AS PlanId,
            p.query_id AS QueryId,
            p.plan_type AS PlanType,
            p.plan_type_desc AS PlanTypeDescription,
            CAST(NULL AS bigint) AS VariantQueryId,
            pq.ParentQueryId,
            p.plan_id AS DispatcherPlanId,
            p.query_plan AS QueryPlanText
        FROM ParentQueries AS pq
        INNER JOIN sys.query_store_plan AS p
            ON p.query_id = pq.ParentQueryId
        WHERE p.plan_type = 1

        UNION ALL

        /*
        Variant plans belong to child queries.
        */

        SELECT
            p.plan_id AS PlanId,
            p.query_id AS QueryId,
            p.plan_type AS PlanType,
            p.plan_type_desc AS PlanTypeDescription,
            qv.query_variant_query_id AS VariantQueryId,
            qv.parent_query_id AS ParentQueryId,
            qv.dispatcher_plan_id AS DispatcherPlanId,
            p.query_plan AS QueryPlanText
        FROM ParentQueries AS pq
        INNER JOIN sys.query_store_query_variant AS qv
            ON qv.parent_query_id = pq.ParentQueryId
        INNER JOIN sys.query_store_plan AS p
            ON p.query_id = qv.query_variant_query_id
        WHERE p.plan_type = 2
    ),
    RuntimeData AS
    (
        SELECT
            rs.plan_id AS PlanId,
            SUM(rs.count_executions) AS ExecutionCount,
            MAX(rs.last_execution_time) AS LastExecutionTime,
            CONVERT
            (
                decimal(18,2),
                SUM
                (
                    rs.avg_logical_io_reads
                    * CONVERT(float, rs.count_executions)
                )
                / NULLIF
                  (
                      SUM
                      (
                          CONVERT
                          (
                              float,
                              rs.count_executions
                          )
                      ),
                      0.0
                  )
            ) AS AverageLogicalReads,
            CONVERT
            (
                decimal(18,2),
                SUM
                (
                    rs.avg_cpu_time
                    * CONVERT(float, rs.count_executions)
                )
                / NULLIF
                  (
                      SUM
                      (
                          CONVERT
                          (
                              float,
                              rs.count_executions
                          )
                      ),
                      0.0
                  )
                / 1000.0
            ) AS AverageCpuMilliseconds,
            CONVERT
            (
                decimal(18,2),
                SUM
                (
                    rs.avg_duration
                    * CONVERT(float, rs.count_executions)
                )
                / NULLIF
                  (
                      SUM
                      (
                          CONVERT
                          (
                              float,
                              rs.count_executions
                          )
                      ),
                      0.0
                  )
                / 1000.0
            ) AS AverageDurationMilliseconds
        FROM sys.query_store_runtime_stats AS rs
        WHERE rs.execution_type = 0
        GROUP BY rs.plan_id
    ),
    PlansWithXml AS
    (
        SELECT
            rp.PlanId,
            rp.QueryId,
            rp.PlanType,
            rp.PlanTypeDescription,
            rp.VariantQueryId,
            rp.ParentQueryId,
            rp.DispatcherPlanId,
            TRY_CONVERT(xml, rp.QueryPlanText) AS PlanXml
        FROM RelevantPlans AS rp
    )
    SELECT
        pw.PlanTypeDescription,
        pw.PlanId,
        pw.QueryId,
        pw.VariantQueryId,
        pw.ParentQueryId,
        pw.DispatcherPlanId,
        CASE
            WHEN pw.PlanType = 1
            THEN N'Dispatcher'
            WHEN pw.PlanXml.exist
                 (
                     '//RelOp[@LogicalOp="Key Lookup"]'
                 ) = 1
            THEN N'Index Seek and Key Lookup'
            WHEN pw.PlanXml.exist
                 (
                     '//RelOp
                       [@PhysicalOp="Clustered Index Scan"]'
                 ) = 1
            THEN N'Clustered Index Scan'
            ELSE N'Other'
        END AS PlanSummary,
        CASE
            WHEN pw.PlanType = 1
            THEN pw.PlanXml.value
                 (
                     '(//Dispatcher
                       /ParameterSensitivePredicate
                       /@LowBoundary)[1]',
                     'nvarchar(128)'
                 )
        END AS LowBoundary,
        CASE
            WHEN pw.PlanType = 1
            THEN pw.PlanXml.value
                 (
                     '(//Dispatcher
                       /ParameterSensitivePredicate
                       /@HighBoundary)[1]',
                     'nvarchar(128)'
                 )
        END AS HighBoundary,
        rd.ExecutionCount,
        rd.LastExecutionTime,
        rd.AverageLogicalReads,
        rd.AverageCpuMilliseconds,
        rd.AverageDurationMilliseconds
    FROM PlansWithXml AS pw
    LEFT JOIN RuntimeData AS rd
        ON rd.PlanId = pw.PlanId
    ORDER BY
        pw.PlanType,
        pw.VariantQueryId,
        pw.PlanId;

    ALTER DATABASE FleetTelemetryLab
    SET QUERY_STORE
    (
        QUERY_CAPTURE_MODE = AUTO
    );

    SET @CaptureModeChanged = 0;
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
Result set 6:
Confirm restoration of the original Query Store capture mode.
*/

SELECT
    qso.actual_state_desc AS ActualState,
    qso.query_capture_mode_desc AS FinalCaptureMode
FROM sys.database_query_store_options AS qso;
