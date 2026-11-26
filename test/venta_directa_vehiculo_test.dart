import 'package:distribuidora_alberdi/features/orders/order_products_page.dart';
import 'package:distribuidora_alberdi/features/stock/stock_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> prod(String id, String nombre) =>
    {'id': id, 'nombre': nombre, 'codigo': id.toUpperCase(), 'precio_normal': 1000, 'precio_promo': 900, 'precio_interior': 1100};

void main() {
  testWidgets('Venta directa: se ve y se busca solo lo libre; lo reservado aparte; Todo busca en todo', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: OrderProductsPage(
          tipoOperacion: 'venta_directa',
          productosIniciales: [
            prod('a', 'Copos libres'),
            prod('b', 'Mix reservado'),
            prod('c', 'Chizitos del depósito'),
            prod('d', 'Palitos vendidos'),
          ],
          vehiculoInicial: const VehicleStock(
            tripId: 'v1',
            lines: {
              // 10 arriba, 2 para entregar: quedan 8.
              'a': VehicleLine(10, 2, 2),
              // 5 arriba, los 5 para entregar.
              'b': VehicleLine(5, 5, 5),
              // 3 arriba, los 3 ya vendidos en venta directa.
              'd': VehicleLine(3, 3, 0),
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('vista-vehiculo')), findsOneWidget);
    expect(find.text('Para vender · 1'), findsOneWidget);
    expect(find.text('Reservado · 1'), findsOneWidget);
    expect(find.text('Copos libres'), findsOneWidget);
    expect(find.text('Vehículo: quedan 8 · 2 para entregar'), findsOneWidget);
    expect(find.text('Mix reservado'), findsNothing);
    expect(find.text('Chizitos del depósito'), findsNothing);
    expect(find.text('Palitos vendidos'), findsNothing);

    await tester.tap(find.byKey(const Key('ver-reservado')));
    await tester.pumpAndSettle();
    expect(find.text('Mix reservado'), findsOneWidget);
    expect(find.text('Vehículo: reservado para entregas'), findsOneWidget);
    expect(find.text('Copos libres'), findsNothing);

    await tester.tap(find.text('Todo'));
    await tester.pumpAndSettle();
    expect(find.text('Chizitos del depósito'), findsOneWidget);
    expect(find.text('Palitos vendidos'), findsOneWidget);

    await tester.tap(find.text('Para vender · 1'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'chizitos');
    await tester.pumpAndSettle();
    expect(find.text('Chizitos del depósito'), findsNothing, reason: 'en "Para vender" busca solo lo libre');
    expect(find.text('No está libre en el vehículo.'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'copos');
    await tester.pumpAndSettle();
    expect(find.text('Copos libres'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'chizitos');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('buscar-en-todo')));
    await tester.pumpAndSettle();
    expect(find.text('Chizitos del depósito'), findsOneWidget, reason: 'en "Todo" busca en toda la mercadería');
  });
}
