# Experiment 03: Composite Index Column Order

## Objective

This experiment evaluates how composite-index key order affects the amount of work performed by SQL Server.

The same selective aggregate query is executed under three index configurations:

1. No supporting nonclustered index.
2. A covering composite index ordered by `(EventTime, DeviceId)`.
3. A covering composite index ordered by `(DeviceId, EventTime)`.

Both composite indexes contain exactly the same columns and occupy the same amount of space. Their key order is the only intentional design difference.

The experiment demonstrates why an Index Seek is not necessarily efficient and how a range predicate on the leading key can prevent a later key from effectively narrowing the accessed interval.

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

## Dataset and Test-Case Selection

The experiment uses `telemetry.TelemetryEvent`, containing 1,000,000 deterministic synthetic rows.

A preliminary read-only script verified that no supporting nonclustered index existed and examined twenty candidate devices.

Every candidate contained:

- 25 total telemetry events.
- 4 events during December 2024.

`DeviceId = 10000` was selected as the deterministic test case.

| Measurement | Result |
|---|---:|
| Events for DeviceId 10000 | 25 |
| December events for DeviceId 10000 | 4 |
| December events across the table | 178,622 |
| Total table rows | 1,000,000 |

The query needs only four rows, representing 0.0004 percent of the table.

However, the complete December interval contains 178,622 rows. This creates a strong contrast between starting with the date range and starting with the device equality predicate.

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
WHERE DeviceId = 10000
  AND EventTime >= '2024-12-01T00:00:00'
  AND EventTime <  '2025-01-01T00:00:00';
```

The predicate combines:

- Equality on `DeviceId`.
- A half-open range on `EventTime`.

## Result Consistency

Every configuration produced the same result:

| Measurement | Result |
|---|---:|
| Event count | 4 |
| Total speed | 245 |
| Average battery voltage | 13.25 |
| Latest event time | 2024-12-27 18:33:20 |

This confirms that changing the index key order affected the access strategy but not the query semantics.

## Methodology

The experiment was performed in the following sequence:

1. Verify the original baseline index state.
2. Select a deterministic device and date interval.
3. Capture the unoptimized clustered-scan baseline.
4. Create a covering index ordered by `(EventTime, DeviceId)`.
5. Measure the range-first index and capture its actual plan.
6. Create an equivalent covering index ordered by `(DeviceId, EventTime)`.
7. Remove the range-first index.
8. Measure the equality-first index and capture its actual plan.
9. Remove all experimental indexes.
10. Run the independent database validation script.

Each measured query was executed twice. The second warm-cache execution was retained.

## Index Designs

### Range-first index

```sql
CREATE NONCLUSTERED INDEX IX_TelemetryEvent_EventTime_DeviceId
ON telemetry.TelemetryEvent
(
    EventTime,
    DeviceId
)
INCLUDE
(
    SpeedKph,
    BatteryVoltage
);
```

`EventTime` is the leading key. SQL Server can seek to the December interval, but that interval contains events from every device.

Because `DeviceId` follows a range key, it cannot reduce the single contiguous date interval as effectively for this query.

### Equality-first index

```sql
CREATE NONCLUSTERED INDEX IX_TelemetryEvent_DeviceId_EventTime
ON telemetry.TelemetryEvent
(
    DeviceId,
    EventTime
)
INCLUDE
(
    SpeedKph,
    BatteryVoltage
);
```

`DeviceId` is the leading key. SQL Server can first isolate one device and then apply the date range within that device's contiguous section of the index.

Both indexes are covering. Neither plan requires a Key Lookup.

## Observed Results

| Configuration | Principal access operation | Logical reads | CPU time | Elapsed time |
|---|---|---:|---:|---:|
| No supporting index | Clustered Index Scan | 7,380 | 125 ms | 115 ms |
| `(EventTime, DeviceId)` | Index Seek with residual predicate | 690 | 16 ms | 56 ms |
| `(DeviceId, EventTime)` | Index Seek without residual predicate | 3 | 0 ms | 67 ms |

Physical reads were zero in all retained measurements because the required pages were already present in memory.

The reported zero CPU value means that processor consumption was below the reporting granularity for the short equality-first execution.

## Logical-Read Improvement

| Comparison | Logical-read reduction | Reduction factor |
|---|---:|---:|
| Baseline to range-first index | 90.65% | 10.70 |
| Baseline to equality-first index | 99.96% | 2,460 |
| Range-first to equality-first index | 99.57% | 230 |

The equality-first index required only three logical page reads to locate and aggregate the four qualifying rows.

## Why Elapsed Time Is Not the Primary Metric

The equality-first execution recorded 67 ms compared with 56 ms for the range-first index despite performing substantially fewer logical reads.

These executions are short enough for workstation activity, operating-system scheduling, client processing, and timer granularity to outweigh the database work saved during a single execution.

Logical reads and operator row counts provide the stronger evidence in this experiment:

- Range-first: 690 logical reads and 178,622 index rows read.
- Equality-first: 3 logical reads and 4 index rows read.

The experiment therefore does not claim an elapsed-time improvement from the equality-first index based on these individual executions.

## Plan Analysis

### Baseline: Clustered Index Scan

Without a supporting index, SQL Server scanned the clustered index to locate four qualifying rows among 1,000,000 telemetry events.

The parallel scan required 7,380 logical reads.

Only 0.0004 percent of the table qualified, making a full clustered scan disproportionate to the requested result.

### Range-First Index: Seek with Residual Filtering

The `(EventTime, DeviceId)` index replaced the clustered scan with a nonclustered Index Seek and reduced logical reads from 7,380 to 690.

However, the plan properties revealed a critical distinction:

| Operator property | Value |
|---|---:|
| Estimated rows to be read | 178,342 |
| Actual rows read | 178,622 |
| Estimated rows returned | 6.1275 |
| Actual rows returned | 4 |

The `EventTime` boundaries appeared under **Seek Predicates**.

`DeviceId = 10000` appeared as a separate residual **Predicate**.

SQL Server accurately estimated the broad December interval, read all 178,622 index entries in that interval, applied the device predicate afterward, and retained four rows.

Approximately 44,656 index rows were read for each qualifying row.

This plan demonstrates that the presence of an Index Seek does not guarantee a narrow or efficient access operation.

### Equality-First Index: Fully Delimited Seek

The `(DeviceId, EventTime)` index also produced a nonclustered Index Seek, but its properties were materially different:

| Operator property | Value |
|---|---:|
| Estimated rows to be read | 10.5934 |
| Actual rows read | 4 |
| Estimated rows returned | 10.5934 |
| Actual rows returned | 4 |

The seek properties contained:

- `DeviceId = 10000` as the equality prefix.
- The lower `EventTime` boundary as the seek start.
- The upper `EventTime` boundary as the seek end.
- No separate residual predicate.

Every row read by the access operator qualified for the query.

The cardinality estimate was not exact, but the index allowed SQL Server to navigate directly to the required key interval and perform only three logical reads.

## Understanding the Additional Plan Operators

Both indexed plans contained operators such as:

- Constant Scan
- Compute Scalar
- Concatenation
- Merge Interval
- Nested Loops

In these plans, Nested Loops did not perform a Key Lookup. It combined optimizer-generated interval values with the Index Seek.

The absence of a Key Lookup operator and the covering index definitions confirm that all required query columns came directly from the nonclustered indexes.

## Storage Comparison

| Key order | Rows | Reserved space | Used space | Creation time |
|---|---:|---:|---:|---:|
| `(EventTime, DeviceId)` | 1,000,000 | 30.07 MB | 30.05 MB | 3,100 ms |
| `(DeviceId, EventTime)` | 1,000,000 | 30.07 MB | 30.05 MB | 2,250 ms |

Both designs used the same storage because they contained the same key and included columns.

The observed creation times are documented for reproducibility but are not treated as a meaningful performance comparison. Caching and current workstation activity affected the operations.

The identical index sizes strengthen the experiment: the 230-fold logical-read difference between the indexed plans resulted from key order rather than index width.

## Equality Before Range: A Workload-Dependent Heuristic

For this query, placing the equality column before the range column created the most selective contiguous key interval.

This supports the common heuristic of placing equality predicates before range predicates in a composite index.

It is not a universal rule. Appropriate key order also depends on:

- Other queries using the index.
- Predicate selectivity.
- Sorting and grouping requirements.
- Join patterns.
- Data distribution.
- Update frequency.
- Whether the index can serve multiple workload needs.

Composite indexes should be designed for an observed workload rather than by applying a rule mechanically.

## Cleanup and Validation

The cleanup script checked for and removed both possible experimental indexes.

| Index | Existed before cleanup | Final status |
|---|---:|---|
| `IX_TelemetryEvent_EventTime_DeviceId` | No | Removed |
| `IX_TelemetryEvent_DeviceId_EventTime` | Yes | Removed |

Cleanup completed in 70 ms.

The independent validation script subsequently produced:

| Validation result | Value |
|---|---:|
| Total checks | 45 |
| Passed checks | 45 |
| Failed checks | 0 |
| Overall result | PASS |

This confirms that the experiment restored the original unoptimized index state and did not alter the expected permanent data or database configuration.

## Reproduction Files

Execute or inspect the files in this order:

1. [`00-select-test-case.sql`](00-select-test-case.sql)
2. [`01-capture-baseline.sql`](01-capture-baseline.sql)
3. [`01-clustered-scan-baseline.sqlplan`](01-clustered-scan-baseline.sqlplan)
4. [`02-create-eventtime-deviceid-index.sql`](02-create-eventtime-deviceid-index.sql)
5. [`03-measure-eventtime-deviceid.sql`](03-measure-eventtime-deviceid.sql)
6. [`03-eventtime-deviceid-range-first.sqlplan`](03-eventtime-deviceid-range-first.sqlplan)
7. [`04-replace-with-deviceid-eventtime-index.sql`](04-replace-with-deviceid-eventtime-index.sql)
8. [`05-measure-deviceid-eventtime.sql`](05-measure-deviceid-eventtime.sql)
9. [`05-deviceid-eventtime-equality-first.sqlplan`](05-deviceid-eventtime-equality-first.sqlplan)
10. [`06-drop-composite-indexes.sql`](06-drop-composite-indexes.sql)

The test-case selection script does not modify the database. The cleanup script is safe to execute more than once.

## Limitations

- Measurements come from a local resource-constrained workstation.
- The retained measurements used a warm data cache.
- Only one device and one date interval were tested.
- Short elapsed times are sensitive to workstation and client activity.
- Concurrent workloads were not evaluated.
- Insert, update, and index-maintenance overhead was not benchmarked.
- Other queries could prefer a different key order.
- Results are comparative laboratory measurements, not production-capacity claims.

## Conclusion

Both composite indexes replaced a full clustered scan with a nonclustered Index Seek, but their seeks performed dramatically different amounts of work.

With `EventTime` first, SQL Server read the complete 178,622-row December interval and applied `DeviceId` as a residual predicate. The plan required 690 logical reads to return four rows.

With `DeviceId` first, SQL Server used both the equality predicate and date boundaries to delimit the seek. It read only the four qualifying rows and required three logical reads.

The experiment demonstrates that access-operator names alone are insufficient for performance analysis. Effective plan interpretation requires examining seek predicates, residual predicates, logical reads, estimated rows, actual rows, and rows read.
