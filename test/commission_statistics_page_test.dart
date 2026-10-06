import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:distribuidora_alberdi/features/commissions/commission_statistics_page.dart';

Map<String, dynamic> data({bool empty = false}) => {
  'venta_neta': -200,
  'venta_bruta': 0,
  'devoluciones': 200,
  'comision_neta': -20,
  'comision_bruta': 0,
  'ajustes': 20,
  'clientes': 0,
  'promedio': null,
  'hay_movimientos': !empty,
  'semanal': false,
  'ranking_clientes': empty
      ? []
      : [
          {
            'id': 'c',
            'nombre': 'Cliente de prueba',
            'venta': -200,
            'comision': -20,
            'operaciones': [
              {
                'pedido_id': '12345678-abcd',
                'dia': '2026-09-28',
                'tipo': 'Devolución',
                'venta': -200,
                'comision': -20,
              },
            ],
          },
        ],
  'ranking_productos': empty
      ? []
      : [
          {
            'nombre': 'Producto presentación 10 kg',
            'cantidad': -2,
            'venta': -200,
            'comision': -20,
          },
        ],
  'serie': [
    {'dia': '2026-09-28', 'venta': -200, 'comision': -20},
  ],
};
void main() {
  testWidgets('Administrador ve selector desde acceso sin indicador de rol', (
    tester,
  ) async {
    final consultas = <Map<String, dynamic>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: CommissionStatisticsPage(
          administratorLoader: () async => true,
          usersLoader: () async => [
            {'id': 'vendedor-1', 'nombre': 'Ana', 'apellido': 'Prueba'},
          ],
          loader: (params) async {
            consultas.add(params);
            return data(empty: true);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Resultados comerciales'), findsOneWidget);
    expect(find.text('Preventista'), findsOneWidget);
    expect(consultas.last['p_preventista_id'], isNull);
    await tester.tap(find.text('Todos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ana Prueba').last);
    await tester.pumpAndSettle();
    expect(consultas.last['p_preventista_id'], 'vendedor-1');
  });

  for (final width in [360.0, 1200.0]) {
    testWidgets('Dashboard y detalle sin desbordes a ancho $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            platform: width >= 900
                ? TargetPlatform.windows
                : TargetPlatform.android,
          ),
          home: CommissionStatisticsPage(
            administratorLoader: () async => false,
            loader: (_) async => data(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Comisión neta generada'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text(width >= 900 ? 'Cliente de prueba' : '1. Cliente de prueba'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(width >= 900 ? 'Cliente de prueba' : '1. Cliente de prueba'),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Devolución ·'), findsOneWidget);
      await tester.tap(find.text('Cerrar'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.widgetWithText(ChoiceChip, 'Cantidad'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Cantidad'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('Error visible y reintento sin confundirlo con cero', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: CommissionStatisticsPage(
          administratorLoader: () async => false,
          loader: (_) async {
            if (calls++ == 0) throw Exception('offline');
            return data(empty: true);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.text('Comisión neta generada'), findsNothing);
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(
      find.text('No hay entregas ni devoluciones en este período.'),
      findsOneWidget,
    );
  });
  testWidgets('Una respuesta vieja no reemplaza el nuevo período', (
    tester,
  ) async {
    final old = Completer<Map<String, dynamic>>();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: CommissionStatisticsPage(
          administratorLoader: () async => false,
          loader: (_) {
            return calls++ == 0 ? old.future : Future.value(data(empty: true));
          },
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Esta semana'));
    await tester.pumpAndSettle();
    old.complete(data());
    await tester.pumpAndSettle();
    expect(
      find.text('No hay entregas ni devoluciones en este período.'),
      findsOneWidget,
    );
  });
}
