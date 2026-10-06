# Resumen comercial por modalidad

## Activación

Aplicar `supabase/migrations/20260928180000_resumen_comercial_modalidades.sql`
en el proyecto Supabase antes de publicar esta versión de Flutter. La pantalla
requiere la nueva función `resumen_comercial(p_inicio, p_fin)`. La migración
solo crea o reemplaza esa función y sus permisos; no modifica datos existentes.

## Reglas

- Venta total: preventa facturada (`tipo_operacion = pedido`) por fecha de
  facturación, más venta directa efectivamente entregada por fecha de finalización.
- Mercadería: cantidades entregadas por precio de venta, solo operaciones
  entregadas o parciales, excluyendo estados `cancelado` y `anulado`.
- Entregas históricas sin `fecha_finalizacion`: se usa `fecha_entrega` a
  medianoche argentina. Los productos agregados durante una entrega se incluyen
  en mercadería, pero no en preventa facturada si su cantidad facturada es cero.
- Costo, comisiones y ganancia usan las mismas entregas y fechas que mercadería.
- Recaudación: el total proviene exclusivamente de `cobros_cliente`. Su desglose
  usa importes de `pedido_pagos` relacionados mediante `cobro_id`, clasificados
  por tipo del pedido pagado, incluso cuando este es de un período anterior.
  No se suma otra vez el total del cobro por cada aplicación.
- La diferencia entre recaudación total y aplicaciones clasificadas se muestra
  como «Sin clasificar». Los pagos antiguos sin `cobro_id` no se incorporan al
  total de cobros automáticamente. Una diferencia negativa revela aplicaciones
  inconsistentes y se conserva visible para poder conciliarla.
- Los períodos incluyen su inicio y excluyen el inicio del día posterior al fin,
  en horario argentino. Semana abarca lunes a domingo.
- Saldos pendientes conserva su criterio existente: fecha de entrega registrada
  o todos los saldos. No debe interpretarse como venta menos recaudación del período.
- Los importes históricos reflejan las cantidades guardadas actualmente; una
  corrección posterior de la operación puede cambiar el resumen histórico.

## Verificación local

```text
flutter analyze lib/features/admin/commercial_summary_page.dart lib/features/admin/widgets/commercial_summary_card.dart test/commercial_summary_card_test.dart
flutter test --no-pub test/commercial_summary_card_test.dart
```

Para probar el SQL sin conectarse a Supabase, instalar la dependencia de pruebas
en el directorio ignorado de Dart y ejecutar:

```text
npm install --prefix .dart_tool/commercial_sql_test --no-audit --no-fund @electric-sql/pglite@0.5.8
node test/commercial_summary_sql_test.cjs
```

La prueba utiliza PostgreSQL en memoria con tablas mínimas y datos ficticios.
Cubre períodos vacíos, preventa parcial, venta directa sin facturación, productos
agregados, cobros distribuidos entre modalidades, deudas anteriores, importes
sin clasificar, límites horarios, fechas históricas, anulaciones y autorización.
No reemplaza la comprobación de integración en el proyecto Supabase de destino.
