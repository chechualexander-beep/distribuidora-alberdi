import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:distribuidora_alberdi/core/desktop_table.dart';
import 'package:distribuidora_alberdi/features/invoicing/invoicing_desktop_table.dart';
import 'package:distribuidora_alberdi/features/products/products_desktop_table.dart';
import 'package:distribuidora_alberdi/features/products/product_photo.dart';

void main() {
  final orders = [
    {
      'id': 'a',
      'clientes': {
        'nombre_comercio': 'Almacén A',
        'direccion': 'San Martín 100',
      },
      'usuarios': {'nombre': 'Mary', 'apellido': 'Ana'},
      'total': 161000,
      'created_at': '2026-10-03T12:00:00Z',
      'tipo_precio': 'normal',
      'observacion': 'Catálogo web',
    },
    {
      'id': 'b',
      'clientes': {'nombre_comercio': 'Almacén B'},
      'usuarios': {'nombre': 'Cristian'},
      'total': 55700,
      'created_at': '2026-10-02T12:00:00Z',
      'tipo_precio': 'promo',
    },
  ];
  test('Importes conservan centavos y separadores argentinos', () {
    expect(desktopMoney(3200.25), '\$3.200,25');
    expect(desktopMoney(161000), '\$161.000,00');
  });
  testWidgets('La tabla filtra, suma lo visible y abre el pedido original', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Map<String, dynamic>? opened;
    var refreshes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InvoicingDesktopTable(
            orders: orders,
            onOpen: (p) => opened = p,
            onRefresh: () => refreshes++,
          ),
        ),
      ),
    );
    expect(find.text('Total visible: \$216.700,00'), findsOneWidget);
    expect(find.bySemanticsLabel('Pedido con observación'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'San Martín');
    await tester.pump();
    expect(find.text('Almacén B'), findsNothing);
    expect(find.text('Total visible: \$161.000,00'), findsOneWidget);
    await tester.tap(find.text('Almacén A'));
    await tester.pump();
    expect(identical(opened, orders.first), isTrue);
    await tester.tap(find.byTooltip('Actualizar pedidos'));
    expect(refreshes, 1);
    await tester.enterText(find.byType(TextField), 'inexistente');
    await tester.pump();
    expect(
      find.text('No hay pedidos que coincidan con los filtros.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('Filtro de preventista y recarga sin vendedor seleccionado', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 700);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Widget page(List<Map<String, dynamic>> data) => MaterialApp(
      home: Scaffold(
        body: InvoicingDesktopTable(
          orders: data,
          onOpen: (_) {},
          onRefresh: () {},
        ),
      ),
    );
    await tester.pumpWidget(page(orders));
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mary Ana').last);
    await tester.pumpAndSettle();
    expect(find.text('Almacén B'), findsNothing);
    await tester.pumpWidget(page([orders.last]));
    await tester.pumpAndSettle();
    expect(find.text('Almacén B'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Productos compactos conservan las tres listas y miniaturas', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(950, 700);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProductsDesktopTable(
            products: [
              {
                'id': 'p',
                'nombre': 'Tutuca x 1kg',
                'codigo': '123',
                'precio_normal': 7500,
                'precio_promo': 6100,
                'precio_interior': 8100,
              },
            ],
          ),
        ),
      ),
    );
    expect(find.text('\$7.500,00'), findsOneWidget);
    expect(find.text('\$6.100,00'), findsOneWidget);
    expect(find.text('\$8.100,00'), findsOneWidget);
    expect(tester.widget<ProductPhoto>(find.byType(ProductPhoto)).size, 34);
    expect(tester.takeException(), isNull);
  });
  testWidgets('No activa el escritorio en Android ni en ventanas pequeñas', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    bool? enabled;
    Widget page(TargetPlatform platform) => MaterialApp(
      key: ValueKey(platform),
      theme: ThemeData(platform: platform),
      home: Builder(
        builder: (context) {
          enabled = useDesktopLayout(context);
          return const SizedBox();
        },
      ),
    );
    await tester.pumpWidget(page(TargetPlatform.android));
    expect(enabled, isFalse);
    await tester.pumpWidget(page(TargetPlatform.windows));
    await tester.pumpAndSettle();
    expect(enabled, isTrue);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 700);
    await tester.pump();
    expect(enabled, isFalse);
  });
}
