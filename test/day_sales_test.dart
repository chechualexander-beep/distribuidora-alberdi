import 'package:distribuidora_alberdi/core/app_config.dart';
import 'package:distribuidora_alberdi/features/orders/day_sales.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/outbox_fixture.dart';

Map<String, dynamic> pedido(String resultado, List<List<Object>> lineas, List<List<Object>> pagos) => {
  'resultado_entrega': resultado,
  'pedido_detalles': [
    for (final l in lineas)
      {'cantidad_entregada': l[1], 'precio_unitario': l[2], 'productos': {'nombre': l[0]}},
  ],
  'pedido_pagos': [
    for (final p in pagos) {'medio_pago': p[0], 'importe': p[1]},
  ],
};

void main() {
  setUp(() {
    activateAppConfig(fixtureConfig());
    SharedPreferences.setMockInitialValues({});
  });

  test('venta del día: entregado, cobrado por medio y lo que quedó a cuenta', () {
    final s = DaySales.fromRows([
      pedido('entregado', [['Chizito', 3, 1000], ['Tutuca', 1, 2000]], [['Efectivo', 5000]]),
      pedido('parcial', [['Chizito', 2, 1000]], [['Transferencia', 1000]]),
      pedido('no_entregado', [['Tutuca', 0, 2000]], []),
    ]);
    expect(s.total, 7000);
    expect(s.delivered, 1);
    expect(s.partial, 1);
    expect(s.notDelivered, 1);
    expect(s.count, 2);
    expect(s.units, 6);
    expect(s.byMethod, {'Efectivo': 5000, 'Transferencia': 1000});
    expect(s.owed, 1000);
    expect(s.topProduct, 'Chizito');
    expect(s.topUnits, 5);
  });

  testWidgets('tarjeta: preventa con avance; se cierra y queda en una línea', (tester) async {
    final s = DaySales.fromRows([
      pedido('entregado', [['Chizito', 4, 1000]], [['Efectivo', 4000]]),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DaySalesCard(direct: false, sales: s, pendingCount: 3, pendingTotal: 4000),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Venta del día · preventa'), findsOneWidget);
    expect(find.text('Entregado'), findsOneWidget);
    expect(find.text('50 %'), findsOneWidget, reason: '4.000 entregado de 8.000 esperado');
    expect(find.textContaining('3 faltan'), findsOneWidget);
    expect(find.text('Efectivo'), findsOneWidget);
    await tester.tap(find.byKey(const Key('venta-del-dia')));
    await tester.pumpAndSettle();
    expect(find.text('Entregado'), findsNothing);
    expect(find.textContaining('Venta del día · preventa  '), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().any((k) => k.contains('reparto_venta_del_dia_abierta')), isTrue);
  });

  testWidgets('tarjeta: venta directa con lo más vendido', (tester) async {
    final s = DaySales.fromRows([
      pedido('entregado', [['Chizito', 9, 1000], ['Tutuca', 2, 2000]], [['Efectivo', 13000]]),
    ]);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: DaySalesCard(direct: true, sales: s))),
    );
    await tester.pumpAndSettle();
    expect(find.text('Vendido'), findsOneWidget);
    expect(find.textContaining('Chizito × 9'), findsOneWidget);
    expect(find.textContaining('faltan'), findsNothing);
  });
}
