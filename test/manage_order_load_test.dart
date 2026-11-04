import 'package:distribuidora_alberdi/core/app_config.dart';
import 'package:distribuidora_alberdi/core/desktop_table.dart';
import 'package:distribuidora_alberdi/features/orders/manage_order_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'helpers/outbox_fixture.dart';

void main() {
  for (final operation in ['venta_directa', 'pedido']) {
    group(operation, () {
      late SupabaseClient client;
      late int detailReads;
      // Supabase owns a background isolate. Set up and dispose the mock
      // outside the widget test's fake clock.
      setUp(() {
        detailReads = 0;
        client = mockClient((request) async {
          expect(request.method, 'GET');
          expect(
            request.url.queryParameters['id'] ??
                request.url.queryParameters['pedido_id'],
            'eq.fixture-pedido',
          );
          switch (request.url.pathSegments.last) {
            case 'pedidos':
              return jsonResponse(request, {
                'origen': 'interno',
                'catalogo_preventista_id': null,
                'resultado_entrega': 'pendiente',
              });
            case 'pedido_detalles':
              detailReads++;
              final select = request.url.queryParameters['select'] ?? '';
              // Reproduces the authenticated grant observed in TESTING.
              if (RegExp(r'\bcosto\b').hasMatch(select)) {
                return jsonResponse(request, {
                  'code': '42501',
                  'message': 'permission denied for table productos',
                }, 403);
              }
              expect(select, contains('precio_normal'));
              return jsonResponse(request, [
                {
                  'id': 'fixture-linea',
                  'pedido_id': 'fixture-pedido',
                  'producto_id': 'fixture-producto',
                  'cantidad': 1,
                  'cantidad_facturada': operation == 'pedido' ? 1 : null,
                  'cantidad_entregada': 0,
                  'cantidad_no_entregada': 0,
                  'precio_unitario': 1500,
                  'tipo_precio': 'normal',
                  'productos': {
                    'nombre': 'Producto ficticio',
                    'precio_normal': 1600,
                    'comision_normal': 10,
                  },
                },
              ]);
            default:
              fail('Lectura inesperada: ${request.url.pathSegments.last}');
          }
        }, autoRefreshToken: false);
      });
      testWidgets(
        'opens pending $operation with TESTING column grants',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(1280, 1250);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final config = fixtureConfig();
          activateAppConfig(config);
          expect(config.usesV2For(operation), isTrue);
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(platform: TargetPlatform.windows),
              home: ManageOrderPage(
                pedido: {
                  'id': 'fixture-pedido',
                  'tipo_operacion': operation,
                  'resultado_entrega': 'pendiente',
                  'facturado': operation == 'pedido',
                },
                client: client,
                requestStore: memoryStore(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(detailReads, 1);
          expect(find.text('No se pudo cargar el pedido.'), findsNothing);
          expect(
            useDesktopLayout(tester.element(find.byType(ManageOrderPage))),
            isTrue,
          );
          final modify = find.ancestor(
            of: find.text('MODIFICAR ENTREGA'),
            matching: find.byType(RadioListTile<String>),
          );
          await tester.ensureVisible(modify);
          await tester.tap(modify);
          await tester.pumpAndSettle();
          expect(
            tester.widget<RadioListTile<String>>(modify).groupValue,
            'parcial',
          );
          final quantity = find.byKey(const ValueKey('entregar-fixture-linea'));
          expect(quantity, findsOneWidget);
          await tester.ensureVisible(quantity);
          expect(tester.widget<TextField>(quantity).controller!.text, '1');
          await tester.enterText(quantity, '2');
          await tester.pumpAndSettle();
          final breakdown = find.textContaining('1 adicionales a');
          if (operation == 'venta_directa') {
            expect(breakdown, findsOneWidget);
            expect(
              find.text(
                r'1 del pedido a $1.500,00 + 1 adicionales a $1.600,00',
              ),
              findsOneWidget,
            );
            await tester.enterText(quantity, '1');
            await tester.pumpAndSettle();
          }
          expect(breakdown, findsNothing);
          expect(tester.takeException(), isNull);
        },
        timeout: const Timeout(Duration(seconds: 30)),
      );
    });
  }
}
