# Versión 1.7.0 — Reparto y cobros sin señal (etapa 3 del stock)

Rama: `stock/etapa3` (base: `stock/etapa2`). Migración: `20261119010000_reparto_sin_conexion`.

- Gestión de reparto sin señal: queda "Guardado en el teléfono" con la hora real y se envía sola
  ("Pendientes de enviar"). Descuenta del vehículo.
- La fecha de finalización (comisiones) y la del cobro al entregar son las del momento real.
- Cobro de saldo sin señal: queda pendiente con la hora real y se envía solo, sin duplicar.
- Pruebas: `test/reparto_sin_conexion_escenario.sql`, `test/finalization_request_test.dart`,
  `test/pending_orders_test.dart`.
