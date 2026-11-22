import 'package:distribuidora_alberdi/core/page_switch.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Facturar extends StatefulWidget {
  const _Facturar();
  @override
  State<_Facturar> createState() => _FacturarState();
}

class _FacturarState extends State<_Facturar> {
  int vista = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Facturar'),
      bottom: pageSwitch(
        labels: const ['Para facturar', 'Realizadas'],
        selected: vista,
        onChanged: (v) => setState(() => vista = v),
      ),
    ),
    body: Text(vista == 0 ? 'lista para facturar' : 'lista de realizadas'),
  );
}

void main() {
  testWidgets('vistas de una pantalla: Para facturar y Realizadas en el mismo lugar', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _Facturar()));
    expect(find.text('lista para facturar'), findsOneWidget);
    await tester.tap(find.text('Realizadas'));
    await tester.pumpAndSettle();
    expect(find.text('lista de realizadas'), findsOneWidget);
    expect(find.text('Facturar'), findsOneWidget, reason: 'el título no cambia');
  });
}
