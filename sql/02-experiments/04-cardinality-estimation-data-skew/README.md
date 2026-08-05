# Experiment 04: Cardinality Estimates and Data Skew

## Objective

This experiment evaluates how SQL Server uses statistics and cardinality estimates to choose different execution plans for common and rare values.

Two queries use:

- The same table.
- The same selected columns.
- The same date interval.
- The same available index.
- The same query structure.
- Independent compilation through `OPTION (RECOMPILE)`.

Only the `EventType` literal changes.

The experiment demonstrates:

1. How a histogram represents skewed data.
2. Why sampled statistics contain approximate row counts.
3. Why estimates for combined predicates can differ from single-column histogram values.
4. How different estimates can produce different access strategies.
5. Why an inaccurate estimate can still lead to a reasonable plan.

## Environment

- SQL Server 2025 Standard Developer Edition, CU7
- Database compatibility level 170
- Maximum server memory: 2,048 MB
- MAXDOP: 2
- Automatic statistics enabled
- Warm-cache measurements
- Actual execution plans enabled
- `SET STATISTICS IO ON`
- `SET STATISTICS TIME ON`

See the [laboratory configuration](../../../docs/lab-environment.md) and the [sample database documentation](../../../docs/sample-database.md) for complete environment and dataset details.

## Dataset

The experiment uses `telemetry.TelemetryEvent`, containing 1,000,000 deterministic synthetic rows.

`EventType` has an intentionally uneven distribution:

| EventType | Actual rows | Percentage |
|---:|---:|---:|
| 1 | 720,000 | 72% |
| 2 | 100,000 | 10% |
| 3 | 80,000 | 8% |
| 4 | 60,000 | 6% |
| 5 | 40,000 | 4% |

The most common value occurs eighteen times as often as the rarest value.

## Existing Automatic Statistics

Before the experiment, SQL Server already had an automatically created statistic on `EventType`:

| Property | Value |
|---|---|
| Statistics name | `_WA_Sys_00000005_628FA481` |
| Automatically created | Yes |
| Table rows | 1,000,000 |
| Rows sampled | 176,319 |
| Sampling percentage | Approximately 17.63% |
| Histogram steps | 5 |

The statistic contained one histogram step for every valid `EventType`.

### Sampled Histogram

| EventType | Actual rows | Estimated equal rows | Approximate error |
|---:|---:|---:|---:|
| 1 | 720,000 | 721,204.20 | +0.17% |
| 2 | 100,000 | 99,138.49 | −0.86% |
| 3 | 80,000 | 80,002.72 | +0.003% |
| 4 | 60,000 | 59,698.61 | −0.50% |
| 5 | 40,000 | 39,955.99 | −0.11% |

The decimal values are estimates derived from the sample rather than exact row counts.

The histogram accurately represents the data skew despite sampling only part of the table.

## Test-Window Selection

A read-only selection script measured common and rare values across several candidate intervals.

| EventType | 24 hours | 12 hours | 6 hours | 3 hours |
|---:|---:|---:|---:|---:|
| 1 | 3,870 | 1,938 | 951 | 471 |
| 2 | 528 | 268 | 121 | 58 |
| 3 | 414 | 204 | 105 | 57 |
| 4 | 315 | 156 | 93 | 48 |
| 5 | 216 | 104 | 64 | 32 |

The 24-hour interval on December 6, 2024, was selected because it produced:

- 3,870 rows for the common value.
- 216 rows for the rare value.
- A frequency difference of approximately 17.9 times.

This range was expected to place the two values on opposite sides of the optimizer's cost-based choice between repeated Key Lookups and a clustered-index scan.

## Test Query

The common-value query is:

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
WHERE EventType = 1
  AND EventTime >= '2024-12-06T00:00:00'
  AND EventTime <  '2024-12-07T00:00:00'
OPTION (RECOMPILE);
```

The rare-value query is identical except for:

```sql
WHERE EventType = 5
```

`OPTION (RECOMPILE)` ensures that each literal is independently estimated and optimized. Cached-plan reuse is deliberately excluded from this experiment.

## Result Consistency

The results remained unchanged before and after creating the experimental index.

### Common value

| Measurement | Result |
|---|---:|
| Event count | 3,870 |
| Total speed | 310,628 |
| Average battery voltage | 13.23 |
| Latest event time | 2024-12-06 23:59:54 |

### Rare value

| Measurement | Result |
|---|---:|
| Event count | 216 |
| Total speed | 16,652 |
| Average battery voltage | 13.25 |
| Latest event time | 2024-12-06 23:58:37 |

This confirms that the index affected plan selection but not query semantics.

## Methodology

The experiment was performed in the following sequence:

1. Verify that no experimental nonclustered index existed.
2. Inspect the actual `EventType` distribution.
3. Inspect the existing automatic statistic and histogram.
4. Select a deterministic test interval.
5. Capture common-value and rare-value baselines without a supporting index.
6. Create a noncovering index on `(EventType, EventTime)`.
7. Inspect the exact index statistics and histogram.
8. Recompile and execute both literal queries.
9. Capture the different execution plans.
10. Remove the experimental index.
11. Confirm preservation of the original automatic statistic.
12. Run the independent database validation script.

Each measured script was executed twice. The second warm-cache execution was retained.

## No-Index Baseline

Without a supporting nonclustered index, both queries used a parallel Clustered Index Scan.

| EventType | Actual rows | Estimated rows | Rows read | Logical reads | CPU time | Elapsed time |
|---:|---:|---:|---:|---:|---:|---:|
| 1 | 3,870 | 4,264.38 | 1,000,000 | 7,380 | 126 ms | 132 ms |
| 5 | 216 | 1,003.73 | 1,000,000 | 7,380 | 78 ms | 88 ms |

### Baseline estimation accuracy

| EventType | Estimate error | Estimate-to-actual factor |
|---:|---:|---:|
| 1 | +10.19% | 1.10 |
| 5 | +364.69% | 4.65 |

The common-value estimate was reasonably close.

The rare-value estimate was substantially high, but the absence of an alternative access path meant that both queries still had to scan the complete clustered index.

## Experimental Index

The experiment created this noncovering index:

```sql
CREATE NONCLUSTERED INDEX IX_TelemetryEvent_EventType_EventTime
ON telemetry.TelemetryEvent
(
    EventType,
    EventTime
);
```

The index intentionally omitted `SpeedKph` and `BatteryVoltage`.

A query using this index would therefore need clustered Key Lookups to retrieve those aggregate inputs.

This created a cost-based choice between:

- Seeking and performing repeated Key Lookups.
- Scanning the clustered index once.

## Index Characteristics

| Property | Result |
|---|---:|
| Index rows | 1,000,000 |
| Reserved space | 20.45 MB |
| Used space | 20.38 MB |
| Creation time | 3,977 ms |
| Statistics rows sampled | 1,000,000 |
| Histogram steps | 5 |
| Modification counter | 0 |

The statistics associated with the newly built index examined all 1,000,000 rows.

### Full-scan Index Histogram

| EventType | Equal rows |
|---:|---:|
| 1 | 720,000 |
| 2 | 100,000 |
| 3 | 80,000 |
| 4 | 60,000 |
| 5 | 40,000 |

The index histogram represented the leading `EventType` distribution exactly.

## Plan Selection with the Experimental Index

After creating the index, the same two queries produced different plans.

| EventType | Plan | Logical reads | CPU time | Elapsed time |
|---:|---|---:|---:|---:|
| 1 | Clustered Index Scan | 7,380 | 141 ms | 104 ms |
| 5 | Index Seek, Nested Loops, Key Lookup | 675 | 15 ms | 41 ms |

The common query ignored the available nonclustered index.

The rare query used the index and performed one clustered Key Lookup for every qualifying row.

## Common-Value Plan Analysis

The common-value plan used a Clustered Index Scan.

| Operator property | Value |
|---|---:|
| Estimated rows returned | 4,260.82 |
| Actual rows returned | 3,870 |
| Estimated rows to be read | 1,000,000 |
| Actual rows read | 1,000,000 |
| Estimate error | +10.10% |

The optimizer estimated that thousands of qualifying rows would require thousands of random clustered Key Lookups.

It considered a single sequential clustered scan less expensive and therefore did not use the experimental index.

This was a reasonable choice for the estimated and actual cardinalities.

## Rare-Value Plan Analysis

The rare-value plan used:

```text
Index Seek → Nested Loops → Key Lookup
```

### Index Seek properties

| Operator property | Value |
|---|---:|
| Estimated rows returned | 1,004.29 |
| Actual rows returned | 216 |
| Estimated rows to be read | 1,004.29 |
| Actual rows read | 216 |
| Estimate error | +364.95% |
| Estimate-to-actual factor | 4.65 |

The seek used both `EventType` and `EventTime` to delimit the required interval.

All 216 index rows read qualified for the query.

### Key Lookup properties

| Operator property | Value |
|---|---:|
| Estimated executions | 1,004.29 |
| Actual executions | 216 |
| Estimated total rows | 1,004.29 |
| Actual total rows | 216 |
| Rows returned per execution | 1 |

The cardinality overestimate propagated from the Index Seek through Nested Loops to the Key Lookup.

Even when expecting approximately 1,004 lookups, SQL Server estimated that this plan would be less expensive than scanning the clustered index.

The estimate was inaccurate, but the resulting plan was still appropriate for the actual 216 qualifying rows.

## Rare-Value Improvement

Compared with its no-index baseline, the rare-value plan produced:

| Metric | Baseline | Experimental index | Reduction |
|---|---:|---:|---:|
| Logical reads | 7,380 | 675 | 90.85% |
| CPU time | 78 ms | 15 ms | 80.77% |
| Elapsed time | 88 ms | 41 ms | 53.41% |

The elapsed-time result is an observed local measurement rather than a production-capacity claim.

## Why Exact Leading-Key Counts Did Not Produce Exact Combined Estimates

The index histogram contains exact counts for `EventType`, its leading key.

However, SQL Server statistics do not contain a separate conditional histogram describing every `EventTime` distribution within every `EventType`.

The optimizer must estimate the conjunction of:

- An equality predicate on `EventType`.
- A range predicate on `EventTime`.

It uses available histograms, density information, and cardinality-estimator assumptions to model the relationship between those columns.

As a result:

- The common combination was estimated reasonably well.
- The rare combination was overestimated by approximately 4.65 times.

Multi-column statistics can provide useful density information, but their histogram still belongs only to the leading statistics column.

## Why `OPTION (RECOMPILE)` Matters

`OPTION (RECOMPILE)` ensures that the optimizer evaluates each literal separately.

This experiment therefore demonstrates data-skew-aware compilation rather than parameter sniffing or cached-plan reuse.

The next parameter-sensitivity experiment can remove that protection and evaluate what happens when a plan compiled for one value is reused for another.

## Cost-Based Plan Choice

The experiment does not rely on a fixed universal Key Lookup threshold.

SQL Server compares estimated costs based on factors including:

- Estimated qualifying rows.
- Index depth and width.
- Lookup cost.
- Clustered-index size.
- CPU cost.
- Available predicates.
- Parallelism alternatives.

For this workload:

- Approximately 4,261 estimated common rows favored a scan.
- Approximately 1,004 estimated rare rows favored a seek with lookups.

The optimizer selected different plans from the same available indexes because the estimated cardinalities were different.

## Cleanup and Validation

The cleanup script removed `IX_TelemetryEvent_EventType_EventTime`.

| Measurement | Result |
|---|---:|
| Index existed before cleanup | Yes |
| Final index status | Removed |
| Cleanup time | 92 ms |

Dropping the index also removed its associated index statistics.

The original automatic `EventType` statistic remained:

| Property | Value |
|---|---:|
| Automatically created | Yes |
| Rows sampled | 176,319 |
| Histogram steps | 5 |

The independent validation script subsequently produced:

| Validation result | Value |
|---|---:|
| Total checks | 45 |
| Passed checks | 45 |
| Failed checks | 0 |
| Overall result | PASS |

This confirms that the experiment restored the original index and statistics state without altering permanent data.

## Reproduction Files

Execute or inspect the files in this order:

1. [`00-inspect-skew-and-statistics.sql`](00-inspect-skew-and-statistics.sql)
2. [`01-select-test-window.sql`](01-select-test-window.sql)
3. [`02-capture-no-index-baseline.sql`](02-capture-no-index-baseline.sql)
4. [`02-no-index-skew-baseline.sqlplan`](02-no-index-skew-baseline.sqlplan)
5. [`03-create-eventtype-eventtime-index.sql`](03-create-eventtype-eventtime-index.sql)
6. [`04-compare-common-and-rare-values.sql`](04-compare-common-and-rare-values.sql)
7. [`04-skew-aware-plan-choice.sqlplan`](04-skew-aware-plan-choice.sqlplan)
8. [`05-drop-experimental-index.sql`](05-drop-experimental-index.sql)

The inspection and test-window scripts do not modify permanent data. The cleanup script is safe to execute more than once.

## Limitations

- Measurements come from a local resource-constrained workstation.
- The retained measurements used a warm data cache.
- Only two `EventType` values and one date interval were compared.
- The experimental index was intentionally noncovering.
- Short elapsed times are sensitive to workstation and client activity.
- Concurrent workloads were not evaluated.
- Insert, update, and index-maintenance overhead was not benchmarked.
- Cached-plan reuse was intentionally excluded.
- Results are comparative laboratory measurements, not production-capacity claims.

## Conclusion

The existing sampled histogram represented the skewed `EventType` distribution accurately, and the experimental index histogram captured the leading-key counts exactly.

Nevertheless, combined predicates on `EventType` and `EventTime` required cardinality-estimator assumptions. The common value was estimated within approximately 10 percent, while the rare value was overestimated by approximately 4.65 times.

Those estimates produced different cost-based decisions from the same available indexes:

- The common value used a Clustered Index Scan.
- The rare value used an Index Seek with 216 Key Lookups.

The rare-value plan reduced logical reads by 90.85 percent while preserving identical results.

The experiment demonstrates that cardinality estimates do not need to be perfect to influence a useful plan choice, but understanding their errors is essential for interpreting plan behavior and anticipating parameter-sensitive workloads.
