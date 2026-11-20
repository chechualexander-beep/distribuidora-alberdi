import 'package:distribuidora_alberdi/features/orders/order_products_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final productos = [
  {
    'id': 'p1',
    'nombre': 'Tutuca F.N Super Dulce x 1kg',
    'codigo': '182',
    'descripcion': 'Marca: Flor Del Norte.',
    'precio_normal': 5700,
    'precio_promo': 4600,
    'precio_interior': 6100,
  },
  {
    'id': 'p2',
    'nombre': 'Azúcar Ledesma x 1kg',
    'codigo': 'A1',
    'precio_normal': 1150,
    'precio_promo': 1000,
    'precio_interior': 1200,
  },
];

const kioscoPromo = {
  'id': 'c1',
  'nombre_comercio': 'Kiosco Nuevo',
  'tipo_precio_habitual': 'promo',
};

Future<void> abrir(
  WidgetTester tester, {
  required Map<String, dynamic>? Function() cliente,
  required void Function(OrderDraft) alResumen,
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => OrderProductsPage(
                    tipoOperacion: 'pedido',
                    fechaEntrega: DateTime(2026, 11, 21),
                    productosIniciales: productos,
                    elegirCliente: (_) async => cliente(),
                    abrirResumen: alResumen,
                  ),
                ),
              ),
              child: const Text('ABRIR'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('ABRIR'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sin cliente: se elige al final y pasa a su lista habitual', (
    tester,
  ) async {
    OrderDraft? resumen;
    await abrir(tester, cliente: () => kioscoPromo, alResumen: (p) => resumen = p);

    expect(find.text('CLIENTE AL FINAL'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.add_circle).first);
    await tester.tap(find.byIcon(Icons.add_circle).first);
    await tester.pump();
    expect(find.text('\$11.400'), findsOneWidget);

    await tester.tap(find.text('VER PEDIDO'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Su lista habitual es Promo'), findsOneWidget);
    await tester.tap(find.text('Pasar a Promo'));
    await tester.pumpAndSettle();

    expect(resumen, isNotNull);
    expect(resumen!.cliente['id'], 'c1');
    expect(resumen!.cantidades, {'p1': 2});
    expect(resumen!.precios, {'p1': 4600});
    expect(resumen!.listas, {'p1': 'promo'});
    expect(find.text('Kiosco Nuevo'), findsOneWidget);
  });

  testWidgets('sin cliente: puede mantener los precios de la lista elegida', (
    tester,
  ) async {
    OrderDraft? resumen;
    await abrir(tester, cliente: () => kioscoPromo, alResumen: (p) => resumen = p);
    await tester.tap(find.byIcon(Icons.add_circle).first);
    await tester.pump();
    await tester.tap(find.text('VER PEDIDO'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mantener precios'));
    await tester.pumpAndSettle();
    expect(resumen!.precios, {'p1': 5700});
    expect(resumen!.listas, {'p1': 'normal'});
  });

  testWidgets('sin cliente: si vuelve atrás no pasa nada y pide confirmar al salir', (
    tester,
  ) async {
    OrderDraft? resumen;
    await abrir(tester, cliente: () => null, alResumen: (p) => resumen = p);
    await tester.tap(find.byIcon(Icons.add_circle).first);
    await tester.pump();
    await tester.tap(find.text('VER PEDIDO'));
    await tester.pumpAndSettle();
    expect(resumen, isNull);
    expect(find.text('CLIENTE AL FINAL'), findsOneWidget);

    final NavigatorState navegador = tester.state(find.byType(Navigator));
    navegador.maybePop();
    await tester.pumpAndSettle();
    expect(find.text('¿Salir del pedido?'), findsOneWidget);
    await tester.tap(find.text('Salir'));
    await tester.pumpAndSettle();
    expect(find.text('ABRIR'), findsOneWidget);
  });

  testWidgets('buscar productos sin acentos y por palabras', (tester) async {
    await abrir(tester, cliente: () => null, alResumen: (_) {});
    await tester.enterText(find.byType(TextField), 'azucar');
    await tester.pump();
    expect(find.text('Azúcar Ledesma x 1kg'), findsOneWidget);
    expect(find.text('Tutuca F.N Super Dulce x 1kg'), findsNothing);
    await tester.enterText(find.byType(TextField), '1kg fn');
    await tester.pump();
    expect(find.text('Tutuca F.N Super Dulce x 1kg'), findsOneWidget);
    expect(find.text('Azúcar Ledesma x 1kg'), findsNothing);
  });
}
