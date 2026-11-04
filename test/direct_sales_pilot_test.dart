import 'package:distribuidora_alberdi/core/app_config.dart';
import 'package:distribuidora_alberdi/features/orders/order_operation_selector.dart';
import 'package:distribuidora_alberdi/features/orders/order_summary_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AppConfig testingConfig() => AppConfig.resolve(
  testingEntrypoint: true,
  testingUrl: 'https://${AppConfig.testingProject}.supabase.co',
  testingKey: 'sb_publishable_local_fixture_123456789',
);

void main() {
  test('TESTING blocks only direct sales, retaining V2 order routing', () {
    final config = testingConfig();
    expect(config.directSalesEnabled, isFalse);
    expect(config.blocksOrderOperation('venta_directa'), isTrue);
    expect(config.blocksOrderOperation('pedido'), isFalse);
    expect(config.usesV2For('pedido'), isTrue);
    expect(config.usesV2For('venta_directa'), isFalse);
  });

  test('production retains direct sales and its original legacy routing', () {
    final config = AppConfig.resolve(
      productionKey: 'sb_publishable_local_fixture_123456789',
    );
    expect(config.directSalesEnabled, isTrue);
    expect(config.blocksOrderOperation('venta_directa'), isFalse);
    expect(config.usesV2For('venta_directa'), isFalse);
  });

  testWidgets('pilot selector refuses direct sales and explains why', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OrderOperationSelector(
            value: 'pedido',
            allowDirectSales: false,
            onChanged: (value) => selected = value,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Venta directa'));
    await tester.pump();
    expect(selected, isNull);
    expect(find.text(AppConfig.directSalesTestingMessage), findsOneWidget);
  });

  testWidgets('production selector still permits direct sales', (tester) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OrderOperationSelector(
            value: 'pedido',
            allowDirectSales: true,
            onChanged: (value) => selected = value,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Venta directa'));
    await tester.pump();
    expect(selected, 'venta_directa');
    expect(find.text(AppConfig.directSalesTestingMessage), findsNothing);
  });

  testWidgets('direct navigation to summary cannot send a blocked sale', (
    tester,
  ) async {
    // No Supabase instance is initialized: a blocked confirmation must never
    // reach auth, HTTP or real preferences, even through alternate navigation.
    activateAppConfig(testingConfig());
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: OrderSummaryPage(
          cliente: const {'id': 'fictional', 'nombre_comercio': 'LOCAL'},
          productos: const [],
          cantidades: const {},
          tipoPrecio: 'normal',
          preciosFijados: const {},
          tiposPrecioFijados: const {},
          fechaEntrega: DateTime(2026, 1, 1),
          tipoOperacion: 'venta_directa',
        ),
      ),
    );
    final button = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('CONFIRMAR PEDIDO'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(button.onPressed, isNull);
    expect(find.text(AppConfig.directSalesTestingMessage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
