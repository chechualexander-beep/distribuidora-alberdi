# 1.16.0 — Stock: auditoría a la vista (etapa 2)

Incluye la 1.15.0 (inicio nuevo, pantallas unidas, Comisiones) y además:

- **Liquidación del viaje**: al cerrar el viaje se abre sola. Por producto: tenía al salir, cargó
  (cargas y compras), tomado del depósito, vendió, devoluciones, bajadas, otros, debía, contado y la
  diferencia. Lo que no cuadra va arriba y pide **motivo** (rotura, regalo o muestra, error de carga,
  vencido, faltante sin explicar, otro con nota). Se puede dejar sin terminar: lo que queda sin motivo
  aparece en "Stock a revisar". Resumen de ventas y cobros del viaje y **PDF** para compartir.
  También desde Stock → "Liquidaciones" (viajes recientes, con cuántos quedan sin motivo).
- **Historial de un producto**: tocando el producto en Stock → "Historial". Cada movimiento con
  lugar, quién, cliente o proveedor y cómo quedó; lo que dejó en negativo, en rojo. Filtro por lugar.
- **Stock a revisar**: tarjeta roja arriba en Stock (solo si hay algo): negativos (dónde y desde
  cuándo), diferencias sin motivo, y lo que no se cuenta hace más de 30 días (con botón para contar
  los 10 más viejos).
- **Movimientos del día**: botón en Stock; todo lo que movió stock, agrupado (carga, compra, conteo,
  entrega, venta, bajada, cierre), con quién y su detalle; día por día y por lugar.
- Gabriela (ayuda en el depósito) ve el Historial, los Movimientos y Stock a revisar (sin las
  diferencias de liquidación); la liquidación y sus motivos son solo del administrador.

Migración: `20261203010000_auditoria_stock`. Prueba: `test/auditoria_stock_escenario.sql`,
`test/stock_audit_test.dart`.
