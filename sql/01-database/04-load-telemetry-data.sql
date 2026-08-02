/*
    FleetTelemetryLab
    Telemetry event and alert data loader

    Target rows:
      - 1,000,000 telemetry events
      -   120,000 alerts

    Characteristics:
      - Deterministic and reproducible data
      - 25 events per device
      - Geographic coordinates based on customer country
      - Controlled event, alert, severity, and status distributions
      - No performance-tuning indexes are created here
*/

USE [FleetTelemetryLab];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @ExpectedInstance sysname = N'SQL2025LAB';
DECLARE @CustomerCount int = 20000;
DECLARE @VehicleCount int = 40000;
DECLARE @DeviceCount int = 40000;
DECLARE @PolicyCount int = 60000;
DECLARE @EventCount int = 1000000;
DECLARE @AlertCount int = 120000;
DECLARE @AnchorDate datetime2(0) = '2025-01-01T00:00:00';
DECLARE @StartedAt datetime2(3) = SYSDATETIME();
DECLARE @FirstEventId bigint;
DECLARE @LastEventId bigint;

IF CONVERT(sysname, SERVERPROPERTY('InstanceName')) <> @ExpectedInstance
BEGIN
    THROW 52000,
        'Safety check failed: execute this script only on SQL2025LAB.',
        1;
END;

IF DB_NAME() <> N'FleetTelemetryLab'
BEGIN
    THROW 52001,
        'Safety check failed: the current database must be FleetTelemetryLab.',
        1;
END;

IF OBJECT_ID(N'telemetry.TelemetryEvent', N'U') IS NULL
   OR OBJECT_ID(N'telemetry.Alert', N'U') IS NULL
BEGIN
    THROW 52002,
        'The expected telemetry tables do not exist.',
        1;
END;

IF (SELECT COUNT_BIG(*) FROM crm.Customer) <> @CustomerCount
BEGIN
    THROW 52003, 'Unexpected Customer row count.', 1;
END;

IF (SELECT COUNT_BIG(*) FROM fleet.Vehicle) <> @VehicleCount
BEGIN
    THROW 52004, 'Unexpected Vehicle row count.', 1;
END;

IF (SELECT COUNT_BIG(*) FROM fleet.Device) <> @DeviceCount
BEGIN
    THROW 52005, 'Unexpected Device row count.', 1;
END;

IF (SELECT COUNT_BIG(*) FROM insurance.Policy) <> @PolicyCount
BEGIN
    THROW 52006, 'Unexpected Policy row count.', 1;
END;

IF EXISTS (SELECT 1 FROM telemetry.TelemetryEvent)
   OR EXISTS (SELECT 1 FROM telemetry.Alert)
BEGIN
    THROW 52007,
        'Telemetry data already exists. This script will not overwrite it.',
        1;
END;

/*
    Generate the integers from 1 through 1,000,000.

    Six decimal digits produce exactly one million combinations.
    This avoids relying on the number of objects in system catalogs.
*/
DROP TABLE IF EXISTS #Numbers;

;WITH Digits AS
(
    SELECT Digit
    FROM
    (
        VALUES
            (0), (1), (2), (3), (4),
            (5), (6), (7), (8), (9)
    ) AS D(Digit)
)
SELECT
    CONVERT
    (
        int,
        1
        + D0.Digit
        + (D1.Digit * 10)
        + (D2.Digit * 100)
        + (D3.Digit * 1000)
        + (D4.Digit * 10000)
        + (D5.Digit * 100000)
    ) AS Number
INTO #Numbers
FROM Digits AS D0
CROSS JOIN Digits AS D1
CROSS JOIN Digits AS D2
CROSS JOIN Digits AS D3
CROSS JOIN Digits AS D4
CROSS JOIN Digits AS D5;

CREATE UNIQUE CLUSTERED INDEX CX_Numbers
    ON #Numbers (Number);

IF (SELECT COUNT_BIG(*) FROM #Numbers) <> @EventCount
BEGIN
    THROW 52008,
        'The temporary number generator did not produce 1,000,000 rows.',
        1;
END;

BEGIN TRY
    BEGIN TRANSACTION;

    /*
        Telemetry events

        Each of the 40,000 devices receives 25 events distributed
        across approximately 25 weeks.

        Event type distribution:
          1: 72%
          2: 10%
          3:  8%
          4:  6%
          5:  4%

        Approximately 2% of events have a delayed reception time.
    */
    INSERT INTO telemetry.TelemetryEvent WITH (TABLOCK)
    (
        DeviceId,
        EventTime,
        ReceivedAt,
        EventType,
        Latitude,
        Longitude,
        SpeedKph,
        IgnitionOn,
        OdometerKm,
        BatteryVoltage,
        PayloadBytes
    )
    SELECT
        D.DeviceId,
        EventDates.EventTime,
        DATEADD
        (
            SECOND,
            CASE
                WHEN Scores.DelayScore < 98
                    THEN N.Number % 121
                ELSE 3600 + (N.Number % 7201)
            END,
            EventDates.EventTime
        ),
        CONVERT
        (
            tinyint,
            CASE
                WHEN Scores.EventTypeScore < 72 THEN 1
                WHEN Scores.EventTypeScore < 82 THEN 2
                WHEN Scores.EventTypeScore < 90 THEN 3
                WHEN Scores.EventTypeScore < 96 THEN 4
                ELSE 5
            END
        ),
        CONVERT
        (
            decimal(9, 6),
            Locations.BaseLatitude
            +
            (
                (
                    (Assignment.DeviceNumber * 37)
                    + (Assignment.EventSequence * 101)
                ) % 10000
            ) / 100000.0
        ),
        CONVERT
        (
            decimal(9, 6),
            Locations.BaseLongitude
            +
            (
                (
                    (Assignment.DeviceNumber * 29)
                    + (Assignment.EventSequence * 67)
                ) % 10000
            ) / 100000.0
        ),
        CONVERT
        (
            smallint,
            CASE
                WHEN EventProperties.IgnitionOn = 0 THEN 0
                ELSE
                    (
                        (Assignment.DeviceNumber * 7)
                        + (Assignment.EventSequence * 13)
                        + (N.Number % 181)
                    ) % 181
            END
        ),
        CONVERT(bit, EventProperties.IgnitionOn),
        CONVERT
        (
            int,
            1000
            + (Assignment.DeviceNumber * 5)
            + ((24 - Assignment.EventSequence) * 300)
            + (N.Number % 100)
        ),
        CONVERT
        (
            decimal(4, 2),
            11.50 + ((N.Number % 350) / 100.0)
        ),
        CONVERT
        (
            smallint,
            CASE
                WHEN Scores.EventTypeScore >= 96
                    THEN 4000 + (N.Number % 4001)
                ELSE 200 + (N.Number % 1801)
            END
        )
    FROM #Numbers AS N
    CROSS APPLY
    (
        VALUES
        (
            1 + ((N.Number - 1) % @DeviceCount),
            (N.Number - 1) / @DeviceCount
        )
    ) AS Assignment(DeviceNumber, EventSequence)
    INNER JOIN fleet.Device AS D
        ON D.DeviceSerial =
            'DVC'
            + RIGHT
            (
                '000000000000'
                    + CONVERT(varchar(12), Assignment.DeviceNumber),
                12
            )
    INNER JOIN fleet.Vehicle AS V
        ON V.VehicleId = D.VehicleId
    INNER JOIN crm.Customer AS C
        ON C.CustomerId = V.CustomerId
    CROSS APPLY
    (
        VALUES
        (
            (
                (N.Number % 100)
                + (((N.Number - 1) / 100) * 31)
            ) % 100,
            (
                (N.Number % 100)
                + (((N.Number - 1) / 100) * 17)
            ) % 100,
            (
                (N.Number % 100)
                + (((N.Number - 1) / 100) * 43)
            ) % 100
        )
    ) AS Scores(EventTypeScore, IgnitionScore, DelayScore)
    CROSS APPLY
    (
        VALUES
        (
            CASE
                WHEN Scores.IgnitionScore < 12 THEN 0
                ELSE 1
            END
        )
    ) AS EventProperties(IgnitionOn)
    CROSS APPLY
    (
        VALUES
        (
            CASE C.CountryCode
                WHEN 'MX' THEN 19.432600
                WHEN 'CO' THEN 4.711000
                WHEN 'AR' THEN -34.603700
                WHEN 'CL' THEN -33.448900
                WHEN 'PE' THEN -12.046400
            END,
            CASE C.CountryCode
                WHEN 'MX' THEN -99.133200
                WHEN 'CO' THEN -74.072100
                WHEN 'AR' THEN -58.381600
                WHEN 'CL' THEN -70.669300
                WHEN 'PE' THEN -77.042800
            END
        )
    ) AS Locations(BaseLatitude, BaseLongitude)
    CROSS APPLY
    (
        VALUES
        (
            DATEADD
            (
                SECOND,
                -CONVERT
                (
                    int,
                    (Assignment.EventSequence * 604800)
                    + ((Assignment.DeviceNumber * 97) % 604800)
                ),
                @AnchorDate
            )
        )
    ) AS EventDates(EventTime)
    OPTION (MAXDOP 2);

    IF (SELECT COUNT_BIG(*) FROM telemetry.TelemetryEvent) <> @EventCount
    BEGIN
        THROW 52010,
            'Unexpected TelemetryEvent row count.',
            1;
    END;

    SELECT
        @FirstEventId = MIN(TelemetryEventId),
        @LastEventId = MAX(TelemetryEventId)
    FROM telemetry.TelemetryEvent;

    /*
        Confirm that the successful batch generated a contiguous
        identity interval. The initial identity value is not assumed.
    */
    IF (@LastEventId - @FirstEventId + 1) <> @EventCount
    BEGIN
        THROW 52011,
            'TelemetryEvent identity values are not contiguous.',
            1;
    END;

    /*
        Alerts

        A modular permutation distributes 120,000 alerts across the
        complete TelemetryEvent identity interval.

        Alert type distribution:
          1: 30%
          2: 25%
          3: 18%
          4: 12%
          5: 10%
          6:  5%

        Status distribution:
          C: 70% closed
          O: 20% open
          E: 10% escalated

        Severity distribution:
          1: 70%
          2: 25%
          3:  5%
    */
    INSERT INTO telemetry.Alert WITH (TABLOCK)
    (
        TelemetryEventId,
        AlertType,
        Severity,
        AlertStatus,
        CreatedAt,
        ResolvedAt,
        ResolutionCode
    )
    SELECT
        T.TelemetryEventId,
        CONVERT
        (
            tinyint,
            CASE
                WHEN Scores.AlertTypeScore < 30 THEN 1
                WHEN Scores.AlertTypeScore < 55 THEN 2
                WHEN Scores.AlertTypeScore < 73 THEN 3
                WHEN Scores.AlertTypeScore < 85 THEN 4
                WHEN Scores.AlertTypeScore < 95 THEN 5
                ELSE 6
            END
        ),
        CONVERT
        (
            tinyint,
            CASE
                WHEN Scores.SeverityScore < 70 THEN 1
                WHEN Scores.SeverityScore < 95 THEN 2
                ELSE 3
            END
        ),
        AlertProperties.AlertStatus,
        AlertDates.CreatedAt,
        CASE
            WHEN AlertProperties.AlertStatus = 'C'
                THEN DATEADD
                (
                    MINUTE,
                    5 + (N.Number % 1440),
                    AlertDates.CreatedAt
                )
            ELSE NULL
        END,
        CASE
            WHEN AlertProperties.AlertStatus <> 'C' THEN NULL
            WHEN N.Number % 3 = 0 THEN 'AUTO_RESOLVED'
            WHEN N.Number % 3 = 1 THEN 'OPERATOR_CONFIRMED'
            ELSE 'FALSE_POSITIVE'
        END
    FROM #Numbers AS N
    CROSS APPLY
    (
        VALUES
        (
            @FirstEventId
            +
            (
                (
                    CONVERT(bigint, N.Number) * 7919
                ) % @EventCount
            )
        )
    ) AS EventAssignment(TelemetryEventId)
    INNER JOIN telemetry.TelemetryEvent AS T
        ON T.TelemetryEventId = EventAssignment.TelemetryEventId
    CROSS APPLY
    (
        VALUES
        (
            (
                (N.Number % 100)
                + (((N.Number - 1) / 100) * 19)
            ) % 100,
            (
                (N.Number % 100)
                + (((N.Number - 1) / 100) * 37)
            ) % 100,
            (
                (N.Number % 100)
                + (((N.Number - 1) / 100) * 53)
            ) % 100
        )
    ) AS Scores(AlertTypeScore, SeverityScore, StatusScore)
    CROSS APPLY
    (
        VALUES
        (
            CASE
                WHEN Scores.StatusScore < 70 THEN 'C'
                WHEN Scores.StatusScore < 90 THEN 'O'
                ELSE 'E'
            END
        )
    ) AS AlertProperties(AlertStatus)
    CROSS APPLY
    (
        VALUES
        (
            DATEADD
            (
                SECOND,
                30 + (N.Number % 271),
                T.ReceivedAt
            )
        )
    ) AS AlertDates(CreatedAt)
    WHERE N.Number <= @AlertCount
    OPTION (MAXDOP 2);

    IF (SELECT COUNT_BIG(*) FROM telemetry.Alert) <> @AlertCount
    BEGIN
        THROW 52012,
            'Unexpected Alert row count.',
            1;
    END;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;

/*
    Validation results
*/
SELECT
    N'telemetry' AS SchemaName,
    N'TelemetryEvent' AS TableName,
    COUNT_BIG(*) AS [RowCount]
FROM telemetry.TelemetryEvent

UNION ALL

SELECT
    N'telemetry',
    N'Alert',
    COUNT_BIG(*)
FROM telemetry.Alert;

SELECT
    EventType,
    COUNT_BIG(*) AS EventCount
FROM telemetry.TelemetryEvent
GROUP BY EventType
ORDER BY EventType;

SELECT
    MIN(EventTime) AS EarliestEventTime,
    MAX(EventTime) AS LatestEventTime,
    MIN(ReceivedAt) AS EarliestReceivedAt,
    MAX(ReceivedAt) AS LatestReceivedAt,
    SUM
    (
        CONVERT
        (
            bigint,
            CASE
                WHEN DATEDIFF
                (
                    SECOND,
                    EventTime,
                    ReceivedAt
                ) >= 3600
                    THEN 1
                ELSE 0
            END
        )
    ) AS DelayedEventCount
FROM telemetry.TelemetryEvent;

SELECT
    MIN(Latitude) AS MinimumLatitude,
    MAX(Latitude) AS MaximumLatitude,
    MIN(Longitude) AS MinimumLongitude,
    MAX(Longitude) AS MaximumLongitude,
    MIN(SpeedKph) AS MinimumSpeedKph,
    MAX(SpeedKph) AS MaximumSpeedKph,
    MIN(OdometerKm) AS MinimumOdometerKm,
    MAX(OdometerKm) AS MaximumOdometerKm,
    MIN(BatteryVoltage) AS MinimumBatteryVoltage,
    MAX(BatteryVoltage) AS MaximumBatteryVoltage,
    MIN(PayloadBytes) AS MinimumPayloadBytes,
    MAX(PayloadBytes) AS MaximumPayloadBytes
FROM telemetry.TelemetryEvent;

SELECT
    AlertType,
    COUNT_BIG(*) AS AlertCount
FROM telemetry.Alert
GROUP BY AlertType
ORDER BY AlertType;

SELECT
    AlertStatus,
    COUNT_BIG(*) AS AlertCount
FROM telemetry.Alert
GROUP BY AlertStatus
ORDER BY AlertStatus;

SELECT
    Severity,
    COUNT_BIG(*) AS AlertCount
FROM telemetry.Alert
GROUP BY Severity
ORDER BY Severity;

SELECT
    DATEDIFF
    (
        MILLISECOND,
        @StartedAt,
        SYSDATETIME()
    ) AS TotalElapsedMilliseconds;
GO
