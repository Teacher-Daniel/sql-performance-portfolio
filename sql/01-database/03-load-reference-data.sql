/*
    FleetTelemetryLab
    Reference data loader

    Target rows:
      - 20,000 customers
      - 40,000 vehicles
      - 40,000 devices
      - 60,000 policies

    Characteristics:
      - Deterministic and reproducible data
      - Set-based generation
      - No proprietary or personally identifiable information
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
DECLARE @AnchorDate datetime2(0) = '2025-01-01T00:00:00';
DECLARE @StartedAt datetime2(3) = SYSDATETIME();

IF CONVERT(sysname, SERVERPROPERTY('InstanceName')) <> @ExpectedInstance
BEGIN
    THROW 51000,
        'Safety check failed: execute this script only on the SQL2025LAB instance.',
        1;
END;

IF DB_NAME() <> N'FleetTelemetryLab'
BEGIN
    THROW 51001,
        'Safety check failed: the current database must be FleetTelemetryLab.',
        1;
END;

IF OBJECT_ID(N'crm.Customer', N'U') IS NULL
   OR OBJECT_ID(N'fleet.Vehicle', N'U') IS NULL
   OR OBJECT_ID(N'fleet.Device', N'U') IS NULL
   OR OBJECT_ID(N'insurance.Policy', N'U') IS NULL
   OR OBJECT_ID(N'telemetry.TelemetryEvent', N'U') IS NULL
   OR OBJECT_ID(N'telemetry.Alert', N'U') IS NULL
BEGIN
    THROW 51002,
        'The expected FleetTelemetryLab schema is incomplete.',
        1;
END;

IF EXISTS (SELECT 1 FROM crm.Customer)
   OR EXISTS (SELECT 1 FROM fleet.Vehicle)
   OR EXISTS (SELECT 1 FROM fleet.Device)
   OR EXISTS (SELECT 1 FROM insurance.Policy)
   OR EXISTS (SELECT 1 FROM telemetry.TelemetryEvent)
   OR EXISTS (SELECT 1 FROM telemetry.Alert)
BEGIN
    THROW 51003,
        'The database already contains data. This script will not overwrite it.',
        1;
END;

/*
    Create a reusable sequence from 1 to 60,000.

    sys.all_objects is used only as a source of rows. The resulting values
    are independent of object names and are stored in a temporary table.
*/
DROP TABLE IF EXISTS #Numbers;

;WITH NumberSource AS
(
    SELECT TOP (@PolicyCount)
        ROW_NUMBER() OVER
        (
            ORDER BY A.object_id, B.object_id
        ) AS Number
    FROM sys.all_objects AS A
    CROSS JOIN sys.all_objects AS B
)
SELECT
    CONVERT(int, Number) AS Number
INTO #Numbers
FROM NumberSource;

CREATE UNIQUE CLUSTERED INDEX CX_Numbers
    ON #Numbers (Number);

BEGIN TRY
    BEGIN TRANSACTION;

    /*
        Customers

        Distribution:
          - 85% personal customers
          - 15% business customers
          - Approximately 97% active
          - Geographic distribution weighted toward Mexico
    */
    INSERT INTO crm.Customer
    (
        CustomerCode,
        DisplayName,
        CountryCode,
        CustomerType,
        Status,
        CreatedAt
    )
    SELECT
        'C' + RIGHT
        (
            '000000000' + CONVERT(varchar(9), N.Number),
            9
        ),
        N'Cliente sintético ' + CONVERT(nvarchar(10), N.Number),
        CASE
            WHEN N.Number % 100 < 60 THEN 'MX'
            WHEN N.Number % 100 < 72 THEN 'CO'
            WHEN N.Number % 100 < 82 THEN 'AR'
            WHEN N.Number % 100 < 92 THEN 'CL'
            ELSE 'PE'
        END,
        CASE
            WHEN N.Number <= 17000 THEN 'P'
            ELSE 'B'
        END,
        CASE
            WHEN ((N.Number % 100) + (((N.Number - 1) / 100) * 17)) % 100 < 97 THEN 'A'
            ELSE 'I'
        END,
        DATEADD
        (
            DAY,
            -(N.Number % 1825),
            @AnchorDate
        )
    FROM #Numbers AS N
    WHERE N.Number <= @CustomerCount;

    /*
        Vehicles

        Every customer receives at least one vehicle. The additional
        20,000 vehicles are concentrated among business customers,
        creating a realistic uneven distribution.
    */
    INSERT INTO fleet.Vehicle
    (
        CustomerId,
        VIN,
        PlateNumber,
        ModelYear,
        VehicleType,
        Status,
        CreatedAt
    )
    SELECT
        C.CustomerId,
        '1FT' + RIGHT
        (
            '00000000000000' + CONVERT(varchar(14), N.Number),
            14
        ),
        'P' + RIGHT
        (
            '0000000' + CONVERT(varchar(7), N.Number),
            7
        ),
        CONVERT(smallint, 2008 + (N.Number % 18)),
        CASE N.Number % 10
            WHEN 0 THEN 'T'
            WHEN 1 THEN 'S'
            WHEN 2 THEN 'V'
            ELSE 'C'
        END,
        CASE
            WHEN ((N.Number % 100) + (((N.Number - 1) / 100) * 23)) % 100 < 94 THEN 'A'
            WHEN ((N.Number % 100) + (((N.Number - 1) / 100) * 23)) % 100 < 98 THEN 'S'
            ELSE 'I'
        END,
        DATEADD
        (
            DAY,
            -(N.Number % 1460),
            @AnchorDate
        )
    FROM #Numbers AS N
    CROSS APPLY
    (
        VALUES
        (
            CASE
                WHEN N.Number <= @CustomerCount
                    THEN N.Number
                ELSE 17001 + ((N.Number - 20001) % 3000)
            END
        )
    ) AS Assignment(CustomerNumber)
    INNER JOIN crm.Customer AS C
        ON C.CustomerCode =
            'C' + RIGHT
            (
                '000000000'
                    + CONVERT(varchar(9), Assignment.CustomerNumber),
                9
            )
    WHERE N.Number <= @VehicleCount;

    /*
        Devices

        Each vehicle receives one unique telematics device.
        Most devices remain active, while a small percentage
        is suspended or inactive.
    */
    INSERT INTO fleet.Device
    (
        VehicleId,
        DeviceSerial,
        ActivatedAt,
        DeviceStatus,
        FirmwareVersion,
        LastCommunicationAt,
        CreatedAt
    )
    SELECT
        V.VehicleId,
        'DVC' + RIGHT
        (
            '000000000000' + CONVERT(varchar(12), N.Number),
            12
        ),
        Activation.ActivatedAt,
        DeviceState.DeviceStatus,
        'FW-'
            + CONVERT(varchar(2), 2 + (N.Number % 4))
            + '.'
            + CONVERT(varchar(2), N.Number % 10),
        CASE
            WHEN DeviceState.DeviceStatus = 'I' THEN NULL
            ELSE DATEADD
            (
                MINUTE,
                -(N.Number % 43200),
                @AnchorDate
            )
        END,
        DATEADD(DAY, -1, Activation.ActivatedAt)
    FROM #Numbers AS N
    INNER JOIN fleet.Vehicle AS V
        ON V.VIN =
            '1FT' + RIGHT
            (
                '00000000000000' + CONVERT(varchar(14), N.Number),
                14
            )
    CROSS APPLY
    (
        VALUES
        (
            DATEADD
            (
                DAY,
                -(365 + (N.Number % 1460)),
                @AnchorDate
            )
        )
    ) AS Activation(ActivatedAt)
    CROSS APPLY
    (
        VALUES
        (
            CASE
                WHEN ((N.Number % 100) + (((N.Number - 1) / 100) * 29)) % 100 < 94 THEN 'A'
                WHEN ((N.Number % 100) + (((N.Number - 1) / 100) * 29)) % 100 < 98 THEN 'S'
                ELSE 'I'
            END
        )
    ) AS DeviceState(DeviceStatus)
    WHERE N.Number <= @DeviceCount;

    /*
        Policies

        Vehicles 1 through 20,000 receive both a current policy
        and one historical policy. The remaining vehicles receive
        one current policy.

        Distribution:
          - 40,000 current
          - 16,000 expired
          - 4,000 cancelled
    */
    INSERT INTO insurance.Policy
    (
        VehicleId,
        PolicyNumber,
        StartDate,
        EndDate,
        InsuredAmount,
        PolicyStatus,
        CreatedAt
    )
    SELECT
        V.VehicleId,
        'POL' + RIGHT
        (
            '000000000000' + CONVERT(varchar(12), N.Number),
            12
        ),
        PolicyDates.StartDate,
        DATEADD(DAY, 365, PolicyDates.StartDate),
        CONVERT
        (
            decimal(14, 2),
            150000 + ((N.Number % 1051) * 1000)
        ),
        CASE
            WHEN N.Number <= 40000 THEN 'C'
            WHEN N.Number <= 56000 THEN 'E'
            ELSE 'X'
        END,
        DATEADD(DAY, -30, PolicyDates.StartDate)
    FROM #Numbers AS N
    CROSS APPLY
    (
        VALUES
        (
            1 + ((N.Number - 1) % @VehicleCount)
        )
    ) AS Assignment(VehicleNumber)
    INNER JOIN fleet.Vehicle AS V
        ON V.VIN =
            '1FT' + RIGHT
            (
                '00000000000000'
                    + CONVERT(varchar(14), Assignment.VehicleNumber),
                14
            )
    CROSS APPLY
    (
        VALUES
        (
            CASE
                WHEN N.Number <= 40000
                    THEN DATEADD
                    (
                        DAY,
                        -(N.Number % 330),
                        @AnchorDate
                    )
                ELSE DATEADD
                    (
                        DAY,
                        -(500 + (N.Number % 730)),
                        @AnchorDate
                    )
            END
        )
    ) AS PolicyDates(StartDate)
    WHERE N.Number <= @PolicyCount;

    /*
        Validate all expected row counts before committing.
    */
    IF (SELECT COUNT_BIG(*) FROM crm.Customer) <> @CustomerCount
        THROW 51010, 'Unexpected Customer row count.', 1;

    IF (SELECT COUNT_BIG(*) FROM fleet.Vehicle) <> @VehicleCount
        THROW 51011, 'Unexpected Vehicle row count.', 1;

    IF (SELECT COUNT_BIG(*) FROM fleet.Device) <> @DeviceCount
        THROW 51012, 'Unexpected Device row count.', 1;

    IF (SELECT COUNT_BIG(*) FROM insurance.Policy) <> @PolicyCount
        THROW 51013, 'Unexpected Policy row count.', 1;

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
    S.SchemaName,
    S.TableName,
    S.[RowCount]
FROM
(
    SELECT
        1 AS SortOrder,
        N'crm' AS SchemaName,
        N'Customer' AS TableName,
        COUNT_BIG(*) AS [RowCount]
    FROM crm.Customer

    UNION ALL

    SELECT
        2,
        N'fleet',
        N'Vehicle',
        COUNT_BIG(*)
    FROM fleet.Vehicle

    UNION ALL

    SELECT
        3,
        N'fleet',
        N'Device',
        COUNT_BIG(*)
    FROM fleet.Device

    UNION ALL

    SELECT
        4,
        N'insurance',
        N'Policy',
        COUNT_BIG(*)
    FROM insurance.Policy
) AS S
ORDER BY S.SortOrder;

SELECT
    CountryCode,
    CustomerType,
    Status,
    COUNT_BIG(*) AS CustomerCount
FROM crm.Customer
GROUP BY
    CountryCode,
    CustomerType,
    Status
ORDER BY
    CountryCode,
    CustomerType,
    Status;

SELECT
    PolicyStatus,
    COUNT_BIG(*) AS PolicyCount,
    MIN(InsuredAmount) AS MinimumInsuredAmount,
    MAX(InsuredAmount) AS MaximumInsuredAmount
FROM insurance.Policy
GROUP BY PolicyStatus
ORDER BY PolicyStatus;

SELECT
    COUNT_BIG(*) AS BusinessCustomerCount,
    MIN(VehicleTotals.VehicleCount) AS MinimumVehicles,
    MAX(VehicleTotals.VehicleCount) AS MaximumVehicles,
    CONVERT
    (
        decimal(10, 2),
        AVG(CONVERT(decimal(10, 2), VehicleTotals.VehicleCount))
    ) AS AverageVehicles
FROM
(
    SELECT
        C.CustomerId,
        COUNT_BIG(*) AS VehicleCount
    FROM crm.Customer AS C
    INNER JOIN fleet.Vehicle AS V
        ON V.CustomerId = C.CustomerId
    WHERE C.CustomerType = 'B'
    GROUP BY C.CustomerId
) AS VehicleTotals;

SELECT
    DATEDIFF
    (
        MILLISECOND,
        @StartedAt,
        SYSDATETIME()
    ) AS TotalElapsedMilliseconds;
GO
