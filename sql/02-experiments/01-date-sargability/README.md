# Experiment 01: Date Predicate SARGability

## Objective

Demonstrate how applying functions to a date column affects index usage, logical reads, cardinality estimates, CPU time, and execution-plan shape.

The experiment compares two semantically equivalent predicates that both return the telemetry events recorded during December 2024.

## Environment

| Property | Value |
|---|---|
| SQL Server | SQL Server 2025 Standard Developer, CU7 |
| Compatibility level | 170 |
| Table | `telemetry.TelemetryEvent` |
| Table rows | 1,000,000 |
| Experimental index | `IX_TelemetryEvent_EventTime` |
| Index key | `EventTime` |
| Index used space | 19.42 MB |
| Index creation time | 1,628 ms |
| Measurement condition | Second warm-cache execution |

All measurements were collected locally with `SET STATISTICS IO ON`, `SET STATISTICS TIME ON`, and actual execution plans enabled.

## Compared Predicates

### Query A: Non-SARGable

```sql
SELECT
    COUNT_BIG(*) AS DecemberEventCount
FROM telemetry.TelemetryEvent
WHERE YEAR(EventTime) = 2024
  AND MONTH(EventTime) = 12;
```

`EventTime` is wrapped in two functions. SQL Server cannot navigate the ordered index using a continuous date interval.

### Query B: SARGable

```sql
SELECT
    COUNT_BIG(*) AS DecemberEventCount
FROM telemetry.TelemetryEvent
WHERE EventTime >= '2024-12-01T00:00:00'
  AND EventTime <  '2025-01-01T00:00:00';
```

`EventTime` remains unchanged and is compared with constant lower and upper bounds. Both queries return exactly 178,622 rows.

## Results

| Scenario | Main operator | Logical reads | Approx. data read | CPU time | Elapsed time | Estimated rows | Actual rows |
|---|---|---:|---:|---:|---:|---:|---:|
| Original baseline without the index | Clustered Index Scan | 7,380 | 57.66 MiB | 468 ms | 449 ms | 83,333 | 178,622 |
| Query A with the index | Nonclustered Index Scan | 2,486 | 19.42 MiB | 422 ms | 520 ms | 83,333 | 178,622 |
| Query B with the index | Nonclustered Index Seek | 448 | 3.50 MiB | 62 ms | 247 ms | 178,342 | 178,622 |

## Measured Improvements

Replacing Query A with Query B while keeping the same index produced:

- 82.0% fewer logical reads.
- 85.3% less CPU time.
- 52.5% less elapsed time.
- 5.55 times fewer pages read.
- A cardinality estimate within 0.16% of the actual result.

Compared with the original baseline, Query B produced:

- 93.9% fewer logical reads.
- 86.8% less CPU time.
- 45.0% less elapsed time.
- 16.47 times fewer pages read.

## Execution-Plan Analysis

### Original baseline

Without an index on `EventTime`, SQL Server used a parallel `Clustered Index Scan` and read approximately the complete 57 MB table.

The optimizer estimated 83,333 rows but returned 178,622 rows. The actual result was approximately 214% of the estimate.

### Query A

After the experimental index was created, SQL Server selected the narrower nonclustered index but still performed an `Index Scan`.

The index reduced the pages read relative to the original table, but the function-based predicate prevented a seek. Its cardinality estimate remained 83,333 rows.

### Query B

The half-open date interval enabled an `Index Seek`. SQL Server formed a continuous seek range and read only the pages containing qualifying dates.

The estimate improved to 178,342 rows, only 280 fewer than the actual 178,622 rows. Statistics on the `EventTime` index could now support the range estimate.

The additional `Constant Scan`, `Compute Scalar`, `Concatenation`, and `Merge Interval` operators prepare the seek boundaries and contribute negligible cost.

## Why Use a Half-Open Interval?

The upper boundary is exclusive:

```sql
EventTime >= '2024-12-01T00:00:00'
AND EventTime <  '2025-01-01T00:00:00'
```

This includes every possible time during December regardless of the column's fractional-second precision.

A predicate such as the following is error-prone:

```sql
BETWEEN '2024-12-01' AND '2024-12-31'
```

Its upper boundary represents midnight at the beginning of December 31 and can exclude events occurring later that day.

## Reproduction

Execute the files in this order:

1. [`01-capture-baseline.sql`](01-capture-baseline.sql)
2. [`02-create-eventtime-index.sql`](02-create-eventtime-index.sql)
3. [`03-compare-date-predicates.sql`](03-compare-date-predicates.sql)
4. [`04-drop-eventtime-index.sql`](04-drop-eventtime-index.sql)

Execution-plan evidence:

- [`01-non-sargable-baseline.sqlplan`](01-non-sargable-baseline.sqlplan)
- [`03-date-predicate-comparison.sqlplan`](03-date-predicate-comparison.sqlplan)

The cleanup script removes the experimental index and restores the original unoptimized database state.

## Conclusions

- A useful index does not guarantee an `Index Seek`.
- Applying functions to a candidate search column can force an index scan.
- SARGable predicates allow SQL Server to navigate index key ranges.
- SARGability can improve both access methods and cardinality estimates.
- Logical reads provide a more stable comparison than elapsed time alone.
- Equivalent results do not imply equivalent execution costs.

## Limitations

The measurements represent warm-cache executions on one resource-constrained local workstation. Elapsed time can vary because of scheduling, parallelism, and other system activity.

The query uses `COUNT_BIG` to isolate predicate and access-path behavior. These results are comparative evidence and are not production-capacity benchmarks.
