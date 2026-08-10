/*
Experiment 05 - Escalate to extreme PSP skew

Purpose:
Change only the distribution of the experimental SkewKey column while
preserving the table, index, query shape, aggregate columns, and stored
procedures.

Initial distribution:
- SkewKey 0: 279,784 rows
- SkewKey 1: 720,000 rows
- SkewKey 5: 216 rows

Final distribution:
- SkewKey 1: 999,999 rows
- SkewKey 5: 1 row

This creates an extreme 999,999-to-1 frequency difference for the
next PSP eligibility test.

Only the experimental table telemetry.PspHighSkewEvent is modified.
The script is safe to execute again after successful completion.
*/

USE FleetTelemetryLab;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

DECLARE
    @TableId int =
        OBJECT_ID(N'telemetry.PspHighSkewEvent'),
    @StartedAt datetime2(7) =
        SYSDATETIME(),
    @RareRowId bigint,
    @RowsAffectedByUpdates bigint = 0,
    @WasAlreadyEscalated bit = 0,
    @TotalRows bigint,
    @ZeroRows bigint,
    @CommonRows bigint,
    @RareRows bigint,
    @UnexpectedRows bigint;

IF COALESCE
(
    CONVERT(sysname, SERVERPROPERTY(N'InstanceName')),
    N'MSSQLSERVER'
) <> N'SQL2025LAB'
BEGIN
    THROW 51000,
        'Safety check failed: execute this script on SQL2025LAB.',
        1;
END;

IF DB_NAME() <> N'FleetTelemetryLab'
BEGIN
    THROW 51001,
        'Safety check failed: the current database must be FleetTelemetryLab.',
        1;
END;

IF @TableId IS NULL
BEGIN
    THROW 51002,
        'The table telemetry.PspHighSkewEvent does not exist.',
        1;
END;

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes AS i
    WHERE i.object_id = @TableId
      AND i.name = N'IX_PspHighSkewEvent_SkewKey'
      AND i.is_disabled = 0
)
BEGIN
    THROW 51003,
        'The required high-skew nonclustered index is unavailable.',
        1;
END;

IF OBJECT_ID
(
    N'telemetry.usp_PspHighSkewSummary_NoPsp',
    N'P'
) IS NULL
OR OBJECT_ID
(
    N'telemetry.usp_PspHighSkewSummary_Psp',
    N'P'
) IS NULL
BEGIN
    THROW 51004,
        'One or more high-skew experiment procedures do not exist.',
        1;
END;

SELECT
    @TotalRows = COUNT_BIG(*),
    @ZeroRows = SUM
    (
        CONVERT
        (
            bigint,
            CASE
                WHEN phe.SkewKey = 0 THEN 1
                ELSE 0
            END
        )
    ),
    @CommonRows = SUM
    (
        CONVERT
        (
            bigint,
            CASE
                WHEN phe.SkewKey = 1 THEN 1
                ELSE 0
            END
        )
    ),
    @RareRows = SUM
    (
        CONVERT
        (
            bigint,
            CASE
                WHEN phe.SkewKey = 5 THEN 1
                ELSE 0
            END
        )
    ),
    @UnexpectedRows = SUM
    (
        CONVERT
        (
            bigint,
            CASE
                WHEN phe.SkewKey NOT IN (0, 1, 5)
                THEN 1
                ELSE 0
            END
        )
    )
FROM telemetry.PspHighSkewEvent AS phe;

IF @TotalRows <> 1000000
   OR @UnexpectedRows <> 0
BEGIN
    THROW 51005,
        'The high-skew fixture contains an unexpected row count or key.',
        1;
END;

IF @ZeroRows = 0
   AND @CommonRows = 999999
   AND @RareRows = 1
BEGIN
    SET @WasAlreadyEscalated = 1;

    SELECT
        @RareRowId =
            MIN(phe.PspHighSkewEventId)
    FROM telemetry.PspHighSkewEvent AS phe
    WHERE phe.SkewKey = 5;
END;
ELSE
BEGIN
    IF @ZeroRows <> 279784
       OR @CommonRows <> 720000
       OR @RareRows <> 216
    BEGIN
        THROW 51006,
            'The fixture is neither in its initial nor final expected state.',
            1;
    END;

    SELECT
        @RareRowId =
            MIN(phe.PspHighSkewEventId)
    FROM telemetry.PspHighSkewEvent AS phe;
END;

BEGIN TRY
    BEGIN TRANSACTION;

    IF @WasAlreadyEscalated = 0
    BEGIN
        /*
        Convert every current zero and rare key to the common key.
        Existing common rows remain unchanged.
        */
        UPDATE phe
        SET phe.SkewKey = 1
        FROM telemetry.PspHighSkewEvent AS phe
        WHERE phe.SkewKey <> 1;

        SET @RowsAffectedByUpdates =
            @RowsAffectedByUpdates + @@ROWCOUNT;

        /*
        Select one deterministic row as the only rare value.
        */
        UPDATE phe
        SET phe.SkewKey = 5
        FROM telemetry.PspHighSkewEvent AS phe
        WHERE phe.PspHighSkewEventId = @RareRowId;

        SET @RowsAffectedByUpdates =
            @RowsAffectedByUpdates + @@ROWCOUNT;
    END;

    /*
    Rebuild exact leading-key statistics for the new distribution.
    */
    UPDATE STATISTICS
        telemetry.PspHighSkewEvent
        IX_PspHighSkewEvent_SkewKey
    WITH FULLSCAN;

    SELECT
        @TotalRows = COUNT_BIG(*),
        @ZeroRows = SUM
        (
            CONVERT
            (
                bigint,
                CASE
                    WHEN phe.SkewKey = 0 THEN 1
                    ELSE 0
                END
            )
        ),
        @CommonRows = SUM
        (
            CONVERT
            (
                bigint,
                CASE
                    WHEN phe.SkewKey = 1 THEN 1
                    ELSE 0
                END
            )
        ),
        @RareRows = SUM
        (
            CONVERT
            (
                bigint,
                CASE
                    WHEN phe.SkewKey = 5 THEN 1
                    ELSE 0
                END
            )
        )
    FROM telemetry.PspHighSkewEvent AS phe;

    IF @TotalRows <> 1000000
       OR @ZeroRows <> 0
       OR @CommonRows <> 999999
       OR @RareRows <> 1
    BEGIN
        THROW 51007,
            'The final extreme-skew distribution is incorrect.',
            1;
    END;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
    BEGIN
        ROLLBACK TRANSACTION;
    END;

    THROW;
END CATCH;

EXEC sys.sp_recompile
    N'telemetry.usp_PspHighSkewSummary_NoPsp';

EXEC sys.sp_recompile
    N'telemetry.usp_PspHighSkewSummary_Psp';

/*
Result set 1:
Escalation summary.
*/
SELECT
    @WasAlreadyEscalated AS WasAlreadyEscalated,
    @RowsAffectedByUpdates AS RowsAffectedByUpdates,
    @RareRowId AS RareRowId,
    DATEDIFF_BIG
    (
        millisecond,
        @StartedAt,
        SYSDATETIME()
    ) AS EscalationMilliseconds;

/*
Result set 2:
Final exact distribution.
*/
SELECT
    phe.SkewKey,
    COUNT_BIG(*) AS EventCount,
    CONVERT
    (
        decimal(9,4),
        COUNT_BIG(*) * 100.0 / 1000000.0
    ) AS Percentage
FROM telemetry.PspHighSkewEvent AS phe
GROUP BY phe.SkewKey
ORDER BY phe.SkewKey;

/*
Result set 3:
Confirm full-scan statistics and no pending modifications.
*/
SELECT
    s.stats_id AS StatsId,
    s.name AS StatisticsName,
    s.auto_created AS IsAutoCreated,
    s.user_created AS IsUserCreated,
    sp.last_updated AS LastUpdated,
    sp.rows AS TableRows,
    sp.rows_sampled AS RowsSampled,
    sp.steps AS HistogramSteps,
    sp.modification_counter AS ModificationCounter
FROM sys.stats AS s
OUTER APPLY sys.dm_db_stats_properties
(
    s.object_id,
    s.stats_id
) AS sp
WHERE s.object_id = @TableId
  AND s.name = N'IX_PspHighSkewEvent_SkewKey';

/*
Result set 4:
Confirm Query Store remained unchanged.
*/
SELECT
    qso.actual_state_desc AS ActualState,
    qso.desired_state_desc AS DesiredState,
    qso.query_capture_mode_desc AS CaptureMode
FROM sys.database_query_store_options AS qso;

/*
Result set 5:
The histogram should contain exactly two equality steps:
999,999 rows for key 1 and one row for key 5.
*/
DBCC SHOW_STATISTICS
(
    N'telemetry.PspHighSkewEvent',
    N'IX_PspHighSkewEvent_SkewKey'
)
WITH HISTOGRAM;
GO
