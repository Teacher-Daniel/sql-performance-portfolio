# Portafolio de rendimiento en SQL Server

Proyecto práctico para documentar el análisis y la optimización de consultas en SQL Server.

[English version](README.md)

## Objetivos

- Interpretar planes de ejecución reales.
- Identificar problemas de rendimiento en consultas.
- Medir mejoras mediante líneas base reproducibles.
- Documentar decisiones técnicas y sus implicaciones.

## Hoja de ruta

El portafolio central tiene un alcance fijo de ocho experimentos de rendimiento y culminará en `v1.0.0`.

Consulta la [hoja de ruta del proyecto](docs/project-roadmap.md) para conocer la secuencia de experimentos, los criterios de finalización, la lista opcional de trabajo futuro y la regla para cambiar el alcance.

## Entorno de laboratorio

Consulta la [configuración del laboratorio](docs/lab-environment.md) y ejecuta el [script de validación del entorno](sql/00-setup/validate-environment.sql).

## Base de datos de muestra

Consulta la [base de datos de telemetría vehicular](docs/sample-database.md), incluyendo el orden de construcción, los volúmenes verificados y los resultados de validación.

## Experimentos de rendimiento

| # | Experimento | Hallazgo principal | Estado |
|---|---|---|---|
| 01 | [SARGabilidad de predicados de fecha](sql/02-experiments/01-date-sargability/README.md) | Un intervalo de fechas semiabierto redujo las lecturas lógicas 82.0% frente al filtrado mediante funciones utilizando el mismo índice. | Completado |
| 02 | [Búsquedas de clave e índices cubrientes](sql/02-experiments/02-key-lookup-covering-index/README.md) | Un índice cubriente eliminó 500 búsquedas de clave y redujo las lecturas lógicas de 1,544 a 6 (99.61%). | Completado |
| 03 | [Orden de columnas en índices compuestos](sql/02-experiments/03-composite-index-column-order/README.md) | Colocar primero la llave de igualdad redujo las lecturas lógicas de 690 a 3 (99.57%) al eliminar el filtrado residual. | Completado |
| 04 | [Estimaciones de cardinalidad y sesgo de datos](sql/02-experiments/04-cardinality-estimation-data-skew/README.md) | Las estimaciones sensibles al sesgo seleccionaron planes diferentes; el `Index Seek` del valor poco frecuente redujo las lecturas lógicas de 7,380 a 675 (90.85%). | Completado |
| 05 | [Planes sensibles a parámetros](sql/02-experiments/05-parameter-sensitive-plans/README.md) | PSP creó variantes de `scan` y `seek` para el sesgo extremo; el plan del valor raro redujo las lecturas lógicas de 8,022 a 6 (99.93%). | Completado |
| 06 | [Estrategias de unión e índices de soporte](sql/02-experiments/06-join-strategies-supporting-indexes/README.md) | Un índice sobre `DeviceId` cambió la unión amplia de `Hash Match` a `Merge Join` sin ordenamientos ni concesión de memoria; en el caso selectivo, las lecturas de `TelemetryEvent` bajaron de 7,380 a 3 (99.96%). | Completado |
