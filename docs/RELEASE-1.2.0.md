# Versión 1.2.0 — facturación a prueba de cortes y uso con poca señal

Rama: `release/1.2.0` (base: `release/1.1.1`). Migración nueva: `20261116040000_facturacion_atomica`.

## Facturación a prueba de cortes (Windows)
- Facturar es **una sola operación del servidor** (`facturar_pedido`): número de comprobante,
  cantidades, líneas quitadas, productos agregados y marca de facturado, todo junto o nada.
- Cada intento lleva un identificador guardado en la PC. Si internet se corta y no se sabe si
  llegó, el botón pasa a **COMPLETAR FACTURACIÓN** y reenvía lo mismo: el servidor devuelve el
  mismo comprobante, nunca factura dos veces ni gasta otro número.
- Si el servidor rechaza (por ejemplo, cambió un precio o ya estaba facturado), no queda nada
  guardado y se puede corregir.
- La boleta se imprime con lo que quedó guardado en el servidor. Si falla la impresión, el pedido
  ya está facturado y se reimprime desde Facturas realizadas.

## Poca señal (Android y Windows)
- Las consultas tienen un tiempo máximo de 15 segundos: la pantalla ya no queda cargando minutos,
  muestra el error con **Reintentar**. Las operaciones que guardan datos no se cortan.
- Franja inferior **"Sin conexión o señal débil"** mientras falle la conexión.
- **Ahorro de datos** (ícono arriba, en la pantalla de inicio del celular): las fotos de productos
  no se descargan; se ven solo si se tocan.

## Pruebas
- `test/facturacion_atomica_escenario.sql` (solo TESTING: consume un número de comprobante).
- `test/atomic_invoice_test.dart`, `test/network_status_test.dart`.
