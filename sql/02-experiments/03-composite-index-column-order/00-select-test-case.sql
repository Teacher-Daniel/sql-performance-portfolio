/*
Experiment 03 - Test-case selection

Purpose:
Verify the baseline index state and identify a deterministic DeviceId
for comparing composite-index key order.

This script does not modify the database.
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

IF OBJECT_ID(N'telemetry.TelemetryEvent', N'U') IS NULL
BEGIN
    THROW 51002, 'The table telemetry.TelemetryEvent does not exist.', 1;
END;
GO

DECLARE @StartDate datetime2(0) = '2024-12-01T00:00:00';
DECLARE @EndDate   datetime2(0) = '2025-01-01T00:00:00';

/*
Result set 1:
No experimental or supporting nonclustered indexes should exist.
An empty result is expected.
*/
SELECT
    i.name AS IndexName,
    i.type_desc AS IndexType,
    i.is_unique AS IsUnique,
    i.is_disabled AS IsDisabled
FROM sys.indexes AS i
WHERE i.object_id = OBJECT_ID(N'telemetry.TelemetryEvent')
  AND i.index_id > 1
ORDER BY i.name;

/*
Result set 2:
Review twenty deterministic candidate devices and their December
event distribution.
*/
SELECT
    te.DeviceId,
    COUNT_BIG(*) AS TotalEventCount,
    SUM
    (
        CASE
            WHEN te.EventTime >= @StartDate
             AND te.EventTime <  @EndDate
            THEN 1
            ELSE 0
        END
    ) AS DecemberEventCount,
    MIN
    (
        CASE
            WHEN te.EventTime >= @StartDate
             AND te.EventTime <  @EndDate
            THEN te.EventTime
        END
    ) AS FirstDecemberEventTime,
    MAX
    (
        CASE
            WHEN te.EventTime >= @StartDate
             AND te.EventTime <  @EndDate
            THEN te.EventTime
        END
    ) AS LastDecemberEventTime
FROM telemetry.TelemetryEvent AS te
WHERE te.DeviceId BETWEEN 10000 AND 10019
GROUP BY te.DeviceId
ORDER BY te.DeviceId;

/*
Result set 3:
This is the broad date range that an EventTime-leading index may need
to traverse before applying the DeviceId predicate.
*/
SELECT
    COUNT_BIG(*) AS DecemberTableEventCount
FROM telemetry.TelemetryEvent AS te
WHERE te.EventTime >= @StartDate
  AND te.EventTime <  @EndDate;
GO