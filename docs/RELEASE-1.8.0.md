# Versión 1.8.0 — Resumen de productos con stock y fraccionados

Rama: `stock/etapa4` (base: `stock/etapa3`). Migración: `20261120010000_fraccionados`.

- Resumen de productos fácil de leer (filas alternadas, pedido vs. lo que hay, estado en color,
  "Solo lo que falta", "Lista de compras").
- Productos fraccionados: vínculo con el origen, "Fraccionar" a mano y apertura automática al
  entregar cuando no alcanza.
- Pruebas: `test/fraccionados_escenario.sql`, `test/stock_ui_test.dart`.

Agregado antes de producción (migraciones `20261121010000` a `20261125010000`):

- Entrega sin carga del vehículo, compras que pasan a llevar stock, sueltos automáticos.
- Cargar vehículo como lista para marcar en flúor, con colores de stock, pantalla completa,
  "Pedidos a entregar" con solo lo que falta subir y edición cómoda de cantidades.
- Preventista del viaje editable con el viaje abierto.
- Resumen de pedidos nuevos contra lo libre; "Lo que llevamos" descuenta lo del reparto.
- Pantalla bloqueada sin "Cerrar sesión" (solo aparece, con confirmación, si el teléfono no
  puede verificar).
- Windows en modo oscuro sin zonas blancas (colores según el tema en `Tonos`).
- Inicio del celular: "Nuevo pedido" dorado arriba y accesos en dos columnas con borde.
