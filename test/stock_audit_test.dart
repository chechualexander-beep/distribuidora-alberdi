import 'package:distribuidora_alberdi/core/app_config.dart';
import 'package:distribuidora_alberdi/features/stock/stock_audit_data.dart';
import 'package:distribuidora_alberdi/features/stock/stock_audit_pages.dart';
import 'package:distribuidora_alberdi/features/stock/stock_data.dart';
import 'package:distribuidora_alberdi/features/stock/stock_guide_page.dart';
import 'package:distribuidora_alberdi/features/stock/trip_settlement_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/outbox_fixture.dart';

TripSettlement liquidacion() => TripSettlement.fromJson({
  'viaje': {
    'id': 'v1',
    'estado': 'cerrado',
    'abierto_at': '2026-11-22T12:10:00Z',
    'cerrado_at': '2026-11-22T21:40:00Z',
    'preventista': 'Gabriela',
    'contado': true,
  },
  'filas': [
    {
      'producto_id': 'pasas', 'nombre': 'Pasas Uva 1kg', 'tenia': 1, 'cargo': 3, 'deposito': 0, 'vendido': 2,
      'devuelto': 0, 'bajado': 0, 'otros': 0, 'deberia': 2, 'contado': 1, 'diferencia': -1,
    },
    {
      'producto_id': 'chizito', 'nombre': 'Chizito', 'tenia': 0, 'cargo': 0, 'deposito': 1, 'vendido': 1,
      'devuelto': 0, 'bajado': 0, 'otros': 0, 'deberia': 0, 'contado': 0, 'diferencia': 0,
    },
    {
      'producto_id': 'tutuca', 'nombre': 'Tutuca', 'tenia': 2, 'cargo': 10, 'deposito': 0, 'vendido': 8,
      'devuelto': 1, 'bajado': 0, 'otros': 0, 'deberia': 5, 'contado': 5, 'diferencia': 0,
    },
  ],
  'cobros': [
    {'medio': 'Efectivo', 'importe': 50000},
    {'medio': 'Transferencia', 'importe': 10000},
  ],
  'ventas': {'cantidad': 4, 'total': 70000},
});

void main() {
  setUp(() => activateAppConfig(fixtureConfig()));

  test('liquidación: diferencias, tomado del depósito y cobros', () {
    final l = liquidacion();
    expect(l.withDifference.map((r) => r.productId), ['pasas']);
    expect(l.fromDepositCount, 1);
    expect(l.withoutReason, 1);
    expect(l.collected, 60000);
  });

  testWidgets('liquidación: pide motivo a lo que no cuadra y lo guarda', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    List<({String productId, String? reason, String? note})>? guardado;
    await tester.pumpWidget(
      MaterialApp(
        home: TripSettlementPage(
          tripId: 'v1',
          loader: () async => liquidacion(),
          saver: (items) async => guardado = items,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 cuadran'), findsOneWidget);
    expect(find.text('1 con diferencia'), findsOneWidget);
    expect(find.text('1 tomado del depósito'), findsOneWidget);
    expect(find.text('-1'), findsOneWidget);
    expect(find.text('Se tomó 1 del depósito porque no alcanzaba arriba.'), findsOneWidget);
    expect(find.text('Tutuca'), findsNothing, reason: 'lo que cuadra queda plegado');
    await tester.tap(find.byKey(const ValueKey('motivo-pasas')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rotura').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('guardar-liquidacion')));
    await tester.pumpAndSettle();
    expect(guardado, hasLength(1));
    expect(guardado!.single.productId, 'pasas');
    expect(guardado!.single.reason, 'rotura');
    expect(find.text('Liquidación completa.'), findsOneWidget);
  });

  testWidgets('historial: lo que dejó en negativo, en rojo; filtra por lugar', (tester) async {
    final item = StockItem(
      id: 'tutuca', name: 'Tutuca', code: 'T', category: 'x', photo: null, controlled: true, deposit: 4, vehicle: 0,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ProductHistoryPage(
          item: item,
          loader: () async => [
            ProductMovement.fromJson({
              'fecha': '2026-11-21T19:35:00Z', 'ubicacion': 'deposito_alberdi', 'tipo': 'transferencia_entrada',
              'operacion': 'cierre_viaje', 'delta': 5, 'anterior': -1, 'nueva': 4, 'usuario': 'Cristian',
            }),
            ProductMovement.fromJson({
              'fecha': '2026-11-21T14:44:00Z', 'ubicacion': 'vehiculo', 'tipo': 'compra', 'operacion': 'compra',
              'delta': 5, 'anterior': 2, 'nueva': 7, 'usuario': 'Cristian', 'contraparte': 'Proveedor Norte',
            }),
            ProductMovement.fromJson({
              'fecha': '2026-11-21T03:42:00Z', 'ubicacion': 'deposito_alberdi', 'tipo': 'transferencia_salida',
              'operacion': 'carga_vehiculo', 'delta': -2, 'anterior': 1, 'nueva': -1, 'usuario': 'Cristian',
            }),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Cierre del viaje'), findsOneWidget);
    expect(find.textContaining('Proveedor Norte'), findsOneWidget);
    expect(find.textContaining('quedó en negativo'), findsOneWidget);
    await tester.tap(find.text('Vehículo').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Cierre del viaje'), findsNothing);
    expect(find.textContaining('Compra'), findsOneWidget);
  });

  testWidgets('movimientos del día: cada cosa con quién, y su detalle al tocarla', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DayMovementsPage(
          loader: (day) async => [
            DayMovement.fromJson({
              'hora': '2026-11-22T12:05:00Z', 'tipo': 'carga_vehiculo', 'usuario': 'Gabriela', 'productos': 1,
              'lineas': [
                {'producto': 'Tutuca', 'ubicacion': 'deposito_alberdi', 'delta': -2, 'nueva': 2},
                {'producto': 'Tutuca', 'ubicacion': 'vehiculo', 'delta': 2, 'nueva': 2},
              ],
            }),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Carga del vehículo'), findsOneWidget);
    expect(find.textContaining('Gabriela'), findsOneWidget);
    expect(find.textContaining('Tutuca · Vehículo'), findsNothing);
    await tester.tap(find.textContaining('Carga del vehículo'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Tutuca · Vehículo'), findsOneWidget);
  });

  test('stock a revisar: negativos, sin motivo y sin contar', () {
    final r = StockReview.fromJson({
      'negativos': [
        {'producto_id': 'a', 'nombre': 'Papas', 'ubicacion': 'deposito_alberdi', 'cantidad': -1, 'desde': '2026-11-21T10:00:00Z'},
      ],
      'sin_motivo': [
        {'viaje_id': 'v1', 'cerrado_at': '2026-11-20T21:00:00Z', 'nombre': 'Pasas', 'diferencia': -1},
      ],
      'sin_contar': {'total': 3, 'productos': [{'producto_id': 'c', 'nombre': 'Maní', 'contado_at': null}]},
    });
    expect(r.total, 5);
    expect(r.negatives.single.place, 'deposito_alberdi');
    expect(r.withoutReason.single.tripId, 'v1');
    expect(r.notCounted.single.countedAt, isNull);
  });

  testWidgets('instructivo: el preventista no ve lo que es solo del administrador', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: StockGuidePage()));
    expect(find.text('Anotar una compra'), findsOneWidget);
    await tester.tap(find.text('Cargar el vehículo'));
    await tester.pumpAndSettle();
    expect(find.textContaining('marcala en flúor'), findsOneWidget);
    expect(find.textContaining('Evitá: Subir sin marcar'), findsOneWidget);
    await tester.pumpWidget(const MaterialApp(home: StockGuidePage(admin: false)));
    await tester.pumpAndSettle();
    expect(find.text('Anotar una compra'), findsNothing);
    expect(find.text('Cerrar el viaje y la liquidación'), findsNothing);
    expect(find.text('Contar'), findsOneWidget);
  });
}
