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
  // 1.0.8: venta directa V2 habilitada en todos los entornos.
  const enabled = true;
  test('TESTING routes direct sales to V2 only with the explicit option', () {
    final config = testingConfig();
    expect(config.directSalesEnabled, enabled);
    expect(config.blocksOrderOperation('venta_directa'), !enabled);
    expect(config.blocksOrderOperation('pedido'), isFalse);
    expect(config.usesV2For('pedido'), isTrue);
    expect(config.usesV2For('venta_directa'), enabled);
  });

  test('production keeps direct sales and routes them through V2', () {
    final config = AppConfig.resolve(
      productionKey: 'sb_publishable_local_fixture_123456789',
    );
    expect(config.directSalesEnabled, isTrue);
    expect(config.blocksOrderOperation('venta_directa'), isFalse);
    expect(config.usesV2For('venta_directa'), isTrue);
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

  testWidgets('TESTING selector follows the build option', (tester) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OrderOperationSelector(
            value: 'pedido',
            allowDirectSales: testingConfig().directSalesEnabled,
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
  }, skip: enabled);
}
