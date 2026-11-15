import 'package:distribuidora_alberdi/features/orders/order_whatsapp_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Pedido guardado: los botones de WhatsApp no desbordan en un celular angosto', (
    tester,
  ) async {
    for (final width in [320.0, 360.0, 412.0]) {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AlertDialog(
              title: const Text('Pedido guardado'),
              content: const Text('Total: \$4.200'),
              actions: [
                OrderWhatsAppButton(clientId: 'cliente', message: () => 'x'),
                FilledButton(onPressed: () {}, child: const Text('ACEPTAR')),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'ancho $width');
      expect(find.text('Otro número'), findsOneWidget);
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
