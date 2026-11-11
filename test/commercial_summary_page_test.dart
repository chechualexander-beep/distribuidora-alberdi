import 'dart:async';

import 'package:distribuidora_alberdi/features/admin/commercial_summary_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/balance_fixture.dart';

Map<String, dynamic> summary({bool returns = false}) => {
  'venta_preventa': 4000,
  'entrega_total': 3300,
  'entrega_preventa': 1000,
  'entrega_directa': 2300,
  'entrega_sin_clasificar': 0,
  'recaudacion_total': 500,
  'recaudacion_preventa': 500,
  'recaudacion_directa': 0,
  'recaudacion_sin_clasificar': 0,
  'recaudacion_neta': returns ? 400 : 500,
  'costo_mercaderia': 2000,
  'comisiones': 330,
  'ganancia': returns ? 620 : 970,
  'notas_credito': returns ? 1500 : 0,
  'mercaderia_neta': returns ? 1800 : 3300,
  'reintegros': returns ? 100 : 0,
  'costo_recuperado': returns ? 1000 : 0,
  'comisiones_revertidas': returns ? 150 : 0,
  'comisiones_por_preventista': {'QA': 330},
};

Future<void> openSummary(
  WidgetTester tester,
  CommercialPeriodReader reader,
  FakeBalanceRepository balances,
) async {
  await tester.binding.setSurfaceSize(const Size(1280, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: CommercialSummaryPage(
          readPeriod: reader,
          balanceRepository: balances,
          nowArgentina: () => DateTime.utc(2026, 11, 5),
        ),
      ),
    ),
  );
  await tester.pump();
}

Finder card(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(Card));

void expectAmount(String title, String amount) {
  expect(
    find.descendant(of: card(title), matching: find.text(amount)),
    findsOneWidget,
  );
}

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets('Fondo y tarjetas usan superficies oscuras en $platform', (
      tester,
    ) async {
      final isAndroid = platform == TargetPlatform.android;
      await tester.binding.setSurfaceSize(Size(isAndroid ? 390 : 1280, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            platform: platform,
            colorSchemeSeed: Colors.indigo,
            brightness: isAndroid ? Brightness.light : Brightness.dark,
          ),
          home: CommercialSummaryPage(
            readPeriod: (_, _) async => summary(returns: true),
            balanceRepository: FakeBalanceRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final title = find.text('Resumen comercial');
      final theme = Theme.of(tester.element(title));
      expect(theme.brightness, Brightness.dark);
      final background = tester.widget<Material>(
        find.ancestor(of: title, matching: find.byType(Material)).first,
      );
      expect(background.color, theme.colorScheme.surface);
      final tile = find.text('Ventas');
      await tester.ensureVisible(tile);
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(find.text('Mercadería entregada'), findsOneWidget);
      for (final cardWidget in tester.widgetList<Card>(find.byType(Card))) {
        expect(cardWidget.color, theme.colorScheme.surfaceContainerLow);
        expect(cardWidget.color!.computeLuminance(), lessThan(0.15));
      }
      expect(
        Theme.of(tester.element(find.text('Mercadería entregada'))).brightness,
        Brightness.dark,
      );
    });
  }

  testWidgets(
    'El desglose conserva diferencias negativas sin reclasificar cobros',
    (tester) async {
      await openSummary(tester, (_, _) async {
        return summary()
          ..['recaudacion_preventa'] = 550
          ..['recaudacion_sin_clasificar'] = -50;
      }, FakeBalanceRepository());
      await tester.tap(find.text('Cobros'));
      await tester.pumpAndSettle();
      expect(find.text('Cobros sin clasificar'), findsOneWidget);
      expectAmount('Cobros', r'$-50,00');
      expectAmount('RECAUDACIÓN', r'$500,00');
    },
  );

  testWidgets(
    'Los cuatro indicadores usan fuentes distintas y el detalle conserva adicionales y cobros históricos',
    (tester) async {
      final periods = <(DateTime, DateTime)>[];
      final balances = FakeBalanceRepository()..debt = 780000;
      await openSummary(tester, (start, end) async {
        periods.add((start, end));
        return summary();
      }, balances);
      expectAmount('VENTAS EFECTIVAS', r'$3.300,00');
      expectAmount('RECAUDACIÓN', r'$500,00');
      expectAmount('TOTAL POR COBRAR', r'$7.800,00');
      expectAmount('RESULTADO COMERCIAL', r'$970,00');
      expect(find.text('Ajustes y devoluciones'), findsNothing);
      expect(find.text('Ir a Saldos'), findsOneWidget);

      await tester.tap(find.text('Semana'));
      await tester.pumpAndSettle();
      expect(periods, [
        (DateTime.utc(2026, 11, 5, 3), DateTime.utc(2026, 11, 6, 3)),
        (DateTime.utc(2026, 11, 2, 3), DateTime.utc(2026, 11, 9, 3)),
      ]);
      expect(balances.accountReads, 1);
      expectAmount('TOTAL POR COBRAR', r'$7.800,00');
      expect(find.text('Ajustes y devoluciones'), findsNothing);

      await tester.tap(find.text('Ventas'));
      await tester.pumpAndSettle();
      expectAmount('Ventas', r'$2.300,00');
      expectAmount('Ventas', r'$4.000,00');
      await tester.tap(find.text('Cobros'));
      await tester.pumpAndSettle();
      expect(find.text(r'$500,00'), findsNWidgets(3));
      expect(find.text('Aplicado a ventas directas'), findsNothing);
      expectAmount('RECAUDACIÓN', r'$500,00');

      await tester.tap(find.text('Personalizado'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      final inputs = find.byType(TextField);
      await tester.enterText(inputs.at(0), '11/1/2026');
      await tester.enterText(inputs.at(1), '11/3/2026');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(periods.last, (
        DateTime.utc(2026, 11, 1, 3),
        DateTime.utc(2026, 11, 4, 3),
      ));
      expectAmount('TOTAL POR COBRAR', r'$7.800,00');
    },
  );

  testWidgets(
    'Una devolución histórica muestra los ajustes sin descontarlos dos veces',
    (tester) async {
      await openSummary(
        tester,
        (_, _) async => summary(returns: true),
        FakeBalanceRepository(),
      );
      await tester.tap(find.text('Semana'));
      await tester.pumpAndSettle();
      expectAmount('VENTAS EFECTIVAS', r'$3.300,00');
      expectAmount('RESULTADO COMERCIAL', r'$620,00');
      expect(find.text('Costo recuperado'), findsNothing);
      await tester.tap(find.text('Ajustes y devoluciones'));
      await tester.pumpAndSettle();
      expectAmount('Ajustes y devoluciones', r'$1.500,00');
      expectAmount('Ajustes y devoluciones', r'$1.000,00');
      expectAmount('Ajustes y devoluciones', r'$150,00');
      await tester.tap(find.text('Costos y rentabilidad'));
      await tester.pumpAndSettle();
      expectAmount('Costos y rentabilidad', r'$2.000,00');
      expect(find.text(r'$330,00'), findsNWidgets(2));
      expectAmount('Costos y rentabilidad', r'$620,00');
      await tester.tap(find.text('Cobros'));
      await tester.pumpAndSettle();
      expectAmount('Cobros', r'$400,00');
      expectAmount('RECAUDACIÓN', r'$500,00');
    },
  );

  testWidgets(
    'Un período vacío conserva la deuda y un dato ausente muestra error',
    (tester) async {
      var broken = false;
      await openSummary(tester, (_, _) async {
        final data = summary().map(
          (key, _) => MapEntry(
            key,
            key == 'comisiones_por_preventista' ? <String, dynamic>{} : 0,
          ),
        );
        if (broken) data.remove('ganancia');
        return data;
      }, FakeBalanceRepository()..debt = 780000);
      expectAmount('VENTAS EFECTIVAS', r'$0,00');
      expectAmount('TOTAL POR COBRAR', r'$7.800,00');
      broken = true;
      await tester.tap(find.text('Semana'));
      await tester.pumpAndSettle();
      expect(
        find.text('No se pudo cargar el resumen del período.'),
        findsOneWidget,
      );
      expectAmount('RESULTADO COMERCIAL', 'No disponible');
      expectAmount('TOTAL POR COBRAR', r'$7.800,00');
    },
  );

  testWidgets(
    'Una respuesta anterior no reemplaza el filtro activo y el error de deuda es visible',
    (tester) async {
      final today = Completer<Map<String, dynamic>>();
      await openSummary(
        tester,
        (start, _) => start.day == 5 ? today.future : Future.value(summary()),
        FakeBalanceRepository()..failReads = true,
      );
      await tester.tap(find.text('Semana'));
      await tester.pumpAndSettle();
      today.complete(summary()..['entrega_total'] = 999);
      await tester.pumpAndSettle();
      expectAmount('VENTAS EFECTIVAS', r'$3.300,00');
      expectAmount('TOTAL POR COBRAR', 'No disponible');
      expect(
        find.text('No se pudo consultar la deuda acumulada.'),
        findsOneWidget,
      );
    },
  );
}
