/*
    FleetTelemetryLab
    Complete sample database validation

    This script:
      - Makes no data modifications.
      - Validates database configuration.
      - Validates expected row counts.
      - Detects disabled or untrusted constraints.
      - Detects orphaned rows.
      - Validates deterministic data distributions.
      - Returns PASS or FAIL for every check.
*/

USE [FleetTelemetryLab];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @StartedAt datetime2(3) = SYSDATETIME();

DROP TABLE IF EXISTS #ValidationResults;

CREATE TABLE #ValidationResults
(
    ValidationId int IDENTITY(1, 1) NOT NULL,
    Category varchar(30) NOT NULL,
    CheckName varchar(150) NOT NULL,
    ExpectedValue varchar(50) NOT NULL,
    ActualValue varchar(50) NOT NULL,
    Result varchar(4) NOT NULL
);

/*
    Database configuration
*/
INSERT INTO #ValidationResults
(
    Category,
    CheckName,
    ExpectedValue,
    ActualValue,
    Result
)
SELECT
    'Configuration',
    'Current database',
    'FleetTelemetryLab',
    DB_NAME(),
    CASE
        WHEN DB_NAME() = N'FleetTelemetryLab' THEN 'PASS'
        ELSE 'FAIL'
    END

UNION ALL

SELECT
    'Configuration',
    'Compatibility level',
    '170',
    CONVERT(varchar(50), D.compatibility_level),
    CASE
        WHEN D.compatibility_level = 170 THEN 'PASS'
        ELSE 'FAIL'
    END
FROM sys.databases AS D
WHERE D.database_id = DB_ID()

UNION ALL

SELECT
    'Configuration',
    'Recovery model',
    'SIMPLE',
    D.recovery_model_desc,
    CASE
        WHEN D.recovery_model_desc = 'SIMPLE' THEN 'PASS'
        ELSE 'FAIL'
    END
FROM sys.databases AS D
WHERE D.database_id = DB_ID()

UNION ALL

SELECT
    'Configuration',
    'Page verification',
    'CHECKSUM',
    D.page_verify_option_desc,
    CASE
        WHEN D.page_verify_option_desc = 'CHECKSUM' THEN 'PASS'
        ELSE 'FAIL'
    END
FROM sys.databases AS D
WHERE D.database_id = DB_ID()

UNION ALL

SELECT
    'Configuration',
    'Auto close',
    'OFF',
    CASE D.is_auto_close_on WHEN 0 THEN 'OFF' ELSE 'ON' END,
    CASE D.is_auto_close_on WHEN 0 THEN 'PASS' ELSE 'FAIL' END
FROM sys.databases AS D
WHERE D.database_id = DB_ID()

UNION ALL

SELECT
    'Configuration',
    'Auto shrink',
    'OFF',
    CASE D.is_auto_shrink_on WHEN 0 THEN 'OFF' ELSE 'ON' END,
    CASE D.is_auto_shrink_on WHEN 0 THEN 'PASS' ELSE 'FAIL' END
FROM sys.databases AS D
WHERE D.database_id = DB_ID();

INSERT INTO #ValidationResults
(
    Category,
    CheckName,
    ExpectedValue,
    ActualValue,
    Result
)
SELECT
    'Configuration',
    'Query Store state',
    'READ_WRITE',
    actual_state_desc,
    CASE
        WHEN actual_state_desc = 'READ_WRITE' THEN 'PASS'
        ELSE 'FAIL'
    END
FROM sys.database_query_store_options;

/*
    Expected row counts
*/
;WITH ExpectedTables AS
(
    SELECT *
    FROM
    (
        VALUES
            ('crm',       'Customer',       CONVERT(bigint, 20000)),
            ('fleet',     'Vehicle',        CONVERT(bigint, 40000)),
            ('fleet',     'Device',         CONVERT(bigint, 40000)),
            ('insurance', 'Policy',         CONVERT(bigint, 60000)),
            ('telemetry', 'TelemetryEvent', CONVERT(bigint, 1000000)),
            ('telemetry', 'Alert',          CONVERT(bigint, 120000))
    ) AS E(SchemaName, TableName, ExpectedCount)
),
ActualTables AS
(
    SELECT
        S.name AS SchemaName,
        T.name AS TableName,
        SUM(P.row_count) AS ActualCount
    FROM sys.tables AS T
    INNER JOIN sys.schemas AS S
        ON S.schema_id = T.schema_id
    INNER JOIN sys.dm_db_partition_stats AS P
        ON P.object_id = T.object_id
       AND P.index_id IN (0, 1)
    GROUP BY
        S.name,
        T.name
)
INSERT INTO #ValidationResults
(
    Category,
    CheckName,
    ExpectedValue,
    ActualValue,
    Result
)
SELECT
    'Row count',
    E.SchemaName + '.' + E.TableName,
    CONVERT(varchar(50), E.ExpectedCount),
    COALESCE(CONVERT(varchar(50), A.ActualCount), '<missing>'),
    CASE
        WHEN A.ActualCount = E.ExpectedCount THEN 'PASS'
        ELSE 'FAIL'
    END
FROM ExpectedTables AS E
LEFT JOIN ActualTables AS A
    ON A.SchemaName = E.SchemaName
   AND A.TableName = E.TableName;

/*
    Constraint state
*/
INSERT INTO #ValidationResults
(
    Category,
    CheckName,
    ExpectedValue,
    ActualValue,
    Result
)
SELECT
    'Integrity',
    'Disabled or untrusted foreign keys',
    '0',
    CONVERT(varchar(50), COUNT_BIG(*)),
    CASE
        WHEN COUNT_BIG(*) = 0 THEN 'PASS'
        ELSE 'FAIL'
    END
FROM sys.foreign_keys
WHERE is_disabled = 1
   OR is_not_trusted = 1;

INSERT INTO #ValidationResults
(
    Category,
    CheckName,
    ExpectedValue,
    ActualValue,
    Result
)
SELECT
    'Integrity',
    'Disabled or untrusted check constraints',
    '0',
    CONVERT(varchar(50), COUNT_BIG(*)),
    CASE
        WHEN COUNT_BIG(*) = 0 THEN 'PASS'
        ELSE 'FAIL'
    END
FROM sys.check_constraints
WHERE is_disabled = 1
   OR is_not_trusted = 1;

/*
    Orphan detection
*/
INSERT INTO #ValidationResults
SELECT
    'Integrity',
    'Vehicles without a customer',
    '0',
    CONVERT(varchar(50), COUNT_BIG(*)),
    CASE WHEN COUNT_BIG(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM fleet.Vehicle AS V
LEFT JOIN crm.Customer AS C
    ON C.CustomerId = V.CustomerId
WHERE C.CustomerId IS NULL;

INSERT INTO #ValidationResults
SELECT
    'Integrity',
    'Devices without a vehicle',
    '0',
    CONVERT(varchar(50), COUNT_BIG(*)),
    CASE WHEN COUNT_BIG(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM fleet.Device AS D
LEFT JOIN fleet.Vehicle AS V
    ON V.VehicleId = D.VehicleId
WHERE V.VehicleId IS NULL;

INSERT INTO #ValidationResults
SELECT
    'Integrity',
    'Policies without a vehicle',
    '0',
    CONVERT(varchar(50), COUNT_BIG(*)),
    CASE WHEN COUNT_BIG(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM insurance.Policy AS P
LEFT JOIN fleet.Vehicle AS V
    ON V.VehicleId = P.VehicleId
WHERE V.VehicleId IS NULL;

INSERT INTO #ValidationResults
SELECT
    'Integrity',
    'Events without a device',
    '0',
    CONVERT(varchar(50), COUNT_BIG(*)),
    CASE WHEN COUNT_BIG(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM telemetry.TelemetryEvent AS T
LEFT JOIN fleet.Device AS D
    ON D.DeviceId = T.DeviceId
WHERE D.DeviceId IS NULL;

INSERT INTO #ValidationResults
SELECT
    'Integrity',
    'Alerts without an event',
    '0',
    CONVERT(varchar(50), COUNT_BIG(*)),
    CASE WHEN COUNT_BIG(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM telemetry.Alert AS A
LEFT JOIN telemetry.TelemetryEvent AS T
    ON T.TelemetryEventId = A.TelemetryEventId
WHERE T.TelemetryEventId IS NULL;

/*
    Events per device
*/
DROP TABLE IF EXISTS #DeviceEventCounts;

SELECT
    DeviceId,
    COUNT_BIG(*) AS EventCount
INTO #DeviceEventCounts
FROM telemetry.TelemetryEvent
GROUP BY DeviceId;

CREATE UNIQUE CLUSTERED INDEX CX_DeviceEventCounts
    ON #DeviceEventCounts (DeviceId);

DECLARE @DevicesWithEvents bigint;
DECLARE @MinimumEventsPerDevice bigint;
DECLARE @MaximumEventsPerDevice bigint;

SELECT
    @DevicesWithEvents = COUNT_BIG(*),
    @MinimumEventsPerDevice = MIN(EventCount),
    @MaximumEventsPerDevice = MAX(EventCount)
FROM #DeviceEventCounts;

INSERT INTO #ValidationResults
VALUES
(
    'Distribution',
    'Devices represented in telemetry',
    '40000',
    CONVERT(varchar(50), @DevicesWithEvents),
    CASE WHEN @DevicesWithEvents = 40000 THEN 'PASS' ELSE 'FAIL' END
),
(
    'Distribution',
    'Minimum events per device',
    '25',
    CONVERT(varchar(50), @MinimumEventsPerDevice),
    CASE WHEN @MinimumEventsPerDevice = 25 THEN 'PASS' ELSE 'FAIL' END
),
(
    'Distribution',
    'Maximum events per device',
    '25',
    CONVERT(varchar(50), @MaximumEventsPerDevice),
    CASE WHEN @MaximumEventsPerDevice = 25 THEN 'PASS' ELSE 'FAIL' END
);

/*
    Telemetry event type distribution
*/
DECLARE @ExpectedEventTypes TABLE
(
    EventType tinyint PRIMARY KEY,
    ExpectedCount bigint NOT NULL
);

INSERT INTO @ExpectedEventTypes
VALUES
    (1, 720000),
    (2, 100000),
    (3,  80000),
    (4,  60000),
    (5,  40000);

;WITH ActualEventTypes AS
(
    SELECT
        EventType,
        COUNT_BIG(*) AS ActualCount
    FROM telemetry.TelemetryEvent
    GROUP BY EventType
)
INSERT INTO #ValidationResults
SELECT
    'Distribution',
    'Telemetry EventType ' + CONVERT(varchar(10), E.EventType),
    CONVERT(varchar(50), E.ExpectedCount),
    COALESCE(CONVERT(varchar(50), A.ActualCount), '0'),
    CASE
        WHEN COALESCE(A.ActualCount, 0) = E.ExpectedCount THEN 'PASS'
        ELSE 'FAIL'
    END
FROM @ExpectedEventTypes AS E
LEFT JOIN ActualEventTypes AS A
    ON A.EventType = E.EventType;

/*
    Alert type distribution
*/
DECLARE @ExpectedAlertTypes TABLE
(
    AlertType tinyint PRIMARY KEY,
    ExpectedCount bigint NOT NULL
);

INSERT INTO @ExpectedAlertTypes
VALUES
    (1, 36000),
    (2, 30000),
    (3, 21600),
    (4, 14400),
    (5, 12000),
    (6,  6000);

;WITH ActualAlertTypes AS
(
    SELECT
        AlertType,
        COUNT_BIG(*) AS ActualCount
    FROM telemetry.Alert
    GROUP BY AlertType
)
INSERT INTO #ValidationResults
SELECT
    'Distribution',
    'Alert AlertType ' + CONVERT(varchar(10), E.AlertType),
    CONVERT(varchar(50), E.ExpectedCount),
    COALESCE(CONVERT(varchar(50), A.ActualCount), '0'),
    CASE
        WHEN COALESCE(A.ActualCount, 0) = E.ExpectedCount THEN 'PASS'
        ELSE 'FAIL'
    END
FROM @ExpectedAlertTypes AS E
LEFT JOIN ActualAlertTypes AS A
    ON A.AlertType = E.AlertType;

/*
    Alert status distribution
*/
DECLARE @ExpectedAlertStatuses TABLE
(
    AlertStatus char(1) PRIMARY KEY,
    ExpectedCount bigint NOT NULL
);

INSERT INTO @ExpectedAlertStatuses
VALUES
    ('C', 84000),
    ('O', 24000),
    ('E', 12000);

;WITH ActualAlertStatuses AS
(
    SELECT
        AlertStatus,
        COUNT_BIG(*) AS ActualCount
    FROM telemetry.Alert
    GROUP BY AlertStatus
)
INSERT INTO #ValidationResults
SELECT
    'Distribution',
    'Alert status ' + E.AlertStatus,
    CONVERT(varchar(50), E.ExpectedCount),
    COALESCE(CONVERT(varchar(50), A.ActualCount), '0'),
    CASE
        WHEN COALESCE(A.ActualCount, 0) = E.ExpectedCount THEN 'PASS'
        ELSE 'FAIL'
    END
FROM @ExpectedAlertStatuses AS E
LEFT JOIN ActualAlertStatuses AS A
    ON A.AlertStatus = E.AlertStatus;

/*
    Alert severity distribution
*/
DECLARE @ExpectedSeverities TABLE
(
    Severity tinyint PRIMARY KEY,
    ExpectedCount bigint NOT NULL
);

INSERT INTO @ExpectedSeverities
VALUES
    (1, 84000),
    (2, 30000),
    (3,  6000);

;WITH ActualSeverities AS
(
    SELECT
        Severity,
        COUNT_BIG(*) AS ActualCount
    FROM telemetry.Alert
    GROUP BY Severity
)
INSERT INTO #ValidationResults
SELECT
    'Distribution',
    'Alert severity ' + CONVERT(varchar(10), E.Severity),
    CONVERT(varchar(50), E.ExpectedCount),
    COALESCE(CONVERT(varchar(50), A.ActualCount), '0'),
    CASE
        WHEN COALESCE(A.ActualCount, 0) = E.ExpectedCount THEN 'PASS'
        ELSE 'FAIL'
    END
FROM @ExpectedSeverities AS E
LEFT JOIN ActualSeverities AS A
    ON A.Severity = E.Severity;

/*
    Additional logical validations
*/
INSERT INTO #ValidationResults
SELECT
    'Data quality',
    'Events received before event time',
    '0',
    CONVERT(varchar(50), COUNT_BIG(*)),
    CASE WHEN COUNT_BIG(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM telemetry.TelemetryEvent
WHERE ReceivedAt < EventTime;

INSERT INTO #ValidationResults
SELECT
    'Data quality',
    'Movement with ignition off',
    '0',
    CONVERT(varchar(50), COUNT_BIG(*)),
    CASE WHEN COUNT_BIG(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM telemetry.TelemetryEvent
WHERE IgnitionOn = 0
  AND SpeedKph > 0;

INSERT INTO #ValidationResults
SELECT
    'Data quality',
    'Events delayed by at least one hour',
    '20000',
    CONVERT(varchar(50), COUNT_BIG(*)),
    CASE WHEN COUNT_BIG(*) = 20000 THEN 'PASS' ELSE 'FAIL' END
FROM telemetry.TelemetryEvent
WHERE DATEDIFF(SECOND, EventTime, ReceivedAt) >= 3600;

INSERT INTO #ValidationResults
SELECT
    'Data quality',
    'Alerts with inconsistent resolution state',
    '0',
    CONVERT(varchar(50), COUNT_BIG(*)),
    CASE WHEN COUNT_BIG(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM telemetry.Alert
WHERE
    (
        AlertStatus = 'C'
        AND
        (
            ResolvedAt IS NULL
            OR ResolutionCode IS NULL
        )
    )
    OR
    (
        AlertStatus <> 'C'
        AND
        (
            ResolvedAt IS NOT NULL
            OR ResolutionCode IS NOT NULL
        )
    );

INSERT INTO #ValidationResults
SELECT
    'Data quality',
    'Distinct events represented by alerts',
    '120000',
    CONVERT(varchar(50), COUNT_BIG(*)),
    CASE WHEN COUNT_BIG(*) = 120000 THEN 'PASS' ELSE 'FAIL' END
FROM
(
    SELECT DISTINCT TelemetryEventId
    FROM telemetry.Alert
) AS DistinctAlertEvents;

/*
    Final results
*/
DECLARE @TotalChecks int;
DECLARE @PassedChecks int;
DECLARE @FailedChecks int;

SELECT
    @TotalChecks = COUNT(*),
    @PassedChecks = SUM(CASE WHEN Result = 'PASS' THEN 1 ELSE 0 END),
    @FailedChecks = SUM(CASE WHEN Result = 'FAIL' THEN 1 ELSE 0 END)
FROM #ValidationResults;

SELECT
    @TotalChecks AS TotalChecks,
    @PassedChecks AS PassedChecks,
    @FailedChecks AS FailedChecks,
    CASE
        WHEN @FailedChecks = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS OverallResult;

SELECT
    ValidationId,
    Category,
    CheckName,
    ExpectedValue,
    ActualValue,
    Result
FROM #ValidationResults
ORDER BY
    CASE WHEN Result = 'FAIL' THEN 0 ELSE 1 END,
    ValidationId;

SELECT
    S.name AS SchemaName,
    T.name AS TableName,
    SUM(P.row_count) AS [RowCount],
    CONVERT
    (
        decimal(12, 2),
        SUM(P.reserved_page_count) * 8.0 / 1024.0
    ) AS ReservedSpaceMB,
    CONVERT
    (
        decimal(12, 2),
        SUM(P.used_page_count) * 8.0 / 1024.0
    ) AS UsedSpaceMB
FROM sys.tables AS T
INNER JOIN sys.schemas AS S
    ON S.schema_id = T.schema_id
INNER JOIN sys.dm_db_partition_stats AS P
    ON P.object_id = T.object_id
   AND P.index_id IN (0, 1)
WHERE S.name IN
(
    N'crm',
    N'fleet',
    N'insurance',
    N'telemetry'
)
GROUP BY
    S.name,
    T.name
ORDER BY
    S.name,
    T.name;

SELECT
    DATEDIFF
    (
        MILLISECOND,
        @StartedAt,
        SYSDATETIME()
    ) AS ValidationElapsedMilliseconds;

IF @FailedChecks > 0
BEGIN
    THROW 53000,
        'FleetTelemetryLab validation failed. Review the FAIL results.',
        1;
END;

PRINT 'FleetTelemetryLab validation completed successfully.';
GO
