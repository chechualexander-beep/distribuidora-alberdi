# Versión 1.5.0 — clientes nuevos sin señal (Entrega D3)

Rama: `release/1.5.0` (base: `release/1.4.0`). Sin migraciones nuevas.

- **Nuevo cliente sin señal**: queda "Guardado en el teléfono" y se envía solo, igual que los
  pedidos. El id del cliente se elige en el teléfono, así que **se le pueden hacer pedidos y
  ventas directas enseguida**: el cliente sale primero y sus pedidos detrás. Reenviar nunca
  lo duplica (si ya había llegado, el servidor contesta "ya existe" y cuenta como enviado).
- Mientras no llega, aparece en Clientes y en Nuevo pedido con la marca **"Sin enviar"**. Su
  ficha deja hacerle pedidos; editarlo, cobrarle, créditos y catálogo, cuando se envíe.
- Si la señal vuelve justo al confirmar el pedido de un cliente nuevo, primero se envía el
  cliente; si todavía no llegó, el pedido queda guardado detrás de él.
- **Pendientes de enviar** muestra también los clientes nuevos. Si el servidor rechaza un
  cliente, sus pedidos esperan; descartarlo descarta también sus pedidos (lo avisa).
- Reparto y cobros sin señal (D2) quedan para hacerlos junto con el stock del vehículo
  (ver `docs/HOJA-DE-RUTA.md`).
- Pruebas: `test/pending_orders_test.dart` (orden cliente → pedidos, rechazo, "ya existe",
  listas y ficha sin internet).
