# Versión 1.6.0 — Stock: pantallas (etapa 2)

Rama: `stock/etapa2` (base: `stock/etapa1`, que trae la migración `20261118010000_stock_por_producto`).
Detalle en `docs/STOCK.md`.

- **Stock y vehículo** (administrador): cargar y bajar el vehículo, anotar compras, contar, cerrar
  el viaje con diferencias; productos "con stock" / "a pedido"; filtro de negativos.
- **Lo que llevamos** (preventista): lo que queda en el vehículo para ofrecer, por categoría.
- **Venta directa durante un viaje**: muestra solo lo del vehículo con lo que queda, lo que el
  cliente llevó la última vez, y avisa lo que no se ofreció.
- Sin señal: las operaciones de stock quedan en "Pendientes de enviar".
- Pruebas: `test/stock_ui_test.dart` (reemplaza las de la pantalla vieja).
