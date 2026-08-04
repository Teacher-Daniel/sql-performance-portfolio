# Portafolio de rendimiento en SQL Server

Proyecto práctico para documentar el análisis y la optimización de consultas en SQL Server.

[English version](README.md)

## Objetivos

- Interpretar planes de ejecución reales.
- Identificar problemas de rendimiento en consultas.
- Medir mejoras mediante líneas base reproducibles.
- Documentar decisiones técnicas y sus implicaciones.

## Hoja de ruta

Consulta la [hoja de ruta del proyecto](docs/project-roadmap.md).

## Entorno de laboratorio

Consulta la [configuración del laboratorio](docs/lab-environment.md) y ejecuta el [script de validación del entorno](sql/00-setup/validate-environment.sql).

## Base de datos de muestra

Consulta la [base de datos de telemetría vehicular](docs/sample-database.md), incluyendo el orden de construcción, los volúmenes verificados y los resultados de validación.

## Experimentos de rendimiento

| # | Experimento | Hallazgo principal | Estado |
|---|---|---|---|
| 01 | [SARGabilidad de predicados de fecha](sql/02-experiments/01-date-sargability/README.md) | Un intervalo de fechas semiabierto redujo las lecturas lógicas 82.0% frente al filtrado mediante funciones utilizando el mismo índice. | Completado |
| 02 | [Búsquedas de clave e índices cubrientes](sql/02-experiments/02-key-lookup-covering-index/README.md) | Un índice cubriente eliminó 500 búsquedas de clave y redujo las lecturas lógicas de 1,544 a 6 (99.61%). | Completado |