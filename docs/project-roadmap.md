# Project Roadmap

This portfolio documents a practical learning path for analyzing and improving SQL Server query performance.

## Fixed Core Scope

The core portfolio contains exactly eight numbered performance experiments.

Five experiments are complete, and three experiments remain. Completing Experiment 08 and publishing `v1.0.0` will close the required portfolio scope.

Reaching `v1.0.0` means that the planned portfolio is complete. It does not imply that every SQL Server performance topic has been exhausted.

| # | Experiment | Primary competency | Status | Milestone |
|---:|---|---|---|---|
| 01 | [Date predicate SARGability](../sql/02-experiments/01-date-sargability/README.md) | Predicate formulation and efficient index access | Completed | Published |
| 02 | [Key Lookups and covering indexes](../sql/02-experiments/02-key-lookup-covering-index/README.md) | Lookup cost and index coverage | Completed | Published |
| 03 | [Composite index column order](../sql/02-experiments/03-composite-index-column-order/README.md) | Equality, range, and residual predicates | Completed | Published |
| 04 | [Cardinality estimates and data skew](../sql/02-experiments/04-cardinality-estimation-data-skew/README.md) | Statistics, estimates, and skew-aware plan choice | Completed | Published |
| 05 | [Parameter-sensitive plans](../sql/02-experiments/05-parameter-sensitive-plans/README.md) | Cached-plan reuse, PSP eligibility, dispatchers, and variants | Completed | Published |
| 06 | Join strategies and supporting indexes | Physical join selection under controlled cardinality and indexing conditions | Planned | `v0.8.0` |
| 07 | Memory grants, spills, and feedback | Runtime memory diagnostics and adaptive grant correction | Planned | `v0.9.0` |
| 08 | Query Store regression detection and recovery | Historical plan analysis and reversible performance stabilization | Planned | `v1.0.0` |

## Core Experiment Sequence

### Experiment 06: Join Strategies and Supporting Indexes

This experiment will:

- Compare physical join strategies under controlled row counts and indexing conditions.
- Interpret `Nested Loops`, `Hash Match`, and `Merge Join` choices without treating any one algorithm as universally superior.
- Measure the effect of supporting indexes on rows read, logical reads, CPU time, and elapsed time.
- Preserve equivalent results and restore the original database state.

Target release: `v0.8.0`.

### Experiment 07: Memory Grants, Spills, and Feedback

This experiment will:

- Capture a reproducible memory-grant mismatch involving a memory-consuming operator.
- Inspect granted, used, and required memory in actual execution plans.
- Measure spill behavior and its effect on execution.
- Observe Memory Grant Feedback across repeated executions.
- Restore all modified configuration and experimental objects.

Target release: `v0.9.0`.

### Experiment 08: Query Store Regression Detection and Recovery

This capstone experiment will:

- Establish a known-good query-performance baseline.
- Produce and capture a controlled plan regression.
- Use Query Store history to compare plans and runtime statistics.
- Apply and validate reversible plan forcing as a stabilization measure.
- Remove the forcing policy and restore the original database state.

Target release: `v1.0.0`.

## Learning Phases

### Phase 1: Git and GitHub Workflow

- Create a professional repository.
- Work with branches and meaningful commits.
- Review changes through pull requests.
- Tag stable project milestones.

### Phase 2: SQL Server Environment

- Prepare a reproducible sample database.
- Document the database structure and test conditions.
- Define the metrics used to compare query performance.

### Phase 3: Baseline Analysis

- Capture the original queries.
- Review actual execution plans.
- Record logical reads, execution time, and identified bottlenecks.

### Phase 4: Optimization Experiments

- Evaluate indexing strategies.
- Rewrite selected queries.
- Review statistics and cardinality estimates.
- Compare results against the baseline.
- Complete the eight experiments defined in the fixed core scope.

### Phase 5: Results and Conclusions

- Present before-and-after measurements.
- Explain each technical decision.
- Document limitations and possible future improvements.
- Summarize the portfolio-level findings.
- Publish the completed core portfolio as `v1.0.0`.

## Completion Criteria

The core portfolio is complete only when:

- All eight numbered experiments have status `Completed`.
- Every experiment includes reproducible scripts and relevant actual execution plans.
- Every experiment verifies result equivalence or explicitly documents any intentional semantic difference.
- Experimental objects and configuration changes are removed or restored.
- Independent database validation passes after cleanup.
- The English and Spanish repository navigation reflects all eight experiments.
- Portfolio-level results, limitations, and future possibilities are documented.
- The final reviewed state is merged into `main`.
- The annotated tag and GitHub Release `v1.0.0` are published.

## Optional Backlog

The following subjects are possible future extensions and are not part of the required eight-experiment scope:

- Columnstore indexes and batch-mode execution.
- Parallelism and Degree of Parallelism Feedback.
- Temporary tables, table variables, and deferred compilation.
- Optional Parameter Plan Optimization.
- Filtered indexes, compression, and partitioning.
- Blocking, isolation levels, and concurrency diagnostics.

Backlog items are not numbered, scheduled, or required for `v1.0.0`. Finishing a core experiment does not automatically promote a backlog item into the portfolio.

## Scope Change Rule

Any change to the number or subjects of the eight core experiments requires a dedicated documentation decision before implementation begins.

A future extension after `v1.0.0` must define its own purpose, finite scope, completion criteria, and release target.