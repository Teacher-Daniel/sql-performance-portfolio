/*
Experiment 06 - Cleanup

Purpose:
Remove the experimental DeviceId index and restore TelemetryEvent to
its original index state.

If an index with the experimental name has an unexpected definition,
the script stops instead of deleting it.

This script is safe to execute more than once.
*/

USE FleetTelemetryLab;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO

IF COALESCE
(
    CONVERT(sysname, SERVERPROPERTY(N'InstanceName')),
    N'MSSQLSERVER'
) <> N'SQL2025LAB'
BEGIN
    THROW 51000, 'Safety check failed: execute this script on SQL2025LAB.', 1;
END;
GO

IF DB_NAME() <> N'FleetTelemetryLab'
BEGIN
    THROW 51001, 'Safety check failed: the current database must be FleetTelemetryLab.', 1;
END;
GO

IF OBJECT_ID(N'telemetry.TelemetryEvent', N'U') IS NULL
BEGIN
    THROW 51002, 'The table telemetry.TelemetryEvent does not exist.', 1;
END;
GO

DECLARE @TelemetryEventObjectId int =
    OBJECT_ID(N'telemetry.TelemetryEvent');

DECLARE @ExperimentalIndexName sysname =
    N'IX_TelemetryEvent_DeviceId_JoinExperiment';

DECLARE @ExperimentalIndexId int =
    INDEXPROPERTY
    (
        @TelemetryEventObjectId,
        @ExperimentalIndexName,
        N'IndexID'
    );

DECLARE @IndexExistedBeforeCleanup bit =
    CASE
        WHEN @ExperimentalIndexId IS NOT NULL
        THEN 1
        ELSE 0
    END;

IF @ExperimentalIndexId IS NOT NULL
BEGIN
    IF EXISTS
    (
        SELECT 1
        FROM sys.indexes AS i
        WHERE i.object_id = @TelemetryEventObjectId
          AND i.index_id = @ExperimentalIndexId
          AND
          (
              i.type <> 2
              OR i.is_hypothetical = 1
          )
    )
    BEGIN
        THROW 51003, 'Cleanup aborted: the named index has an unexpected type.', 1;
    END;

    IF NOT EXISTS
    (
        SELECT 1
        FROM sys.index_columns AS ic
        INNER JOIN sys.columns AS c
            ON c.object_id = ic.object_id
           AND c.column_id = ic.column_id
        WHERE ic.object_id = @TelemetryEventObjectId
          AND ic.index_id = @ExperimentalIndexId
          AND c.name = N'DeviceId'
          AND ic.key_ordinal = 1
          AND ic.is_included_column = 0
    )
    OR EXISTS
    (
        SELECT 1
        FROM sys.index_columns AS ic
        INNER JOIN sys.columns AS c
            ON c.object_id = ic.object_id
           AND c.column_id = ic.column_id
        WHERE ic.object_id = @TelemetryEventObjectId
          AND ic.index_id = @ExperimentalIndexId
          AND
          (
              ic.key_ordinal > 0
              OR ic.is_included_column = 1
          )
          AND NOT
          (
              c.name = N'DeviceId'
              AND ic.key_ordinal = 1
              AND ic.is_included_column = 0
          )
    )
    BEGIN
        THROW 51004, 'Cleanup aborted: the named index has an unexpected definition.', 1;
    END;
END;
GO

DECLARE @IndexExistedBeforeCleanup bit =
    CASE
        WHEN EXISTS
        (
            SELECT 1
            FROM sys.indexes AS i
            WHERE i.object_id =
                  OBJECT_ID(N'telemetry.TelemetryEvent')
              AND i.name =
                  N'IX_TelemetryEvent_DeviceId_JoinExperiment'
        )
        THEN 1
        ELSE 0
    END;

DECLARE @CleanupStartedAt datetime2(7) =
    SYSDATETIME();

DROP INDEX IF EXISTS
    IX_TelemetryEvent_DeviceId_JoinExperiment
ON telemetry.TelemetryEvent;

DECLARE @CleanupElapsedMilliseconds bigint =
    DATEDIFF_BIG
    (
        MILLISECOND,
        @CleanupStartedAt,
        SYSDATETIME()
    );

IF EXISTS
(
    SELECT 1
    FROM sys.indexes AS i
    WHERE i.object_id =
          OBJECT_ID(N'telemetry.TelemetryEvent')
      AND i.name =
          N'IX_TelemetryEvent_DeviceId_JoinExperiment'
)
BEGIN
    THROW 51005, 'Cleanup failed: the experimental index still exists.', 1;
END;

DECLARE @RemainingNonclusteredIndexes bigint;

SELECT
    @RemainingNonclusteredIndexes = COUNT_BIG(*)
FROM sys.indexes AS i
WHERE i.object_id =
      OBJECT_ID(N'telemetry.TelemetryEvent')
  AND i.index_id > 1
  AND i.is_hypothetical = 0;

IF @RemainingNonclusteredIndexes <> 0
BEGIN
    THROW 51006, 'Cleanup incomplete: an unexpected nonclustered index remains.', 1;
END;

SELECT
    N'IX_TelemetryEvent_DeviceId_JoinExperiment'
        AS IndexName,
    N'REMOVED' AS IndexStatus,
    @IndexExistedBeforeCleanup
        AS IndexExistedBeforeCleanup,
    @RemainingNonclusteredIndexes
        AS RemainingNonclusteredIndexes,
    @CleanupElapsedMilliseconds
        AS CleanupElapsedMilliseconds;
GO
