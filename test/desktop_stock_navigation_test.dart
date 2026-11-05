import 'package:distribuidora_alberdi/core/app_config.dart';
import 'package:distribuidora_alberdi/features/desktop/desktop_home.dart';
import 'package:distribuidora_alberdi/features/stock/stock_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const stockEnabled = bool.fromEnvironment('ENABLE_STOCK');
  setUp(() {
    activateAppConfig(
      AppConfig.resolve(
        testingEntrypoint: true,
        testingUrl: 'https://${AppConfig.testingProject}.supabase.co',
        testingKey: 'sb_publishable_local_fixture_123456789',
      ),
    );
  });

  Future<void> openHome(WidgetTester tester, {required bool admin}) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // Keep Supabase uninitialized. The data pages handle unavailable services
    // locally, and this test exercises navigation without a network client.
    await tester.pumpWidget(
      MaterialApp(
        home: DesktopHome(name: 'Fixture', isAdmin: admin, onSignOut: () {}),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('admin menu honors the Stock build option and opens Stock', (
    tester,
  ) async {
    await openHome(tester, admin: true);
    expect(find.text('Saldos'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Saldos')).dy,
      greaterThan(tester.getTopLeft(find.text('ADMINISTRACIÓN')).dy),
    );
    final menu = find.ancestor(
      of: find.text('Saldos'),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.text('Resumen comercial'),
      200,
      scrollable: menu,
    );
    expect(find.text('Administrar productos'), findsOneWidget);
    expect(find.text('Resumen comercial'), findsOneWidget);
    expect(find.text('Preparación y reparto'), findsOneWidget);
    final stock = find.text('Stock');
    if (stockEnabled) {
      expect(stock, findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Administrar productos')).dy,
        lessThan(tester.getTopLeft(stock).dy),
      );
      expect(
        tester.getTopLeft(stock).dy,
        lessThan(tester.getTopLeft(find.text('Resumen comercial')).dy),
      );
      await tester.tap(stock);
      await tester.pumpAndSettle();
      expect(find.byType(StockPage), findsOneWidget);
    } else {
      expect(stock, findsNothing);
      expect(find.byType(StockPage), findsNothing);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('preventista has no Stock access with either build option', (
    tester,
  ) async {
    await openHome(tester, admin: false);
    expect(find.text('Stock'), findsNothing);
    expect(find.text('Saldos'), findsNothing);
    expect(find.text('Administrar productos'), findsNothing);
    expect(find.byType(StockPage), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
