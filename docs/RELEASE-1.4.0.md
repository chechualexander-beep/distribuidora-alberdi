# Versión 1.4.0 — pedidos y ventas directas sin señal (Entrega D1)

Rama: `release/1.4.0` (base: `release/1.3.0`). Migración nueva: `20261117010000_pedidos_sin_conexion`.

- Al confirmar un pedido o una venta directa **sin señal**, queda **guardado en el teléfono**
  ("Guardado en el teléfono") y se envía solo: al iniciar la app, al volver la conexión y cada
  2 minutos. Nunca se carga dos veces (misma solicitud).
- **Pendientes de enviar** (tarjeta en el inicio, también en Windows): lista de lo guardado,
  "Enviar ahora", y los que el servidor rechazó, con el motivo y la opción de descartarlos.
- **Precio que vio el cliente**: la base guarda el historial de precios. Si un precio cambió
  después de que se cargó el pedido sin señal, se respeta el anterior hasta **72 horas** y queda
  anotado en la observación ("[Sin señal] Se respetó el precio que vio el cliente: ...").
  Un precio que nunca existió se rechaza.
- Al cerrar sesión con pedidos pendientes, avisa (no se pierden: se envían al volver a entrar).
- "Preparar para trabajar sin señal" ahora también guarda el teléfono de cada cliente (WhatsApp).
- Pruebas: `test/pedidos_sin_conexion_escenario.sql`, `test/pending_orders_test.dart`.
