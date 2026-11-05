# Resumen comercial por modalidad

La pantalla usa la función existente `resumen_comercial(p_inicio, p_fin)`
y el repositorio paginado de Saldos. El rediseño no requiere una migración.

## Reglas

- Ventas efectivas: `entrega_total`, antes de notas de crédito. El detalle
  distingue preventa entregada de venta directa entregada. La preventa
  facturada se muestra aparte, por fecha de facturación.
- Mercadería: cantidades entregadas por precio de venta, solo operaciones
  entregadas o parciales, excluyendo estados `cancelado` y `anulado`.
- Entregas históricas sin `fecha_finalizacion`: se usa `fecha_entrega` a
  medianoche argentina. Los productos agregados durante una entrega se incluyen
  en mercadería, pero no en preventa facturada si su cantidad facturada es cero.
- El costo y las comisiones brutas usan las mismas entregas y fechas que la
  mercadería. El resultado comercial toma `ganancia` de la RPC, que resta
  costo, comisiones y notas de crédito y suma costo recuperado y comisiones
  revertidas. Las notas se cuentan en su fecha y el costo se recupera por
  cantidades aptas en la fecha de recepción. El resultado excluye gastos
  generales y no representa el dinero disponible en caja.
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
- Total por cobrar suma los saldos positivos por cliente de
  `saldos_pendientes_clientes`, con paginación completa y sin filtro temporal.
- El desglose de Cobros puede mostrar cobros menos reintegros. El indicador
  principal conserva los cobros brutos del período.
- Los importes históricos reflejan las cantidades guardadas actualmente; una
  corrección posterior de la operación puede cambiar el resumen histórico.

## Verificación local

```text
flutter analyze lib/features/admin/commercial_summary_page.dart lib/features/admin/widgets/commercial_summary_card.dart test/commercial_summary_card_test.dart
flutter test --no-pub test/commercial_summary_page_test.dart test/commercial_summary_card_test.dart
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
