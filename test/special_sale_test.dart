import 'package:distribuidora_alberdi/features/sales/special_sale_data.dart';
import 'package:distribuidora_alberdi/features/sales/special_sale_page.dart';
import 'package:distribuidora_alberdi/features/stock/stock_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const yerba = SaleProduct(
  id: 'a', name: 'Yerba x 1 kg', code: 'Y1', cost: 2500, controlled: true, deposit: 42, vehicle: 3,
  normal: 3400, promo: 3200, interior: 3600,
);
const azucar = SaleProduct(
  id: 'b', name: 'Azúcar x 1 kg', code: 'A1', cost: 950, controlled: false, deposit: 0, vehicle: 0, normal: 1150,
);

void main() {
  test('venta especial: margen, debajo del costo y mensaje', () {
    final l1 = SaleLine(yerba, quantity: 30, price: 3000);
    final l2 = SaleLine(azucar, quantity: 10, price: 900);
    expect(l1.total, 90000);
    expect(l1.profit, 15000);
    expect(l1.margin!, closeTo(0.1667, 0.001));
    expect(l2.belowCost, isTrue);
    expect(saleTotal([l1, l2]), 99000);
    expect(yerba.priceFor('interior'), 3600);
    expect(yerba.priceFor(null), 3400);
    final text = saleMessage(
      lines: [l1, l2],
      payments: {'Efectivo': 60000, 'Transferencia': 30000},
      when: DateTime(2026, 11, 20),
    );
    expect(text, contains('30 × Yerba x 1 kg — \$3.000 c/u = \$90.000'));
    expect(text, contains('Total: \$99.000'));
    expect(text, contains('Pagado: \$90.000 (efectivo \$60.000, transferencia \$30.000)'));
    expect(text, contains('Saldo: \$9.000'));
  });

  testWidgets('venta especial: precio a mano, margen y cobro a consumidor final', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    String? rpc;
    Map<String, dynamic>? args;
    await tester.pumpWidget(
      MaterialApp(
        home: SpecialSalePage(
          products: const [yerba, azucar],
          clients: const [SaleClient('k1', 'Kiosco Pepe', 'normal')],
          runner: (fn, a) async {
            rpc = fn;
            args = a;
            return const StockOpOutcome({'ganancia': 15000, 'saldo_pendiente': 0});
          },
        ),
      ),
    );
    expect(find.text('Consumidor final'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'yer');
    await tester.pump();
    await tester.tap(find.text('Yerba x 1 kg'));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('cant-a')), '30');
    await tester.enterText(find.byKey(const ValueKey('precio-a')), '3000');
    await tester.pump();
    expect(find.text('Ganás \$15.000 · 16,7%'), findsOneWidget);
    expect(find.text('\$90.000'), findsWidgets);
    await tester.tap(find.text('COBRAR Y CONFIRMAR'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TODO EFECTIVO'));
    await tester.pumpAndSettle();
    expect(rpc, 'venta_especial');
    expect(args!['p_cliente_id'], isNull);
    expect(args!['p_ubicacion'], 'deposito_alberdi');
    expect(args!['p_items'], [
      {'producto_id': 'a', 'cantidad': 30.0, 'precio_unitario': 3000.0},
    ]);
    expect(args!['p_pagos'], [
      {'medio': 'Efectivo', 'importe': 90000.0},
    ]);
    expect(find.text('Venta registrada'), findsOneWidget);
  });
}
