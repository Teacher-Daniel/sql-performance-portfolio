# SQL Server Performance Portfolio

A hands-on portfolio documenting the analysis and optimization of SQL Server queries.

[Versión en español](README.es.md)

## Objectives

- Interpret actual execution plans.
- Identify query performance issues.
- Measure improvements using repeatable baselines.
- Document technical decisions and trade-offs.

## Roadmap

See the [project roadmap](docs/project-roadmap.md).

## Lab Environment

Review the [lab configuration](docs/lab-environment.md) and run the [environment validation script](sql/00-setup/validate-environment.sql).

## Sample Database

Review the [Fleet Telemetry sample database](docs/sample-database.md), including its build order, verified row counts, and validation results.

## Performance Experiments

| # | Experiment | Main finding | Status |
|---|---|---|---|
| 01 | [Date predicate SARGability](sql/02-experiments/01-date-sargability/README.md) | A half-open date range reduced logical reads by 82.0% compared with function-based filtering using the same index. | Completed |
