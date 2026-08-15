# Experiment 06: Join Strategies and Supporting Indexes

## Status

Completed for the `v0.8.0` milestone.

## Objective

This experiment evaluates how input cardinality and a supporting index
influence SQL Server's physical join selection.

The same logical inner join is tested with:

- One device and 25 matching telemetry events.
- All 40,000 devices and 1,000,000 matching telemetry events.
- No nonclustered index on the foreign-key column.
- A minimal nonclustered index on the foreign-key column.

No join hints are used.

The experiment demonstrates:

1. Why `Nested Loops` is not automatically efficient without a usable
   inner access path.
2. Why `Hash Match` is suitable for large unordered inputs but requires
   execution memory.
3. How ordered index access can make `Merge Join` cost-effective without
   explicit sorting.
4. Why operator names must be interpreted together with rows read,
   logical reads, memory grants, and input ordering.
5. How the same query can retain equivalent results while receiving
   different physical plans.

## Environment

- SQL Server 2025
- Product version: `17.0.4065.4`
- Database compatibility level: 170
- Maximum degree of parallelism: 2
- Cost threshold for parallelism: 5
- Actual execution plans enabled
- `SET STATISTICS IO ON`
- `SET STATISTICS TIME ON`
- One retained execution per measured script
- No forced cache clearing

See the [laboratory configuration](../../../docs/lab-environment.md) and
the [sample database documentation](../../../docs/sample-database.md)
for complete environment and dataset details.

## Dataset and Relationship

The experiment uses this trusted relationship:

```text
fleet.Device.DeviceId
    1 ─── 25
telemetry.TelemetryEvent.DeviceId
```

| Property | Result |
|---|---:|
| Device rows | 40,000 |
| TelemetryEvent rows | 1,000,000 |
| Minimum DeviceId | 1 |
| Maximum DeviceId | 40,000 |
| Minimum events per device | 25 |
| Maximum events per device | 25 |
| Foreign key disabled | No |
| Foreign key untrusted | No |

The telemetry loader assigns events circularly across devices. Every
device therefore contributes exactly 25 events, making the tested
cardinalities deterministic.

## Baseline Index and Statistics State

Before the experiment, the relevant indexes were:

| Table | Index | Type | Leading key |
|---|---|---|---|
| `fleet.Device` | `PK_fleet_Device` | Clustered, unique | `DeviceId` |
| `fleet.Device` | `UQ_fleet_Device_VehicleId` | Nonclustered, unique | `VehicleId` |
| `fleet.Device` | `UQ_fleet_Device_DeviceSerial` | Nonclustered, unique | `DeviceSerial` |
| `telemetry.TelemetryEvent` | `PK_telemetry_TelemetryEvent` | Clustered, unique | `TelemetryEventId` |

`TelemetryEvent.DeviceId` had no supporting nonclustered index.

SQL Server did have an automatically created statistic on that column:

| Property | Result |
|---|---:|
| Statistics name | `_WA_Sys_00000002_628FA481` |
| Automatically created | Yes |
| Table rows | 1,000,000 |
| Rows sampled | 176,319 |
| Histogram steps | 182 |
| Modification counter | 0 |

The optimizer therefore had cardinality information about `DeviceId`,
but it lacked a seekable and ordered access path on that key.

## Test Query

Both cardinality cases use this aggregate join:

```sql
SELECT
    COUNT_BIG(*) AS JoinedEventCount,
    SUM(CONVERT(bigint, d.VehicleId))
        AS VehicleIdChecksum
FROM fleet.Device AS d
INNER JOIN telemetry.TelemetryEvent AS te
    ON te.DeviceId = d.DeviceId
WHERE d.DeviceId <= 1
OPTION (RECOMPILE);
```

The broad case changes only the cutoff:

```sql
WHERE d.DeviceId <= 40000
```

`VehicleIdChecksum` serves two purposes:

- It verifies result equivalence before and after index creation.
- It deliberately references `fleet.Device`, preventing the trusted
  foreign key from making that table removable from the plan.

`OPTION (RECOMPILE)` lets SQL Server optimize each literal
independently. It is not a join hint.

## Methodology

The experiment was performed in this order:

1. Inspect the server, database, parallelism settings, trusted foreign
   key, indexes, statistics, row counts, and event distribution.
2. Confirm that `TelemetryEvent.DeviceId` has statistics but no
   supporting index.
3. Capture actual plans for the selective and broad joins.
4. Record result values, logical reads, CPU time, elapsed time,
   cardinality estimates, memory grants, and waits.
5. Create a minimal nonclustered index on
   `TelemetryEvent(DeviceId)`.
6. Inspect the index definition, size, statistics, and creation time.
7. Recompile and execute the same two queries.
8. Capture the index-supported plans without join hints.
9. Compare physical strategies and access methods.
10. Remove the experimental index.
11. Confirm that no nonclustered index remains on `TelemetryEvent`.
12. Run the independent 45-check database validator.

Each capture script was executed once. Cache state was not forcibly
reset, so logical reads and plan structure are stronger comparative
evidence than small timing differences.

## Result Consistency

Both index states returned identical results:

| Maximum DeviceId | Index state | Joined events | VehicleId checksum |
|---:|---|---:|---:|
| 1 | No supporting index | 25 | 25 |
| 1 | Supporting index | 25 | 25 |
| 40,000 | No supporting index | 1,000,000 | 20,000,500,000 |
| 40,000 | Supporting index | 1,000,000 | 20,000,500,000 |

The physical-plan changes did not alter query semantics.

## No-Supporting-Index Baseline

The two baseline statements shared this query hash:

```text
0x18134557841B6643
```

Their independently optimized plans differed because of cardinality.

### Selective baseline: Nested Loops with a full scan

For one device, SQL Server chose a parallel `Nested Loops` plan.

| Property | Result |
|---|---:|
| Estimated joined rows | 22.1752 |
| Actual joined rows | 25 |
| Degree of parallelism | 2 |
| Estimated subtree cost | 6.23509 |
| TelemetryEvent rows read | 1,000,000 |
| TelemetryEvent logical reads | 7,380 |
| Device logical reads | 50 |
| Actual-plan CPU time | 209 ms |
| Actual-plan elapsed time | 860 ms |
| Query plan hash | `0x369A7D469C645309` |

The `TelemetryEvent` clustered index was ordered by
`TelemetryEventId`, not `DeviceId`. SQL Server scanned all 1,000,000
events, retained the 25 qualifying rows, and then executed 25 clustered
seeks into `Device`.

This plan demonstrates that `Nested Loops` alone does not guarantee an
efficient selective join. Its effectiveness depends on an inexpensive
way to locate matching inner rows.

### Broad baseline: Hash Match

For all devices, SQL Server chose a parallel `Hash Match`.

| Property | Result |
|---|---:|
| Estimated joined rows | 1,000,000 |
| Actual joined rows | 1,000,000 |
| Degree of parallelism | 2 |
| Estimated subtree cost | 11.276 |
| TelemetryEvent rows read | 1,000,000 |
| TelemetryEvent logical reads | 7,380 |
| Device rows read | 40,000 |
| Device logical reads | 211 |
| Actual-plan CPU time | 1,179 ms |
| Actual-plan elapsed time after the grant | 984 ms |
| Query plan hash | `0x497E16D2F50FEAC7` |

The plan scanned:

- `UQ_fleet_Device_VehicleId` for the 40,000-device build input.
- `PK_telemetry_TelemetryEvent` for the 1,000,000-event probe input.

A hash join does not require its inputs to arrive in join-key order,
making it a reasonable choice for these large unordered inputs.

## Baseline Memory-Grant Wait

The broad hash-join execution recorded:

| Memory property | Result |
|---|---:|
| Requested memory | 17,656 KB |
| Granted memory | 17,656 KB |
| Maximum used memory | 2,624 KB |
| Grant wait time | 12,167 ms |
| Spill to tempdb | No |

`SET STATISTICS TIME` reported total elapsed time of 13,237 ms, while
the actual plan reported 984 ms of execution after the grant became
available.

The difference is primarily explained by the memory-grant wait.

This wait is preserved as an observed runtime condition, but it is not
treated as a stable measure of hash-join execution speed. Memory
availability depends on concurrent activity and server state.

## Experimental Index

The experiment created this minimal index:

```sql
CREATE NONCLUSTERED INDEX
    IX_TelemetryEvent_DeviceId_JoinExperiment
ON telemetry.TelemetryEvent
(
    DeviceId
);
```

The index contains no explicit included columns.

Its purpose is limited to providing:

- Direct access by `DeviceId`.
- Rows ordered by the join key.
- A narrower structure than the clustered index.

The design deliberately avoids repeating the covering-index comparison
from Experiment 02.

## Index Characteristics

| Property | Result |
|---|---:|
| Index rows | 1,000,000 |
| Reserved space | 17.51 MB |
| Used space | 17.47 MB |
| Creation time | 8,222 ms |
| Statistics rows | 1,000,000 |
| Statistics rows sampled | 1,000,000 |
| Histogram steps | 3 |
| Modification counter | 0 |

The index build created full-scan statistics on its leading key.

The baseline estimates were already close or exact, so the main
observed benefit came from the new access path and ordering rather than
from correcting a severe cardinality error.

## Index-Supported Plans

### Selective case: efficient Nested Loops

With the supporting index, the one-device query remained a
`Nested Loops` join, but its access pattern changed completely.

| Property | Result |
|---|---:|
| Estimated joined rows | 25 |
| Actual joined rows | 25 |
| Degree of parallelism | 1 |
| Estimated subtree cost | 0.0067247 |
| Device access | Clustered Index Seek |
| Device rows read | 1 |
| Device logical reads | 2 |
| TelemetryEvent access | Index Seek |
| TelemetryEvent rows read | 25 |
| TelemetryEvent logical reads | 3 |
| Actual-plan CPU time | 49 ms |
| Actual-plan elapsed time | 159 ms |
| Query plan hash | `0xDD99DBE58698134C` |

The join now starts with one `Device` row and performs one ordered seek
into the experimental index for its 25 events.

No join hint forced this change.

### Broad case: Merge Join

With the same supporting index, the 40,000-device query changed from
`Hash Match` to a serial `Merge Join`.

| Property | Result |
|---|---:|
| Estimated joined rows | 1,000,000 |
| Actual joined rows | 1,000,000 |
| Degree of parallelism | 1 |
| Estimated subtree cost | 5.90639 |
| Device access | Clustered Index Seek |
| Device rows read | 40,000 |
| Device logical reads | 290 |
| TelemetryEvent access | Index Seek |
| TelemetryEvent rows read | 1,000,000 |
| TelemetryEvent logical reads | 2,236 |
| Sort operators | 0 |
| Memory grant | 0 KB |
| Actual-plan CPU time | 664 ms |
| Actual-plan elapsed time | 708 ms |
| Query plan hash | `0x246079A564CD7AD8` |

Both inputs reported:

```text
Ordered = true
Scan direction = FORWARD
```

The merge operator reported:

```text
ManyToMany = false
```

Because both inputs arrived in `DeviceId` order, SQL Server performed
the merge without explicit `Sort` operators and without an execution
memory grant.

Although the plan labels both range accesses as seeks, the
`TelemetryEvent` seek still reads all 1,000,000 qualifying rows.
`Index Seek` should therefore not be interpreted as synonymous with
high selectivity.

## Comparative Results

### Selective join

| Measurement | Without index | With index | Change |
|---|---:|---:|---:|
| TelemetryEvent rows read | 1,000,000 | 25 | −99.9975% |
| TelemetryEvent logical reads | 7,380 | 3 | −99.96% |
| Device logical reads | 50 | 2 | −96.00% |
| Total logical reads | 7,430 | 5 | −99.93% |
| Actual-plan CPU time | 209 ms | 49 ms | −76.56% |
| Actual-plan elapsed time | 860 ms | 159 ms | −81.51% |
| Estimated subtree cost | 6.23509 | 0.0067247 | −99.89% |

The decisive improvement was not changing away from `Nested Loops`.
It was giving that join an efficient inner seek.

### Broad join

| Measurement | Without index | With index | Change |
|---|---:|---:|---:|
| Join strategy | Hash Match | Merge Join | Changed |
| TelemetryEvent logical reads | 7,380 | 2,236 | −69.70% |
| Device logical reads | 211 | 290 | +37.44% |
| Total logical reads | 7,591 | 2,526 | −66.72% |
| Actual-plan CPU time | 1,179 ms | 664 ms | −43.68% |
| Post-grant plan elapsed time | 984 ms | 708 ms | −28.05% |
| Estimated subtree cost | 11.276 | 5.90639 | −47.62% |
| Memory grant | 17,656 KB | 0 KB | Eliminated |

The ordered `Device` access required slightly more reads than the
narrower baseline scan, but the total read reduction remained 66.72%.

The 12,167-ms baseline grant wait is intentionally excluded from the
post-grant elapsed-time percentage.

## Why the Join Strategies Changed

The optimizer selected three meaningful plan patterns:

1. **Selective without support:** `Nested Loops` preserved the small
   qualifying result, but the missing foreign-key index forced a full
   telemetry scan.
2. **Broad without support:** `Hash Match` handled two large unordered
   inputs and used memory to build its hash structure.
3. **Selective with support:** `Nested Loops` became efficient because
   both sides could be reached through targeted seeks.
4. **Broad with support:** `Merge Join` became competitive because both
   inputs were already ordered by `DeviceId`.

No one join algorithm was universally best.

The appropriate choice depended on:

- Estimated input cardinality.
- Available access paths.
- Input ordering.
- Row width and I/O cost.
- Parallel alternatives.
- Memory requirements.

## Why Join Hints Were Not Used

The experiment intentionally avoids `LOOP JOIN`, `HASH JOIN`, and
`MERGE JOIN` hints.

A forced operator would prove that SQL Server can execute that
algorithm, but it would not demonstrate that the optimizer considers it
cost-effective under the tested conditions.

`OPTION (RECOMPILE)` changes compilation timing, not the permitted join
algorithms. SQL Server remained free to choose every physical plan.

## Cleanup and Validation

The cleanup script removed
`IX_TelemetryEvent_DeviceId_JoinExperiment`.

| Measurement | Result |
|---|---:|
| Index existed before cleanup | Yes |
| Final index status | Removed |
| Remaining TelemetryEvent nonclustered indexes | 0 |
| Cleanup time | 150 ms |

The independent database validator subsequently produced:

| Validation result | Value |
|---|---:|
| Total checks | 45 |
| Passed checks | 45 |
| Failed checks | 0 |
| Overall result | PASS |

This confirms that the experiment restored the original index state
without altering permanent data or expected database configuration.

## Reproduction Files

Execute or inspect the files in this order:

1. [`00-inspect-join-environment.sql`](00-inspect-join-environment.sql)
2. [`01-capture-no-supporting-index-baseline.sql`](01-capture-no-supporting-index-baseline.sql)
3. [`01-no-supporting-index-baseline.sqlplan`](01-no-supporting-index-baseline.sqlplan)
4. [`02-create-deviceid-join-index.sql`](02-create-deviceid-join-index.sql)
5. [`03-capture-index-supported-joins.sql`](03-capture-index-supported-joins.sql)
6. [`03-index-supported-join-strategies.sqlplan`](03-index-supported-join-strategies.sqlplan)
7. [`04-drop-experimental-index.sql`](04-drop-experimental-index.sql)
8. [`05-validate-sample-database.sql`](../../01-database/05-validate-sample-database.sql)

The inspection and capture scripts do not intentionally modify
permanent data, schema, indexes, or database configuration.

The index-creation script creates only the experiment-owned index. The
cleanup script validates its definition before removal and is safe to
execute more than once.

## Limitations

- Measurements come from one local, resource-constrained workstation.
- Each measured script was executed once.
- Cache state was not forcibly standardized.
- Actual-plan capture adds measurement overhead.
- Only an inner equality join and two cardinality cutoffs were tested.
- The deterministic 25-to-1 distribution does not model join-key skew.
- The index build also created full-scan statistics, although baseline
  estimates were already reasonably accurate.
- The broad baseline encountered a transient memory-grant wait.
- Index creation and storage were measured, but ongoing write and
  maintenance costs were not benchmarked.
- The aggregate query requires only the telemetry join key; included
  columns and Key Lookups are covered separately by Experiment 02.
- Join choices may differ across SQL Server versions, configurations,
  memory conditions, and concurrent workloads.
- Results are comparative laboratory evidence, not production-capacity
  claims.

## Conclusion

The experiment produced three naturally selected join patterns without
physical join hints.

For one device, `Nested Loops` appeared both before and after index
creation. Without a supporting index it read all 1,000,000 telemetry
rows; with the index it read only the 25 matching rows.

For all devices, the unordered baseline used a parallel `Hash Match`
and requested 17,656 KB of memory. The supporting index supplied both
a narrower access path and `DeviceId` ordering, allowing a serial
`Merge Join` with no sort and no memory grant.

The central result is not that one join operator defeated another. It
is that cardinality and physical design changed what each strategy
could do efficiently while preserving identical results.
