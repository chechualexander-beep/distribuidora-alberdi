import 'package:distribuidora_alberdi/core/money_format.dart';
import 'package:distribuidora_alberdi/features/orders/payment_choice.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

String typed(String keys) {
  const f = ImporteInputFormatter();
  var value = TextEditingValue.empty;
  for (final ch in keys.split('')) {
    final next = TextEditingValue(text: value.text + ch);
    value = f.formatEditUpdate(value, next);
  }
  return value.text;
}

void main() {
  test('plata: puntos de miles y decimales solo si existen', () {
    expect(formatoPesos(100000), r'$100.000');
    expect(formatoPesos(1500.5), r'$1.500,50');
    expect(formatoPesos(1500), r'$1.500');
    expect(formatoPesos('2300000.00'), r'$2.300.000');
    expect(formatoPesos(-200), r'-$200');
    expect(formatoPesos(0), r'$0');
    expect(formatoPesos(null), r'$0');
    expect(formatoPesos(999.999), r'$1.000');
    expect(formatoNumero(1234567.8), '1.234.567,80');
  });

  test('leer importes como se escriben en Argentina', () {
    expect(leerImporte('100.000'), 100000);
    expect(leerImporte('1.500,50'), 1500.5);
    expect(leerImporte('1500'), 1500);
    expect(leerImporte('12.25'), 12.25);
    expect(leerImporte(r'$ 2.300.000'), 2300000);
    expect(leerImporte(''), isNull);
    expect(leerImporte('x'), isNull);
  });

  test('al escribir aparecen los puntos; el punto final se toma como coma', () {
    expect(typed('100000'), '100.000');
    expect(typed('1500.5'), '1.500,5');
    expect(typed('1500,505'), '1.500,50');
    expect(typed('007'), '7');
    const f = ImporteInputFormatter();
    expect(f.formatEditUpdate(TextEditingValue.empty, const TextEditingValue(text: '12.25')).text, '12,25');
    expect(f.formatEditUpdate(TextEditingValue.empty, const TextEditingValue(text: '1.225')).text, '1.225');
  });

  test('pago: todo con un medio, mixto o dejó saldo', () {
    var p = planPago(const PaymentChoice(todo: 'Efectivo'), 10000);
    expect(p.completo, 'Efectivo');
    p = planPago(const PaymentChoice(efectivo: 3000, transferencia: 7000), 10000);
    expect([p.parcialMedio, p.parcialImporte, p.segundoMedio, p.segundoImporte], ['Efectivo', 3000, 'Transferencia', 7000]);
    p = planPago(const PaymentChoice(transferencia: 10000), 10000);
    expect(p.completo, 'Transferencia', reason: 'un solo medio por todo = completo');
    p = planPago(const PaymentChoice(efectivo: 4000), 10000);
    expect([p.parcialMedio, p.parcialImporte, p.segundoImporte], ['Efectivo', 4000, null]);
    expect(planPago(const PaymentChoice(), 10000).sinPago, isTrue);
  });

  testWidgets('pago mixto: escribir la transferencia completa el efectivo', (tester) async {
    PaymentChoice? elegido;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async => elegido = await showPaymentChoice(context, aCobrar: 10000),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.text(r'$10.000'), findsOneWidget);
    await tester.tap(find.text('MIXTO O DEJÓ SALDO'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('pago-transferencia')), '7000');
    await tester.pump();
    expect(find.widgetWithText(TextField, '3.000'), findsOneWidget);
    expect(find.text(r'Cobrado $10.000 · no queda saldo'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('pago-efectivo')), '1000');
    await tester.pump();
    expect(find.text(r'Cobrado $8.000 · queda debiendo $2.000'), findsOneWidget);
    await tester.tap(find.text('CONFIRMAR'));
    await tester.pumpAndSettle();
    expect(elegido!.transferencia, 7000);
    expect(elegido!.efectivo, 1000);
  });
}
