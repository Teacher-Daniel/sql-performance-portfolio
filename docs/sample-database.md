# Fleet Telemetry Sample Database

## Purpose

`FleetTelemetryLab` is a synthetic SQL Server workload designed for repeatable query-performance experiments.

The business scenario represents a multi-country vehicle services platform that manages customers, vehicles, tracking devices, insurance policies, telemetry events, and operational alerts.

All records are generated locally. The project contains no proprietary, personal, or production data.

## Data Model

```mermaid
erDiagram
    CUSTOMER ||--o{ VEHICLE : owns
    VEHICLE ||--o{ POLICY : covered_by
    VEHICLE ||--o| DEVICE : uses
    DEVICE ||--o{ TELEMETRY_EVENT : emits
    TELEMETRY_EVENT ||--o{ ALERT : triggers
```

## Schemas and Tables

| Schema | Table | Purpose |
|---|---|---|
| `crm` | `Customer` | Synthetic customer accounts and country distribution |
| `fleet` | `Vehicle` | Vehicles associated with customers |
| `fleet` | `Device` | Telematics devices currently assigned to vehicles |
| `insurance` | `Policy` | Insurance coverage periods and insured amounts |
| `telemetry` | `TelemetryEvent` | Time-series location and vehicle-state events |
| `telemetry` | `Alert` | Operational alerts generated from telemetry events |

## Target Row Counts

| Table | Target rows |
|---|---:|
| `crm.Customer` | 20,000 |
| `fleet.Vehicle` | 40,000 |
| `fleet.Device` | 40,000 |
| `insurance.Policy` | 60,000 |
| `telemetry.TelemetryEvent` | 1,000,000 |
| `telemetry.Alert` | 120,000 |

The dataset is large enough to produce meaningful differences in logical reads and execution plans while remaining practical on the resource-constrained lab workstation.

## Data Characteristics

The generator will create deterministic and intentionally uneven distributions:

- Customers distributed across several Latin American country codes.
- Different numbers of vehicles per customer.
- Active, standby, and inactive devices.
- Current, expired, and cancelled policies.
- Uneven event volumes across devices and dates.
- Open, closed, and escalated alerts.
- Repeated values suitable for cardinality-estimation experiments.

These distributions support realistic selectivity and parameter-sensitivity scenarios.

## Planned Performance Scenarios

The database will support experiments involving:

1. Date predicates and SARGability.
2. Missing and covering indexes.
3. Key lookups.
4. Composite-index column order.
5. Cardinality estimates and data skew.
6. Parameter-sensitive queries.
7. Aggregations, sorts, and memory grants.
8. Statistics and plan changes.
9. Actual execution plans.
10. Query Store comparisons.

## Reproducibility Rules

- Database creation and data generation must be script-driven.
- Scripts must be safe to rerun when documented prerequisites are followed.
- Generated values must not depend on external services.
- Target row counts must be validated after loading.
- Schema and data changes must be committed separately.
- Performance experiments must not modify the original baseline silently.

## Scope and Limitations

The model prioritizes performance-learning scenarios over complete business functionality. It does not represent a production-ready insurance or telematics platform.

Performance results are comparative measurements from the local lab and are not production-capacity claims.
