import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:distribuidora_alberdi/features/admin/widgets/commercial_summary_card.dart';

void main() {
  testWidgets('El total permanece visible al abrir y cerrar el desglose', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CommercialSummaryCard(
              title: 'RECAUDACIÓN',
              icon: Icons.payments_outlined,
              total: 1250.75,
              description: 'Cobrado en el período',
              breakdown: {
                'Aplicado a preventa': 900.25,
                'Aplicado a venta directa': 300.50,
                'Sin clasificar': 50,
              },
              note: 'Puede pagar deudas anteriores.',
            ),
          ),
        ),
      ),
    );
    expect(find.text(r'$1.250,75'), findsOneWidget);
    expect(find.text('Aplicado a preventa'), findsNothing);
    await tester.tap(find.text('RECAUDACIÓN'));
    await tester.pumpAndSettle();
    expect(find.text(r'$1.250,75'), findsOneWidget);
    expect(find.text(r'$900,25'), findsOneWidget);
    expect(find.text(r'$300,50'), findsOneWidget);
    expect(find.text('Sin clasificar'), findsOneWidget);
    await tester.tap(find.text('RECAUDACIÓN'));
    await tester.pumpAndSettle();
    expect(find.text('Aplicado a preventa'), findsNothing);
    expect(find.text(r'$1.250,75'), findsOneWidget);
  });

  testWidgets('La tarjeta admite importes grandes y texto ampliado en móvil', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: CommercialSummaryCard(
                title: 'MERCADERÍA ENTREGADA',
                icon: Icons.inventory_2_outlined,
                total: 123456789.25,
                description: 'Valor a precio de venta en el período',
                breakdown: const {'Preventa': 123456789.25, 'Venta directa': 0},
                note: 'Por fecha de finalización.',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('MERCADERÍA ENTREGADA'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Venta directa'), findsOneWidget);
  });
}
