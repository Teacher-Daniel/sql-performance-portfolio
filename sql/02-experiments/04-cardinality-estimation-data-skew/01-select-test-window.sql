/*
Experiment 04 - Select a deterministic time window

Purpose:
Compare common and rare EventType counts across candidate intervals.

This script is read-only and does not modify the database.
*/

USE FleetTelemetryLab;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
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

SELECT
    te.EventType,
    SUM
    (
        CASE
            WHEN te.EventTime >= '2024-12-06T00:00:00'
             AND te.EventTime <  '2024-12-07T00:00:00'
            THEN 1
            ELSE 0
        END
    ) AS Count24Hours,
    SUM
    (
        CASE
            WHEN te.EventTime >= '2024-12-06T00:00:00'
             AND te.EventTime <  '2024-12-06T12:00:00'
            THEN 1
            ELSE 0
        END
    ) AS Count12Hours,
    SUM
    (
        CASE
            WHEN te.EventTime >= '2024-12-06T00:00:00'
             AND te.EventTime <  '2024-12-06T06:00:00'
            THEN 1
            ELSE 0
        END
    ) AS Count6Hours,
    SUM
    (
        CASE
            WHEN te.EventTime >= '2024-12-06T00:00:00'
             AND te.EventTime <  '2024-12-06T03:00:00'
            THEN 1
            ELSE 0
        END
    ) AS Count3Hours
FROM telemetry.TelemetryEvent AS te
GROUP BY te.EventType
ORDER BY te.EventType;
GO
