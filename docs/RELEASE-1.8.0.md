# Versión 1.8.0 — Resumen de productos con stock y fraccionados

Rama: `stock/etapa4` (base: `stock/etapa3`). Migración: `20261120010000_fraccionados`.

- Resumen de productos fácil de leer (filas alternadas, pedido vs. lo que hay, estado en color,
  "Solo lo que falta", "Lista de compras").
- Productos fraccionados: vínculo con el origen, "Fraccionar" a mano y apertura automática al
  entregar cuando no alcanza.
- Pruebas: `test/fraccionados_escenario.sql`, `test/stock_ui_test.dart`.
