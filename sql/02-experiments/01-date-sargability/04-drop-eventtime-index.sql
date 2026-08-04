/*
    Experiment 01: Date predicate SARGability
    Step 04: Remove the experimental index

    This script restores FleetTelemetryLab to its original
    unoptimized baseline after capturing the comparison plans.
*/

USE [FleetTelemetryLab];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @ExpectedInstance sysname = N'SQL2025LAB';
DECLARE @StartedAt datetime2(3) = SYSDATETIME();

IF CONVERT(sysname, SERVERPROPERTY('InstanceName')) <> @ExpectedInstance
BEGIN
    THROW 54300,
        'Safety check failed: execute this script only on SQL2025LAB.',
        1;
END;

IF DB_NAME() <> N'FleetTelemetryLab'
BEGIN
    THROW 54301,
        'Safety check failed: the current database must be FleetTelemetryLab.',
        1;
END;

IF INDEXPROPERTY
(
    OBJECT_ID(N'telemetry.TelemetryEvent'),
    N'IX_TelemetryEvent_EventTime',
    N'IndexID'
) IS NULL
BEGIN
    THROW 54302,
        'The experimental EventTime index does not exist.',
        1;
END;

DROP INDEX IX_TelemetryEvent_EventTime
    ON telemetry.TelemetryEvent;

IF INDEXPROPERTY
(
    OBJECT_ID(N'telemetry.TelemetryEvent'),
    N'IX_TelemetryEvent_EventTime',
    N'IndexID'
) IS NOT NULL
BEGIN
    THROW 54303,
        'The experimental EventTime index was not removed.',
        1;
END;

SELECT
    N'IX_TelemetryEvent_EventTime' AS IndexName,
    N'REMOVED' AS IndexStatus,
    DATEDIFF
    (
        MILLISECOND,
        @StartedAt,
        SYSDATETIME()
    ) AS CleanupElapsedMilliseconds;
GO
