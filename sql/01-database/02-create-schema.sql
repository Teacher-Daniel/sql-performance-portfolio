/*
Purpose:
    Create the FleetTelemetryLab business schemas, tables,
    keys, relationships, and data-quality constraints.

Safety:
    - Must run against SQL2025LAB.
    - Must run inside FleetTelemetryLab.
    - Stops if any target table already exists.
    - Uses a transaction so partial schemas are rolled back.

Baseline:
    Foreign-key indexes are intentionally omitted. Their effects
    will be measured during later performance experiments.
*/

USE [FleetTelemetryLab];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF CONVERT(int, SERVERPROPERTY('ProductMajorVersion')) <> 17
   OR CONVERT(sysname, SERVERPROPERTY('InstanceName')) <> N'SQL2025LAB'
BEGIN
    THROW 50011,
        'Run this script on the SQL Server 2025 instance SQL2025LAB.',
        1;
END;

IF DB_NAME() <> N'FleetTelemetryLab'
BEGIN
    THROW 50012,
        'The current database must be FleetTelemetryLab.',
        1;
END;

IF EXISTS
(
    SELECT 1
    FROM sys.tables AS t
    INNER JOIN sys.schemas AS s
        ON s.schema_id = t.schema_id
    WHERE
        (s.name = N'crm' AND t.name = N'Customer')
        OR (s.name = N'fleet' AND t.name IN (N'Vehicle', N'Device'))
        OR (s.name = N'insurance' AND t.name = N'Policy')
        OR
        (
            s.name = N'telemetry'
            AND t.name IN (N'TelemetryEvent', N'Alert')
        )
)
BEGIN
    THROW 50013,
        'One or more target tables already exist. No changes were made.',
        1;
END;

BEGIN TRY
    BEGIN TRANSACTION;

    IF SCHEMA_ID(N'crm') IS NULL
        EXEC(N'CREATE SCHEMA [crm] AUTHORIZATION [dbo];');

    IF SCHEMA_ID(N'fleet') IS NULL
        EXEC(N'CREATE SCHEMA [fleet] AUTHORIZATION [dbo];');

    IF SCHEMA_ID(N'insurance') IS NULL
        EXEC(N'CREATE SCHEMA [insurance] AUTHORIZATION [dbo];');

    IF SCHEMA_ID(N'telemetry') IS NULL
        EXEC(N'CREATE SCHEMA [telemetry] AUTHORIZATION [dbo];');

    CREATE TABLE [crm].[Customer]
    (
        [CustomerId] int IDENTITY(1, 1) NOT NULL,
        [CustomerCode] char(10) NOT NULL,
        [DisplayName] nvarchar(100) NOT NULL,
        [CountryCode] char(2) NOT NULL,
        [CustomerType] char(1) NOT NULL,
        [Status] char(1) NOT NULL,
        [CreatedAt] datetime2(0) NOT NULL,

        CONSTRAINT [PK_crm_Customer]
            PRIMARY KEY CLUSTERED ([CustomerId]),

        CONSTRAINT [UQ_crm_Customer_CustomerCode]
            UNIQUE NONCLUSTERED ([CustomerCode]),

        CONSTRAINT [CK_crm_Customer_CountryCode]
            CHECK ([CountryCode] IN ('MX', 'CO', 'AR', 'CL', 'PE')),

        CONSTRAINT [CK_crm_Customer_CustomerType]
            CHECK ([CustomerType] IN ('P', 'B')),

        CONSTRAINT [CK_crm_Customer_Status]
            CHECK ([Status] IN ('A', 'I'))
    );

    CREATE TABLE [fleet].[Vehicle]
    (
        [VehicleId] int IDENTITY(1, 1) NOT NULL,
        [CustomerId] int NOT NULL,
        [VIN] char(17) NOT NULL,
        [PlateNumber] varchar(12) NOT NULL,
        [ModelYear] smallint NOT NULL,
        [VehicleType] char(1) NOT NULL,
        [Status] char(1) NOT NULL,
        [CreatedAt] datetime2(0) NOT NULL,

        CONSTRAINT [PK_fleet_Vehicle]
            PRIMARY KEY CLUSTERED ([VehicleId]),

        CONSTRAINT [UQ_fleet_Vehicle_VIN]
            UNIQUE NONCLUSTERED ([VIN]),

        CONSTRAINT [FK_fleet_Vehicle_crm_Customer]
            FOREIGN KEY ([CustomerId])
            REFERENCES [crm].[Customer] ([CustomerId]),

        CONSTRAINT [CK_fleet_Vehicle_ModelYear]
            CHECK ([ModelYear] BETWEEN 2000 AND 2030),

        CONSTRAINT [CK_fleet_Vehicle_VehicleType]
            CHECK ([VehicleType] IN ('C', 'S', 'T', 'V')),

        CONSTRAINT [CK_fleet_Vehicle_Status]
            CHECK ([Status] IN ('A', 'I', 'S'))
    );

    CREATE TABLE [fleet].[Device]
    (
        [DeviceId] int IDENTITY(1, 1) NOT NULL,
        [VehicleId] int NOT NULL,
        [DeviceSerial] char(15) NOT NULL,
        [ActivatedAt] date NOT NULL,
        [DeviceStatus] char(1) NOT NULL,
        [FirmwareVersion] varchar(20) NOT NULL,
        [LastCommunicationAt] datetime2(0) NULL,
        [CreatedAt] datetime2(0) NOT NULL,

        CONSTRAINT [PK_fleet_Device]
            PRIMARY KEY CLUSTERED ([DeviceId]),

        CONSTRAINT [UQ_fleet_Device_DeviceSerial]
            UNIQUE NONCLUSTERED ([DeviceSerial]),

        CONSTRAINT [UQ_fleet_Device_VehicleId]
            UNIQUE NONCLUSTERED ([VehicleId]),

        CONSTRAINT [FK_fleet_Device_fleet_Vehicle]
            FOREIGN KEY ([VehicleId])
            REFERENCES [fleet].[Vehicle] ([VehicleId]),

        CONSTRAINT [CK_fleet_Device_DeviceStatus]
            CHECK ([DeviceStatus] IN ('A', 'S', 'I')),

        CONSTRAINT [CK_fleet_Device_LastCommunication]
            CHECK
            (
                [LastCommunicationAt] IS NULL
                OR [LastCommunicationAt] >=
                    CAST([ActivatedAt] AS datetime2(0))
            )
    );

    CREATE TABLE [insurance].[Policy]
    (
        [PolicyId] int IDENTITY(1, 1) NOT NULL,
        [VehicleId] int NOT NULL,
        [PolicyNumber] char(15) NOT NULL,
        [StartDate] date NOT NULL,
        [EndDate] date NOT NULL,
        [InsuredAmount] decimal(14, 2) NOT NULL,
        [PolicyStatus] char(1) NOT NULL,
        [CreatedAt] datetime2(0) NOT NULL,

        CONSTRAINT [PK_insurance_Policy]
            PRIMARY KEY CLUSTERED ([PolicyId]),

        CONSTRAINT [UQ_insurance_Policy_PolicyNumber]
            UNIQUE NONCLUSTERED ([PolicyNumber]),

        CONSTRAINT [FK_insurance_Policy_fleet_Vehicle]
            FOREIGN KEY ([VehicleId])
            REFERENCES [fleet].[Vehicle] ([VehicleId]),

        CONSTRAINT [CK_insurance_Policy_Dates]
            CHECK ([EndDate] > [StartDate]),

        CONSTRAINT [CK_insurance_Policy_InsuredAmount]
            CHECK ([InsuredAmount] > 0),

        CONSTRAINT [CK_insurance_Policy_Status]
            CHECK ([PolicyStatus] IN ('C', 'E', 'X'))
    );

    CREATE TABLE [telemetry].[TelemetryEvent]
    (
        [TelemetryEventId] bigint IDENTITY(1, 1) NOT NULL,
        [DeviceId] int NOT NULL,
        [EventTime] datetime2(0) NOT NULL,
        [ReceivedAt] datetime2(0) NOT NULL,
        [EventType] tinyint NOT NULL,
        [Latitude] decimal(9, 6) NOT NULL,
        [Longitude] decimal(9, 6) NOT NULL,
        [SpeedKph] smallint NOT NULL,
        [IgnitionOn] bit NOT NULL,
        [OdometerKm] int NOT NULL,
        [BatteryVoltage] decimal(4, 2) NOT NULL,
        [PayloadBytes] smallint NOT NULL,

        CONSTRAINT [PK_telemetry_TelemetryEvent]
            PRIMARY KEY CLUSTERED ([TelemetryEventId]),

        CONSTRAINT [FK_telemetry_TelemetryEvent_fleet_Device]
            FOREIGN KEY ([DeviceId])
            REFERENCES [fleet].[Device] ([DeviceId]),

        CONSTRAINT [CK_telemetry_TelemetryEvent_Times]
            CHECK ([ReceivedAt] >= [EventTime]),

        CONSTRAINT [CK_telemetry_TelemetryEvent_EventType]
            CHECK ([EventType] BETWEEN 1 AND 5),

        CONSTRAINT [CK_telemetry_TelemetryEvent_Latitude]
            CHECK ([Latitude] BETWEEN -90 AND 90),

        CONSTRAINT [CK_telemetry_TelemetryEvent_Longitude]
            CHECK ([Longitude] BETWEEN -180 AND 180),

        CONSTRAINT [CK_telemetry_TelemetryEvent_Speed]
            CHECK ([SpeedKph] BETWEEN 0 AND 250),

        CONSTRAINT [CK_telemetry_TelemetryEvent_Odometer]
            CHECK ([OdometerKm] >= 0),

        CONSTRAINT [CK_telemetry_TelemetryEvent_Battery]
            CHECK ([BatteryVoltage] BETWEEN 0 AND 48),

        CONSTRAINT [CK_telemetry_TelemetryEvent_Payload]
            CHECK ([PayloadBytes] BETWEEN 0 AND 8000)
    );

    CREATE TABLE [telemetry].[Alert]
    (
        [AlertId] bigint IDENTITY(1, 1) NOT NULL,
        [TelemetryEventId] bigint NOT NULL,
        [AlertType] tinyint NOT NULL,
        [Severity] tinyint NOT NULL,
        [AlertStatus] char(1) NOT NULL,
        [CreatedAt] datetime2(0) NOT NULL,
        [ResolvedAt] datetime2(0) NULL,
        [ResolutionCode] varchar(20) NULL,

        CONSTRAINT [PK_telemetry_Alert]
            PRIMARY KEY CLUSTERED ([AlertId]),

        CONSTRAINT [FK_telemetry_Alert_telemetry_TelemetryEvent]
            FOREIGN KEY ([TelemetryEventId])
            REFERENCES [telemetry].[TelemetryEvent] ([TelemetryEventId]),

        CONSTRAINT [CK_telemetry_Alert_AlertType]
            CHECK ([AlertType] BETWEEN 1 AND 6),

        CONSTRAINT [CK_telemetry_Alert_Severity]
            CHECK ([Severity] BETWEEN 1 AND 3),

        CONSTRAINT [CK_telemetry_Alert_Status]
            CHECK ([AlertStatus] IN ('O', 'C', 'E')),

        CONSTRAINT [CK_telemetry_Alert_ResolutionTime]
            CHECK
            (
                [ResolvedAt] IS NULL
                OR [ResolvedAt] >= [CreatedAt]
            ),

        CONSTRAINT [CK_telemetry_Alert_StatusResolution]
            CHECK
            (
                ([AlertStatus] = 'C' AND [ResolvedAt] IS NOT NULL)
                OR
                (
                    [AlertStatus] IN ('O', 'E')
                    AND [ResolvedAt] IS NULL
                )
            )
    );

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO

PRINT 'Created tables';

SELECT
    s.name AS SchemaName,
    t.name AS TableName,
    SUM(p.rows) AS [RowCount]
FROM sys.tables AS t
INNER JOIN sys.schemas AS s
    ON s.schema_id = t.schema_id
INNER JOIN sys.partitions AS p
    ON p.object_id = t.object_id
   AND p.index_id IN (0, 1)
WHERE s.name IN (N'crm', N'fleet', N'insurance', N'telemetry')
GROUP BY
    s.name,
    t.name
ORDER BY
    s.name,
    t.name;

PRINT 'Created foreign keys';

SELECT
    fk.name AS ForeignKeyName,
    OBJECT_SCHEMA_NAME(fk.parent_object_id) AS ParentSchema,
    OBJECT_NAME(fk.parent_object_id) AS ParentTable,
    OBJECT_SCHEMA_NAME(fk.referenced_object_id) AS ReferencedSchema,
    OBJECT_NAME(fk.referenced_object_id) AS ReferencedTable,
    fk.is_disabled AS IsDisabled,
    fk.is_not_trusted AS IsNotTrusted
FROM sys.foreign_keys AS fk
WHERE OBJECT_SCHEMA_NAME(fk.parent_object_id)
    IN (N'fleet', N'insurance', N'telemetry')
ORDER BY fk.name;

PRINT 'Created indexes';

SELECT
    s.name AS SchemaName,
    t.name AS TableName,
    i.name AS IndexName,
    i.type_desc AS IndexType,
    i.is_unique AS IsUnique,
    i.is_primary_key AS IsPrimaryKey,
    i.is_unique_constraint AS IsUniqueConstraint
FROM sys.indexes AS i
INNER JOIN sys.tables AS t
    ON t.object_id = i.object_id
INNER JOIN sys.schemas AS s
    ON s.schema_id = t.schema_id
WHERE i.index_id > 0
  AND s.name IN (N'crm', N'fleet', N'insurance', N'telemetry')
ORDER BY
    s.name,
    t.name,
    i.index_id;

PRINT 'FleetTelemetryLab schema created successfully.';
GO
