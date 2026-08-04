# Experiment 02: Key Lookups and Covering Indexes

## Objective

This experiment evaluates how nonclustered-index coverage affects logical reads and execution plans in SQL Server.

The same selective aggregate query is executed under three index configurations:

1. No supporting index on `DeviceId`.
2. A noncovering index containing only `DeviceId`.
3. A covering index containing `DeviceId` and the additional columns required by the query.

The experiment demonstrates when a Key Lookup appears, why it adds work, and how included columns can eliminate it.

## Environment

- SQL Server 2025 Standard Developer Edition, CU7
- Database compatibility level 170
- Maximum server memory: 2,048 MB
- MAXDOP: 2
- Warm-cache measurements
- Actual execution plans enabled
- `SET STATISTICS IO ON`
- `SET STATISTICS TIME ON`

See the [laboratory configuration](../../../docs/lab-environment.md) and the [sample database documentation](../../../docs/sample-database.md) for complete environment and dataset details.

## Dataset

The experiment uses `telemetry.TelemetryEvent`, containing 1,000,000 deterministic synthetic rows.

Before the experiment, the table had no supporting nonclustered index on `DeviceId`. Its clustered primary key was the only available access path for this query.

## Test Query

All three measurements use the same query:

```sql
SELECT
    COUNT_BIG(*) AS EventCount,
    SUM(CONVERT(bigint, SpeedKph)) AS TotalSpeedKph,
    CONVERT
    (
        decimal(10,2),
        AVG(CONVERT(decimal(10,4), BatteryVoltage))
    ) AS AverageBatteryVoltage,
    MAX(EventTime) AS LatestEventTime
FROM telemetry.TelemetryEvent
WHERE DeviceId BETWEEN 10000 AND 10019;
```

The predicate returns 500 rows, representing 0.05 percent of the table.

## Result Consistency

Every index configuration produced the same result:

| Measurement | Result |
|---|---:|
| Event count | 500 |
| Total speed | 20,188 |
| Average battery voltage | 13.14 |
| Latest event time | 2024-12-27 18:33:20 |

This confirms that the index changes affected the access strategy but not the query semantics.

## Methodology

The experiment was performed in the following sequence:

1. Confirm that no supporting `DeviceId` index existed.
2. Capture the unoptimized clustered-scan baseline.
3. Create a noncovering index on `DeviceId`.
4. Execute the same query and capture its Key Lookup plan.
5. Replace the index with a covering version using included columns.
6. Execute the same query and capture the lookup-free plan.
7. Remove the experimental index.
8. Run the independent database validation script.

Each measured query was executed twice. The second warm-cache execution was retained for comparison.

## Index Designs

### Noncovering index

```sql
CREATE NONCLUSTERED INDEX IX_TelemetryEvent_DeviceId
ON telemetry.TelemetryEvent
(
    DeviceId
);
```

This index can locate the qualifying rows efficiently, but it does not contain `EventTime`, `SpeedKph`, or `BatteryVoltage`.

SQL Server must therefore retrieve those values from the clustered index for every qualifying row.

### Covering index

```sql
CREATE NONCLUSTERED INDEX IX_TelemetryEvent_DeviceId
ON telemetry.TelemetryEvent
(
    DeviceId
)
INCLUDE
(
    EventTime,
    SpeedKph,
    BatteryVoltage
);
```

The covering index contains every column needed by the query. SQL Server can evaluate the predicate and calculate the aggregates without returning to the clustered index.

## Observed Results

| Configuration | Principal plan operations | Logical reads | CPU time | Elapsed time |
|---|---|---:|---:|---:|
| No supporting index | Clustered Index Scan | 7,380 | 126 ms | 134 ms |
| Noncovering index | Index Seek, Nested Loops, Key Lookup | 1,544 | 0 ms | 81 ms |
| Covering index | Index Seek | 6 | 0 ms | 65 ms |

A reported CPU time of zero does not mean that no processor work occurred. It means that the consumed CPU time was below the reporting granularity for these short executions.

Physical reads were zero in every retained measurement because the required pages were already present in memory. Logical reads therefore provide the most stable comparison of the work performed by each plan.

## Improvement Summary

| Comparison | Logical-read reduction | Elapsed-time reduction |
|---|---:|---:|
| Baseline to noncovering index | 79.08% | 39.55% |
| Baseline to covering index | 99.92% | 51.49% |
| Noncovering to covering index | 99.61% | 19.75% |

The covering plan performed 6 logical reads instead of 7,380, representing a reduction factor of 1,230 compared with the baseline.

Compared with the noncovering index, it reduced the logical-read count by a factor of approximately 257.

Elapsed time is more susceptible to workstation activity, scheduling, and measurement granularity. The logical-read reduction is the strongest evidence of the improvement.

## Plan Analysis

### Baseline: Clustered Index Scan

Without an index on `DeviceId`, SQL Server scanned the clustered index to locate 500 qualifying rows among 1,000,000 events.

The plan read 7,380 pages and used parallel execution.

The scan estimated 290 rows and returned 500, making the actual row count approximately 172 percent of the estimate.

### Noncovering Index: Seek and Key Lookup

The narrow nonclustered index allowed SQL Server to seek directly to the required `DeviceId` range.

Its statistics also improved the estimate: the plan estimated 500 rows and returned exactly 500.

However, the index did not contain the three columns needed by the aggregates. The execution plan therefore used Nested Loops to perform a clustered Key Lookup for each qualifying row.

The seek reduced the logical reads from 7,380 to 1,544, but the 500 repeated lookups remained measurable work.

A Key Lookup is not inherently a defect. It can be efficient when very few rows qualify. Its cumulative cost becomes important as the qualifying row count increases.

### Covering Index: Seek Without Lookups

After adding `EventTime`, `SpeedKph`, and `BatteryVoltage` as included columns, the plan retained the selective Index Seek but eliminated both the Nested Loops operation and the Key Lookup.

The seek estimated and returned 500 rows.

Because all required values were available in the nonclustered index leaf pages, the complete aggregate query required only 6 logical reads.

## Storage Trade-off

| Index design | Rows | Reserved space | Used space |
|---|---:|---:|---:|
| Noncovering | 1,000,000 | 17.51 MB | 17.47 MB |
| Covering | 1,000,000 | 30.07 MB | 30.03 MB |

The included columns increased reserved space by 12.56 MB, or approximately 71.7 percent relative to the narrow index.

This additional storage produced a substantial reduction in read work for the tested query. It would also introduce additional maintenance during inserts and during updates to any included column.

A covering index should therefore be justified by the workload rather than created automatically for every query.

The observed creation times were 6,371 ms for the noncovering index and 2,817 ms for the covering replacement. These timings are recorded for reproducibility but are not treated as a meaningful comparison because caching, current system activity, and `DROP_EXISTING` affected the operations.

## Cleanup and Validation

The cleanup script removed `IX_TelemetryEvent_DeviceId` and restored the original unoptimized index state.

Observed cleanup result:

| Measurement | Result |
|---|---:|
| Index existed before cleanup | Yes |
| Final index status | Removed |
| Cleanup time | 9 ms |

The independent validation script subsequently produced:

| Validation result | Value |
|---|---:|
| Total checks | 45 |
| Passed checks | 45 |
| Failed checks | 0 |
| Overall result | PASS |

This confirms that the experiment and its cleanup did not alter the expected permanent data or database configuration.

## Reproduction Files

Execute or inspect the files in this order:

1. [`01-capture-baseline.sql`](01-capture-baseline.sql)
2. [`01-clustered-scan-baseline.sqlplan`](01-clustered-scan-baseline.sqlplan)
3. [`02-create-noncovering-index.sql`](02-create-noncovering-index.sql)
4. [`03-measure-key-lookup.sql`](03-measure-key-lookup.sql)
5. [`03-noncovering-index-key-lookup.sqlplan`](03-noncovering-index-key-lookup.sqlplan)
6. [`04-replace-with-covering-index.sql`](04-replace-with-covering-index.sql)
7. [`05-measure-covering-index.sql`](05-measure-covering-index.sql)
8. [`05-covering-index-seek.sqlplan`](05-covering-index-seek.sqlplan)
9. [`06-drop-deviceid-index.sql`](06-drop-deviceid-index.sql)

The cleanup script is safe to execute more than once.

## Limitations

- Measurements come from a local resource-constrained workstation.
- The retained measurements used a warm data cache.
- Short execution times are sensitive to scheduler and workstation activity.
- Only one selective `DeviceId` range was tested.
- The experiment does not measure concurrent workloads.
- Insert, update, and index-maintenance overhead was not benchmarked.
- The results demonstrate comparative behavior, not production capacity.

## Conclusion

A narrow nonclustered index significantly improved the query by replacing a full clustered scan with a selective seek. However, missing aggregate columns required 500 clustered Key Lookups.

Adding the required columns to the index eliminated those lookups and reduced logical reads from 1,544 to 6 while preserving the same results and accurate cardinality estimate.

The experiment demonstrates the central covering-index trade-off: additional index width and write-maintenance cost can be justified when eliminating repeated lookups materially reduces read work for an important query.
