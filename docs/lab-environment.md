# SQL Server Lab Environment

## Purpose

This local environment provides a controlled and reproducible workspace for analyzing SQL Server query performance. It is intended exclusively for development, testing, and portfolio demonstrations.

## Software

| Component | Version |
|---|---|
| Operating system | Windows 10 x64 |
| Database engine | SQL Server 2025 Standard Developer Edition |
| SQL Server build | 17.0.4065.4 (CU7) |
| Management tool | SQL Server Management Studio 21.6.17 |
| Authentication | Windows Authentication |

Standard Developer Edition was selected to keep the experiments aligned with the feature set commonly available in SQL Server Standard production environments.

## Instance Configuration

| Setting | Value |
|---|---|
| Instance name | `SQL2025LAB` |
| Service startup | Manual |
| SQL Server Agent startup | Manual |
| SQL Server Browser | Disabled |
| Collation | `Modern_Spanish_CI_AS` |
| Maximum server memory | 2,048 MB |
| Maximum degree of parallelism | 2 |
| Instant File Initialization | Enabled |

The instance is started only during lab sessions to avoid competing with other services on the workstation.

## TempDB Configuration

| Setting | Value |
|---|---|
| Data files | 4 |
| Initial size per data file | 64 MB |
| Data file autogrowth | 64 MB |
| Initial log size | 64 MB |
| Log autogrowth | 64 MB |
| Percentage growth | Disabled |

Fixed growth increments make file growth behavior more predictable during performance experiments.

## Hardware Constraints

| Resource | Available |
|---|---|
| Physical CPU cores | 2 |
| Logical processors | 4 |
| Installed memory | 8 GB |

The SQL Server memory and parallelism limits preserve resources for Windows, SSMS, and monitoring tools.

## Measurement Rules

Each experiment will:

- Run only against the `SQL2025LAB` instance.
- Record the database compatibility level.
- Capture the actual execution plan.
- Collect logical reads with `SET STATISTICS IO ON`.
- Collect elapsed and CPU time with `SET STATISTICS TIME ON`.
- Distinguish between cold-cache and warm-cache executions.
- Repeat measurements when appropriate.
- Record every schema, index, or query change.
- Compare results under the same test conditions.

## Validation

The script [`validate-environment.sql`](../sql/00-setup/validate-environment.sql) verifies the engine build, instance settings, TempDB files, service status, and hardware resources visible to SQL Server.

## Limitations

This is a resource-constrained, single-machine development environment. Results are suitable for comparative analysis but must not be interpreted as production-capacity benchmarks.
