import 'package:distribuidora_alberdi/features/stock/stock_data.dart';
import 'package:distribuidora_alberdi/features/stock/stock_form_page.dart';
import 'package:distribuidora_alberdi/features/stock/stock_reorder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

List<ReorderLine> lineas() => [
  for (final j in [
    {'producto_id': 'a', 'nombre': 'Azúcar Ledesma 1 kg', 'accion': 'comprar', 'proveedor': 'Distribuidora Norte',
      'demora': 1, 'hay': 16, 'comprometido': 10, 'libre': 6, 'por_semana': 40, 'dias': 1.1, 'comprar': 40,
      'costo_total': 52000},
    {'producto_id': 'y', 'nombre': 'Yerba Playadito 1 kg', 'accion': 'comprar', 'proveedor': 'Distribuidora Norte',
      'demora': 1, 'hay': 9, 'comprometido': 0, 'libre': 9, 'por_semana': 21, 'dias': 3, 'comprar': 20,
      'costo_total': 60000},
    {'producto_id': 'c', 'nombre': 'Copos 3A x 4 kg', 'accion': 'comprar', 'proveedor': 'Mayorista Sur', 'demora': 2,
      'hay': 3, 'comprometido': 0, 'libre': 3, 'por_semana': 10, 'dias': 2.1, 'comprar': 8, 'costo_total': 144000},
    {'producto_id': 'h', 'nombre': 'Harina 000 x 1 kg', 'accion': 'abrir', 'proveedor': null, 'demora': 1, 'hay': 2,
      'comprometido': 0, 'libre': 2, 'por_semana': 14, 'dias': 1, 'abrir': 1, 'origen': 'Harina 000 x 25 kg'},
  ])
    ReorderLine.fromJson(j),
];

void main() {
  test('Para reponer: por proveedor, el más urgente primero y sin proveedor al final', () {
    final groups = groupBySupplier(lineas());
    expect(groups.map((g) => g.key).toList(), ['Distribuidora Norte', 'Mayorista Sur', sinProveedor]);
    expect(lineas().first.daysText, 'alcanza 1 día');
    expect(lineas()[1].daysText, 'alcanza 3 días');
    final text = reorderShareText(lineas());
    expect(text, contains('*Distribuidora Norte*'));
    expect(text, contains('40 × Azúcar Ledesma 1 kg (alcanza 1 día)'));
    expect(text, contains('Abrir 1 × Harina 000 x 25 kg (para Harina 000 x 1 kg)'));
  });

  testWidgets('Para reponer (administrador): costos, total y disponible', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: ReorderPage(initial: lineas(), available: 800000)));
    expect(find.byKey(const Key('reponer-total')), findsOneWidget);
    expect(find.text('\$256.000'), findsOneWidget);
    expect(find.text('\$800.000'), findsOneWidget);
    expect(find.text('DISTRIBUIDORA NORTE · llega en 1 día'), findsOneWidget);
    expect(find.text('Comprar 40'), findsOneWidget);
    expect(find.text('abrir 1 × Harina 000 x 25 kg'), findsOneWidget);
    expect(find.text('Anotar compra'), findsNWidgets(2));
  });

  testWidgets('Para reponer (Gabriela): sin plata y sin anotar compras', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: ReorderPage(initial: lineas(), helper: true)));
    expect(find.byKey(const Key('reponer-total')), findsNothing);
    expect(find.textContaining('\$'), findsNothing);
    expect(find.text('Faltan 40'), findsOneWidget);
    expect(find.text('Anotar compra'), findsNothing);
    expect(find.text('Mandar la lista'), findsOneWidget);
  });

  testWidgets('Anotar compra desde Para reponer: viene armada y con el ritmo de venta', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: StockFormPage(
          kind: StockFormKind.purchase,
          items: [
            StockItem(id: 'a', name: 'Azúcar', code: 'A', category: 'x', photo: null, controlled: true,
                deposit: 6, vehicle: 0, cost: 1300),
            StockItem(id: 'b', name: 'Otro', code: 'B', category: 'x', photo: null, controlled: true,
                deposit: 50, vehicle: 0, cost: 100),
          ],
          initialQuantities: const {'a': 40},
          initialSupplier: 'Distribuidora Norte',
          hints: const {'a': 'Vende ~40 por semana · alcanza 1 día'},
          runner: (fn, a) async => const StockOpOutcome({}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pista-a')), findsOneWidget);
    expect(find.text('Vende ~40 por semana · alcanza 1 día'), findsOneWidget);
    expect(find.widgetWithText(TextField, '40'), findsOneWidget);
    expect(find.text('Distribuidora Norte'), findsOneWidget);
    expect(find.text('Otro'), findsNothing, reason: 'muestra solo lo que viene armado');
  });
}
