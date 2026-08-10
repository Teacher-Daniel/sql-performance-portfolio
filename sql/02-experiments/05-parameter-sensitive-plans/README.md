# Experiment 05: Parameter-Sensitive Plans

## Status

Completed.

## Objective

This experiment examines how SQL Server handles parameter-sensitive
queries when different parameter values require different physical
execution plans.

The experiment compares:

- Ordinary parameter sniffing and cached-plan reuse.
- Independent literal optimization with `OPTION (RECOMPILE)`.
- Queries that are ineligible for Parameter Sensitive Plan optimization.
- Equality predicates that do not meet the internal PSP skewness threshold.
- An extreme equality distribution that produces a dispatcher and multiple
  query variants.

The primary questions are:

1. What happens when a plan compiled for a common value is reused for a
   rare value?
2. What happens when a seek-and-lookup plan compiled for a rare value is
   reused for a common value?
3. Does the existence of different optimal plans guarantee PSP activation?
4. Which predicate and skew conditions prevent PSP activation?
5. How does SQL Server expose dispatchers and query variants in execution
   plans, Query Store, and Extended Events?

## Environment

| Property | Value |
|---|---|
| SQL Server instance | `SQL2025LAB` |
| Product version | 17.0.4065.4 |
| Database | `FleetTelemetryLab` |
| Compatibility level | 170 |
| Query Store state | `READ_WRITE` |
| Query Store capture mode | `AUTO` |
| Parameter sniffing | Enabled |
| Parameter Sensitive Plan optimization | Enabled |
| Base telemetry rows | 1,000,000 |

SQL Server 2025 and compatibility level 170 were used throughout the
experiment.

## Executive Summary

The experiment produced four distinct optimizer behaviors.

| Stage | Predicates or distribution | Result |
|---|---|---|
| Original telemetry query | Equality plus date ranges | PSP skipped: `UnsupportedPredicateType` |
| Equality fixture | 3,870 common rows and 216 rare rows | PSP skipped: `SkewnessThresholdNotMet` |
| High-skew fixture | 720,000 common rows and 216 rare rows | PSP skipped: `SkewnessThresholdNotMet` |
| Extreme-skew fixture | 999,999 common rows and 1 rare row | Dispatcher and two query variants |

For the extreme distribution:

- PSP disabled: the rare value reused a scan and performed 8,022 logical
  reads.
- PSP enabled: the rare value used an Index Seek with one Key Lookup and
  performed 6 logical reads.
- Logical reads for the rare value decreased by 99.93 percent.
- Query Store recorded one dispatcher and two variants.
- Extended Events reported one interesting predicate with
  `Skewness = 999999.00`.
- PSP optimization was reported as supported.

The experiment also demonstrated that different independently optimal
plans do not, by themselves, guarantee PSP activation.

## Methodology

The experiment was performed in the following stages:

1. Inspect the SQL Server, database, Query Store, index, statistics, and
   object state.
2. Create a noncovering index and two stored procedures for the original
   telemetry query.
3. Disable PSP for one procedure while preserving ordinary parameter
   sniffing and plan reuse.
4. Compile the classic plan with the common value and reuse it for the rare
   value.
5. Compile the classic plan with the rare value and reuse it for the common
   value.
6. Execute the original query with PSP enabled.
7. Diagnose why the original query was not eligible.
8. Create an equality-only fixture using the original daily cardinalities.
9. Verify that common and rare literals independently produce different
   plans.
10. Test PSP against the moderate equality distribution.
11. Diagnose the PSP skewness-threshold result.
12. Create a second equality-only fixture with a much larger frequency
    difference.
13. Verify independent scan and seek plans.
14. Test PSP against the 720,000-to-216 distribution.
15. Diagnose the second skewness-threshold result.
16. Escalate the same experimental table to a 999,999-to-1 distribution.
17. Verify independent optimal plans again.
18. Capture classic common-first reuse with PSP disabled.
19. Enable PSP and capture the dispatcher and both variants.
20. Capture the positive parameter-sensitivity Extended Event.
21. Remove every experimental object.
22. Run the independent 45-check database validation script.

Actual execution plans were retained for every stage that compared physical
plans.

## Original Telemetry Query

The first test used the same aggregate query as the preceding cardinality
estimation experiment.

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
WHERE EventType = @EventType
  AND EventTime >= '2024-12-06T00:00:00'
  AND EventTime <  '2024-12-07T00:00:00';
```

The tested values were:

| Parameter | Meaning | Actual rows |
|---:|---|---:|
| 1 | Common value | 3,870 |
| 5 | Rare value | 216 |

The same noncovering index was available to both values:

```sql
CREATE NONCLUSTERED INDEX IX_TelemetryEvent_EventType_EventTime
ON telemetry.TelemetryEvent
(
    EventType,
    EventTime
);
```

The index omitted `SpeedKph` and `BatteryVoltage`.

A selective plan therefore required clustered Key Lookups to retrieve the
aggregate inputs.

## Stored Procedures

Two procedures used the same statement and parameter.

### Classic procedure

The classic procedure included:

```sql
USE HINT('DISABLE_PARAMETER_SENSITIVE_PLAN')
```

This hint disabled PSP but did not disable:

- Parameter sniffing.
- Cached-plan reuse.
- Cardinality estimation based on the compiled parameter.
- Ordinary cost-based plan selection.

### PSP-eligible procedure

The second procedure contained no:

- Recompile hint.
- Optimize-for hint.
- Parameter-sniffing-disabling hint.
- PSP-disabling hint.

It therefore allowed the database and optimizer configuration to determine
whether PSP should be used.

## Classic Common-First Reuse

The first classic sequence was:

```text
Common value 1 compiles → Rare value 5 reuses
```

The common value compiled a parallel Clustered Index Scan.

| Execution | Compiled value | Actual value | Plan | Logical reads |
|---|---:|---:|---|---:|
| 1 | 1 | 1 | Clustered Index Scan | 7,380 |
| 2 | 1 | 5 | Reused Clustered Index Scan | 7,380 |

The cached plan reported:

| Property | Value |
|---|---:|
| Execution count | 2 |
| Compiled parameter | `(1)` |
| Common estimated rows | 4,260.82 |
| Common actual rows | 3,870 |
| Rare actual rows during reuse | 216 |

The rare execution had zero parse-and-compile time.

It reused the common-value scan and read the complete clustered index even
though an independently optimized rare value could use the nonclustered
index.

## Classic Rare-First Reuse

The reverse sequence was:

```text
Rare value 5 compiles → Common value 1 reuses
```

The rare value compiled:

```text
Index Seek → Nested Loops → Key Lookup
```

| Execution | Compiled value | Actual value | Plan | Logical reads |
|---|---:|---:|---|---:|
| 1 | 5 | 5 | Seek and Key Lookup | 675 |
| 2 | 5 | 1 | Reused seek-and-lookup plan | 11,874 |

The cached plan reported:

| Property | Value |
|---|---:|
| Execution count | 2 |
| Compiled parameter | `(5)` |
| Minimum procedure logical reads | 721 |
| Maximum procedure logical reads | 12,376 |

The common value performed 3,870 Key Lookups.

Compared with its independently appropriate 7,380-read scan, the reused
rare-value plan increased common-value logical reads by 60.89 percent.

This demonstrates the two directions of parameter sensitivity:

- A scan can be wasteful for a rare value.
- Repeated Key Lookups can be wasteful for a common value.

## Why the Original Query Did Not Produce PSP

The PSP-enabled procedure was recompiled and executed for both values.

Both executions used a Clustered Index Scan and performed 7,380 logical
reads.

Query Store contained:

| Object | Count |
|---|---:|
| Dispatcher plans | 0 |
| Query variants | 0 |

The diagnostic Extended Events session captured:

| Event | Reason |
|---|---|
| `parameter_sensitive_plan_optimization_skipped_reason` | `UnsupportedPredicateType` |

The resolved T-SQL stack identified:

```text
telemetry.usp_EventTypeSummary_Psp
```

The statement combined:

- An equality predicate on `EventType`.
- A lower-bound range predicate on `EventTime`.
- An upper-bound range predicate on `EventTime`.

PSP currently operates on equality predicates. On this SQL Server 2025
build, the range predicates caused the complete statement to be classified
as unsupported for PSP.

This result required an equality-only fixture.

## Equality-Only Fixture

The first independent fixture was:

```text
telemetry.PspEqualityEvent
```

It preserved the selected-day cardinalities while assigning all other rows
to key zero.

### Distribution

| SensitivityKey | Rows | Percentage |
|---:|---:|---:|
| 0 | 994,657 | 99.4657% |
| 1 | 3,870 | 0.3870% |
| 2 | 528 | 0.0528% |
| 3 | 414 | 0.0414% |
| 4 | 315 | 0.0315% |
| 5 | 216 | 0.0216% |

The common tested value occurred approximately 17.92 times as often as the
rare tested value.

### Fixture characteristics

| Object | Rows | Reserved space | Used space |
|---|---:|---:|---:|
| Clustered index | 1,000,000 | 61.26 MB | 61.19 MB |
| Nonclustered index | 1,000,000 | 14.57 MB | 14.55 MB |

The nonclustered index statistics:

| Property | Value |
|---|---:|
| Rows | 1,000,000 |
| Rows sampled | 1,000,000 |
| Histogram steps | 6 |
| Modification counter | 0 |

The histogram represented every equality count exactly.

## Equality-Only Independent Plans

`OPTION (RECOMPILE)` was used to optimize each literal independently.

| Value | Actual rows | Plan | Logical reads | CPU | Elapsed |
|---:|---:|---|---:|---:|---:|
| 1 | 3,870 | Clustered Index Scan | 7,898 | 78 ms | 177 ms |
| 5 | 216 | Index Seek and Key Lookup | 675 | 0 ms | 139 ms |

Both estimated cardinalities matched the actual cardinalities.

The rare seek reduced logical reads by approximately 91.45 percent compared
with the scan.

This confirmed that the workload was parameter-sensitive at the physical
plan level.

## Equality-Only PSP Attempt

The PSP-enabled equality procedure was then compiled for the common value
and executed for both values.

| Value | Plan | Logical reads | CPU | Elapsed |
|---:|---|---:|---:|---:|
| 1 | Clustered Index Scan | 7,898 | 125 ms | 218 ms |
| 5 | Reused Clustered Index Scan | 7,898 | 126 ms | 210 ms |

Query Store contained no dispatcher and no query variants.

Extended Events reported:

```text
SkewnessThresholdNotMet
```

The stack resolved to:

```text
telemetry.usp_PspEqualitySummary_Psp
```

This showed that:

- The statement used a supported equality predicate.
- Different independently optimal plans existed.
- PSP still declined to create a dispatcher.

The 17.92-to-1 tested frequency difference did not meet the internal PSP
criterion.

## High-Skew Fixture

A second fixture increased the tested frequency difference substantially.

```text
telemetry.PspHighSkewEvent
```

### Initial distribution

| SkewKey | Rows | Percentage |
|---:|---:|---:|
| 0 | 279,784 | 27.9784% |
| 1 | 720,000 | 72.0000% |
| 5 | 216 | 0.0216% |

The common tested value occurred approximately 3,333.33 times as often as
the rare value.

### Fixture characteristics

| Object | Rows | Reserved space | Used space |
|---|---:|---:|---:|
| Clustered index | 1,000,000 | 62.26 MB | 62.16 MB |
| Nonclustered index | 1,000,000 | 14.57 MB | 14.55 MB |

Fixture creation required 8,953 ms.

The nonclustered statistics:

| Property | Value |
|---|---:|
| Rows | 1,000,000 |
| Rows sampled | 1,000,000 |
| Histogram steps | 3 |
| Modification counter | 0 |

## High-Skew Independent Plans

The common and rare literals again produced different plans.

| Value | Actual rows | Plan | Logical reads | CPU | Elapsed |
|---:|---:|---|---:|---:|---:|
| 1 | 720,000 | Clustered Index Scan | 8,022 | 703 ms | 402 ms |
| 5 | 216 | Index Seek and Key Lookup | 675 | 16 ms | 194 ms |

The estimates matched the actual row counts.

The rare seek reduced logical reads by 91.59 percent compared with the scan.

## High-Skew PSP Attempt

The PSP-enabled high-skew procedure was compiled for the common value.

| Value | Plan | Logical reads | CPU | Elapsed |
|---:|---|---:|---:|---:|
| 1 | Clustered Index Scan | 8,022 | 656 ms | 416 ms |
| 5 | Reused Clustered Index Scan | 8,022 | 125 ms | 232 ms |

Query Store reported:

| Object | Count |
|---|---:|
| Dispatcher plans | 0 |
| Query variants | 0 |

Extended Events again reported:

```text
SkewnessThresholdNotMet
```

The captured stack matched:

```text
telemetry.usp_PspHighSkewSummary_Psp
```

Even a 3,333.33-to-1 tested frequency difference did not cause PSP to
generate variants on this build.

This demonstrates that a simple ratio between two tested values is not a
published substitute for SQL Server's internal skewness calculation.

## Escalation to Extreme Skew

The same high-skew table was modified rather than creating another table.

Only `SkewKey` values changed.

The table, index, stored procedures, query shape, selected columns, and
aggregate expressions remained unchanged.

### Final distribution

| SkewKey | Rows | Percentage |
|---:|---:|---:|
| 1 | 999,999 | 99.9999% |
| 5 | 1 | 0.0001% |

The escalation:

| Property | Value |
|---|---:|
| Update operations | 280,001 |
| Deterministic rare row ID | 1 |
| Escalation time | 19,583 ms |
| Statistics rows sampled | 1,000,000 |
| Histogram steps | 2 |
| Modification counter | 0 |

The final histogram contained:

| RANGE_HI_KEY | EQ_ROWS |
|---:|---:|
| 1 | 999,999 |
| 5 | 1 |

## Extreme-Skew Independent Plans

Each literal was first optimized with `OPTION (RECOMPILE)`.

| Value | Actual rows | Estimated rows | Plan | Logical reads |
|---:|---:|---:|---|---:|
| 1 | 999,999 | 999,999 | Clustered Index Scan | 8,022 |
| 5 | 1 | 1 | Index Seek and one Key Lookup | 6 |

The rare plan read only six logical pages.

Compared with the scan, this represented a 99.93 percent reduction.

## Extreme-Skew Classic Reuse

PSP was disabled while ordinary parameter sniffing remained enabled.

The common value compiled first.

| Execution | Compiled value | Actual value | Plan | Logical reads |
|---|---:|---:|---|---:|
| 1 | 1 | 1 | Clustered Index Scan | 8,022 |
| 2 | 1 | 5 | Reused Clustered Index Scan | 8,022 |

The cached procedure plan reported:

| Property | Value |
|---|---:|
| Execution count | 2 |
| Compiled parameter | `(1)` |
| Minimum procedure logical reads | 8,022 |
| Maximum procedure logical reads | 8,024 |
| PSP markers | 0 |

During rare-value reuse:

- Estimated rows remained 999,999.
- Actual rows were 1.
- The estimate-to-actual factor was 999,999.
- Parse-and-compile time was zero.
- The complete clustered index was read.

The reused scan performed approximately 1,337 times as many logical reads as
the independently optimized six-read plan.

## Extreme-Skew PSP Result

The PSP-enabled procedure was recompiled and executed in this order:

1. Initialize the common-value range.
2. Initialize the rare-value range.
3. Measure the common value.
4. Measure the rare value.

### Runtime measurements

| Value | PSP plan | Logical reads | CPU | Elapsed |
|---:|---|---:|---:|---:|
| 1 | Parallel Clustered Index Scan | 8,022 | 641 ms | 557 ms |
| 5 | Serial Index Seek and one Key Lookup | 6 | 16 ms | 188 ms |

The rare-value PSP variant reduced logical reads from 8,022 to 6:

```text
Reduction = 99.93%
```

Short elapsed times were influenced by workstation, scheduler, client, and
actual-plan-capture activity. The experiment therefore treats logical
reads and physical plan selection as the primary comparative evidence.

## Query Store Dispatcher and Variants

Query Store recorded one dispatcher and two query variants.

| Relationship | Plan type | Plan ID | Query ID | Compiled value | Access operator | Parallel | Executions |
|---|---|---:|---:|---:|---|---:|---:|
| Dispatcher | Dispatcher Plan | 107 | 584 | — | — | Yes | — |
| Common variant | Query Variant Plan | 108 | 657 | `(1)` | Clustered Index Scan | Yes | 2 |
| Rare variant | Query Variant Plan | 109 | 658 | `(5)` | Index Seek | No | 2 |

Both variants referenced:

| Property | Result |
|---|---:|
| Parent query ID | 584 |
| Dispatcher plan ID | 107 |
| `ParameterSensitivePredicate` present | Yes |
| `PLAN PER VALUE` present | Yes |

The saved actual plan contained:

| ShowPlan marker | Count |
|---|---:|
| `<Dispatcher>` | 4 |
| `<ParameterSensitivePredicate` | 4 |
| `PLAN PER VALUE(ObjectID` | 4 |
| `QueryVariantID="1"` | 2 |
| `QueryVariantID="3"` | 2 |

The variant identifiers represent dispatcher ranges rather than literal
parameter values.

## Positive Extended Events Evidence

The successful extreme-skew compilation produced:

```text
query_with_parameter_sensitivity
```

The event payload contained:

| Field | Value |
|---|---|
| `interesting_predicate_count` | 1 |
| `interesting_predicate_details` | `{"Predicates":[{"ColumnId":2,"TableId":2085582468,"Skewness":999999.00}]}` |
| `psp_optimization_supported` | `true` |
| `query_type` | 193 |

No `parameter_sensitive_plan_optimization_skipped_reason` event was
produced.

The T-SQL stack resolved to:

```text
telemetry.usp_PspHighSkewSummary_Psp
```

This establishes a complete chain of evidence:

```text
Histogram skew
    → Interesting equality predicate
    → PSP supported
    → Dispatcher
    → Common and rare variants
    → Different physical plans
```

## Threshold Findings

The experiment does not claim to discover a universal numeric PSP threshold.

The observed results were:

| Tested scenario | Frequency relationship | PSP result |
|---|---:|---|
| Original query with ranges | 3,870 versus 216 | `UnsupportedPredicateType` |
| Equality fixture | 3,870 versus 216 | `SkewnessThresholdNotMet` |
| High-skew fixture | 720,000 versus 216 | `SkewnessThresholdNotMet` |
| Extreme-skew fixture | 999,999 versus 1 | Dispatcher and variants |

For the successful case, Extended Events exposed:

```text
Skewness = 999999.00
```

SQL Server evaluates PSP candidacy using internal calculations based on
statistics histograms and optimizer rules.

Those internal thresholds and formulas should not be replaced with a fixed
lookup-count or value-frequency rule.

## Why Different Optimal Plans Were Not Enough

Both equality-only fixtures produced:

- A scan for the common value.
- A seek and lookups for the rare value.
- Exact independent cardinality estimates.
- Large logical-read differences.

Nevertheless, PSP did not activate until the extreme distribution.

This distinction is important:

```text
Parameter-sensitive physical behavior
```

does not automatically imply:

```text
PSP dispatcher generation
```

The query must also meet SQL Server's internal candidacy and skewness
criteria.

## Why `OPTION (RECOMPILE)` Was Used

`OPTION (RECOMPILE)` was used only in the plan-separation validation scripts.

Its purpose was to answer:

```text
Would SQL Server independently choose different plans for these literals?
```

It was deliberately absent from:

- Classic cached-plan procedures.
- PSP-eligible procedures.

A recompile hint prevents the cached dispatcher-and-variant behavior being
studied.

## Query Store Methodology

Query Store was initially configured as:

```text
READ_WRITE / AUTO
```

For dispatcher-and-variant capture, the scripts temporarily changed the
capture mode to:

```text
ALL
```

Every script used `TRY/CATCH` protection to restore:

```text
READ_WRITE / AUTO
```

before completion or error propagation.

The final cleanup confirmed that Query Store remained in its original
configuration.

Historical Query Store records generated by the experiment were retained as
normal monitoring telemetry and remain subject to the configured retention
policy.

## Extended Events Methodology

Temporary server-level sessions captured:

- `parameter_sensitive_plan_optimization_skipped_reason`
- `query_with_parameter_sensitivity`

Every diagnostic script:

1. Verified that its session name did not already exist.
2. Created and started the session.
3. Recompiled and executed the target procedure.
4. Captured the ring-buffer XML.
5. Stopped the session.
6. Dropped the session.
7. Resolved the T-SQL stack.
8. Verified that no session remained.

The cleanup script also removed any remaining session whose name began with:

```text
Experiment05_
```

No diagnostic session remained after the experiment.

## Result Consistency

Common and rare executions returned the same aggregate results regardless of
whether they used:

- A scan.
- A seek and Key Lookup.
- A reused cached plan.
- A PSP query variant.
- `OPTION (RECOMPILE)`.

The experimental changes affected access paths and plan reuse, not query
semantics.

## Cleanup

The cleanup script removed nine objects:

| Object type | Count |
|---|---:|
| Stored procedures | 6 |
| Experimental tables | 2 |
| Experimental index on `TelemetryEvent` | 1 |
| Total | 9 |

Every object existed before cleanup and returned:

```text
ExistsAfter = 0
```

Additional cleanup results:

| Property | Result |
|---|---:|
| Remaining Experiment 05 objects | 0 |
| Remaining Experiment 05 event sessions | 0 |
| Final `TelemetryEvent` indexes | Original clustered primary key only |
| Final `TelemetryEvent` rows | 1,000,000 |
| Query Store | `READ_WRITE / AUTO` |
| Cleanup time | 2,446 ms |

## Statistics Preservation

Dropping the experimental index removed its associated index statistics.

The original automatic `EventType` statistic remained:

| Property | Value |
|---|---:|
| Automatically created | Yes |
| Table rows | 1,000,000 |
| Rows sampled | 176,319 |
| Histogram steps | 5 |
| Modification counter | 0 |

No permanent source data was changed.

Only the experiment-owned fixture tables were populated and modified.

## Independent Database Validation

After cleanup, the repository's independent validator produced:

| Validation result | Value |
|---|---:|
| Total checks | 45 |
| Passed checks | 45 |
| Failed checks | 0 |
| Overall result | PASS |

The validation included:

- Database configuration.
- Query Store state.
- Every expected base-table row count.
- Foreign keys and check constraints.
- Referential integrity.
- Telemetry distributions.
- Alert distributions.
- Data-quality rules.

## Reproduction Files

Execute or inspect the files in this order:

1. [`00-inspect-psp-environment.sql`](00-inspect-psp-environment.sql)
2. [`01-create-psp-test-objects.sql`](01-create-psp-test-objects.sql)
3. [`02-capture-classic-common-first.sql`](02-capture-classic-common-first.sql)
4. [`02-classic-common-first.sqlplan`](02-classic-common-first.sqlplan)
5. [`03-capture-classic-rare-first.sql`](03-capture-classic-rare-first.sql)
6. [`03-classic-rare-first.sqlplan`](03-classic-rare-first.sqlplan)
7. [`04-capture-psp-ineligible-range-predicates.sql`](04-capture-psp-ineligible-range-predicates.sql)
8. [`04-psp-ineligible-range-predicates.sqlplan`](04-psp-ineligible-range-predicates.sqlplan)
9. [`05-diagnose-psp-eligibility.sql`](05-diagnose-psp-eligibility.sql)
10. [`06-create-equality-psp-fixture.sql`](06-create-equality-psp-fixture.sql)
11. [`07-validate-equality-plan-separation.sql`](07-validate-equality-plan-separation.sql)
12. [`07-equality-plan-separation.sqlplan`](07-equality-plan-separation.sqlplan)
13. [`08-capture-equality-psp-skew-threshold-not-met.sql`](08-capture-equality-psp-skew-threshold-not-met.sql)
14. [`08-equality-psp-skew-threshold-not-met.sqlplan`](08-equality-psp-skew-threshold-not-met.sqlplan)
15. [`09-diagnose-equality-psp-eligibility.sql`](09-diagnose-equality-psp-eligibility.sql)
16. [`10-create-high-skew-psp-fixture.sql`](10-create-high-skew-psp-fixture.sql)
17. [`11-validate-high-skew-plan-separation.sql`](11-validate-high-skew-plan-separation.sql)
18. [`11-high-skew-plan-separation.sqlplan`](11-high-skew-plan-separation.sqlplan)
19. [`12-capture-high-skew-psp-skew-threshold-not-met.sql`](12-capture-high-skew-psp-skew-threshold-not-met.sql)
20. [`12-high-skew-psp-skew-threshold-not-met.sqlplan`](12-high-skew-psp-skew-threshold-not-met.sqlplan)
21. [`13-diagnose-high-skew-psp-eligibility.sql`](13-diagnose-high-skew-psp-eligibility.sql)
22. [`14-escalate-to-extreme-psp-skew.sql`](14-escalate-to-extreme-psp-skew.sql)
23. [`15-validate-extreme-skew-plan-separation.sql`](15-validate-extreme-skew-plan-separation.sql)
24. [`15-extreme-skew-plan-separation.sqlplan`](15-extreme-skew-plan-separation.sqlplan)
25. [`16-capture-extreme-classic-common-first.sql`](16-capture-extreme-classic-common-first.sql)
26. [`16-extreme-classic-common-first.sqlplan`](16-extreme-classic-common-first.sqlplan)
27. [`17-capture-extreme-skew-psp-dispatcher-and-variants.sql`](17-capture-extreme-skew-psp-dispatcher-and-variants.sql)
28. [`17-extreme-skew-psp-dispatcher-and-variants.sqlplan`](17-extreme-skew-psp-dispatcher-and-variants.sqlplan)
29. [`18-capture-extreme-psp-eligibility-event.sql`](18-capture-extreme-psp-eligibility-event.sql)
30. [`19-drop-experiment-objects.sql`](19-drop-experiment-objects.sql)

## Limitations

- Measurements were collected on a local resource-constrained workstation.
- Actual-plan capture adds profiling and client-processing overhead.
- Short elapsed times are sensitive to scheduler and workstation activity.
- Logical reads and plan shapes are more stable than elapsed time in this
  laboratory environment.
- The data is deterministic and synthetic.
- The successful 999,999-to-1 fixture is intentionally extreme.
- The experiment evaluates one SQL Server 2025 build and compatibility
  level 170.
- Internal PSP skewness thresholds and formulas are not documented.
- Only one sensitive equality parameter was evaluated at a time.
- Concurrent workloads were not tested.
- Query Store historical telemetry was retained.
- Results are comparative laboratory observations, not production-capacity
  claims.

## Conclusion

Ordinary parameter sniffing cached one physical plan for all parameter
values.

That behavior produced both classic failure modes:

- A scan compiled for a common value was reused for a rare value.
- A seek-and-lookup plan compiled for a rare value was reused for a common
  value.

Independent recompilation proved that the values required different
physical plans, but that alone did not guarantee PSP activation.

The original equality-and-range statement was rejected with:

```text
UnsupportedPredicateType
```

Two equality-only distributions were accepted structurally but rejected
with:

```text
SkewnessThresholdNotMet
```

Only the extreme equality distribution produced:

- One interesting predicate.
- `Skewness = 999999.00`.
- A dispatcher.
- A parallel common-value scan variant.
- A serial rare-value seek-and-lookup variant.

For the rare value, PSP reduced logical reads from 8,022 to 6 while
preserving identical results.

The experiment demonstrates that Parameter Sensitive Plan optimization is
not merely automatic multi-plan caching for every skewed query. It is a
selective optimizer feature governed by predicate eligibility, statistics,
internal skewness criteria, dispatcher ranges, and normal cost-based plan
selection.

## References

- [Parameter Sensitive Plan optimization](https://learn.microsoft.com/en-us/sql/relational-databases/performance/parameter-sensitive-plan-optimization?view=sql-server-ver17)
- [`sys.query_store_query_variant`](https://learn.microsoft.com/en-us/sql/relational-databases/system-catalog-views/sys-query-store-query-variant?view=sql-server-ver17)
- [`sys.query_store_plan`](https://learn.microsoft.com/en-us/sql/relational-databases/system-catalog-views/sys-query-store-plan-transact-sql?view=sql-server-ver17)
