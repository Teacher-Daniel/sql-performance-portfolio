/*
    Experiment 01: Date predicate SARGability
    Step 01: Capture the unoptimized baseline

    This query applies functions directly to EventTime.
    No query-specific performance index should exist yet.
*/

USE [FleetTelemetryLab];
GO

SET NOCOUNT ON;

DECLARE @ExpectedInstance sysname = N'SQL2025LAB';

IF CONVERT(sysname, SERVERPROPERTY('InstanceName')) <> @ExpectedInstance
BEGIN
    THROW 54000,
        'Safety check failed: execute this script only on SQL2025LAB.',
        1;
END;

IF DB_NAME() <> N'FleetTelemetryLab'
BEGIN
    THROW 54001,
        'Safety check failed: the current database must be FleetTelemetryLab.',
        1;
END;

SET STATISTICS IO ON;
SET STATISTICS TIME ON;

PRINT 'Experiment 01 - Non-SARGable date predicate baseline';

/*
    Applying YEAR and MONTH to the indexed candidate column prevents
    SQL Server from using EventTime directly as a seek predicate.
*/
SELECT
    COUNT_BIG(*) AS DecemberEventCount
FROM telemetry.TelemetryEvent
WHERE YEAR(EventTime) = 2024
  AND MONTH(EventTime) = 12;

SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;
GO
