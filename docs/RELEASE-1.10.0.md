# Versión 1.10.0 — Venta especial (etapa A del mostrador)

Rama: `gestion/etapa1`. Migración: `20261128010000_venta_especial`.

- **Venta especial** (solo administrador; celular: Administración; Windows: menú): cliente o
  "Consumidor final", depósito o vehículo, precio a mano por producto (o total de la línea), margen en
  vivo (aviso si queda debajo del costo), sin comisión. Se cobra con "¿Cómo quedó el pago?" (efectivo,
  transferencia, mixto o fiado; a "Consumidor final" no se le fía). Queda entregada al instante: stock
  del lugar elegido (abre cajas si hace falta, con la misma lógica que la entrega), costo y ganancia en
  el Resumen comercial y el Tablero, cobro en Plata del negocio. Detalle por WhatsApp. Sin señal queda
  en "Pendientes de enviar" (idempotente). Origen `especial` en `pedidos`: no se suma al viaje abierto.
- **Ventas del administrador sin comisión**: trigger `zz_comision_cero_administrador` (pedidos, venta
  directa y venta especial). Lo ya registrado no cambia.
- Cliente fijo "Consumidor final" (`consumidor_final_id()`).

Prueba: `test/venta_especial_escenario.sql`, `test/special_sale_test.dart`.

Etapa B (cuando abra el local): rol cajero, ubicación "Local", caja por turno, lista minorista.
