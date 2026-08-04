/*
    Experiment 01: Date predicate SARGability
    Step 03: Compare equivalent date predicates

    Both queries use the same table, index, date interval,
    result aggregation, and execution environment.
*/

USE [FleetTelemetryLab];
GO

SET NOCOUNT ON;

DECLARE @ExpectedInstance sysname = N'SQL2025LAB';

IF CONVERT(sysname, SERVERPROPERTY('InstanceName')) <> @ExpectedInstance
BEGIN
    THROW 54200,
        'Safety check failed: execute this script only on SQL2025LAB.',
        1;
END;

IF DB_NAME() <> N'FleetTelemetryLab'
BEGIN
    THROW 54201,
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
    THROW 54202,
        'The experimental EventTime index does not exist.',
        1;
END;

SET STATISTICS IO ON;
SET STATISTICS TIME ON;

PRINT 'Query A - Non-SARGable predicate';

/*
    EventTime is wrapped in YEAR and MONTH.
    The index cannot be navigated using a continuous key interval.
*/
SELECT
    COUNT_BIG(*) AS DecemberEventCount
FROM telemetry.TelemetryEvent
WHERE YEAR(EventTime) = 2024
  AND MONTH(EventTime) = 12;

PRINT 'Query B - SARGable half-open interval';

/*
    EventTime remains unchanged and is compared with constant bounds.
    The upper limit is exclusive, preserving all possible time values.
*/
SELECT
    COUNT_BIG(*) AS DecemberEventCount
FROM telemetry.TelemetryEvent
WHERE EventTime >= '2024-12-01T00:00:00'
  AND EventTime <  '2025-01-01T00:00:00';

SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;
GO
