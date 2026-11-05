import 'package:distribuidora_alberdi/core/app_config.dart';
import 'package:distribuidora_alberdi/core/desktop_table.dart';
import 'package:distribuidora_alberdi/features/orders/manage_order_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'helpers/outbox_fixture.dart';
import 'helpers/balance_fixture.dart';

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
          final clientScoped = request.url.queryParameters['cliente_id'];
          if (clientScoped != null) {
            expect(clientScoped, 'eq.client');
            return jsonResponse(request, []);
          }
          if (request.url.pathSegments.last == 'clientes') {
            expect(request.url.queryParameters['id'], 'eq.client');
            return jsonResponse(request, [
              {
                'id': 'client',
                'nombre_comercio': 'Comercio QA',
                'direccion': 'Calle de prueba 123',
                if (operation == 'venta_directa') ...{
                  'latitud': -34.6,
                  'longitud': -58.4,
                },
              },
            ]);
          }
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
          final requests = memoryStore();
          activateAppConfig(config);
          expect(config.usesV2For(operation), isTrue);
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(platform: TargetPlatform.windows),
              home: ManageOrderPage(
                pedido: {
                  'id': 'fixture-pedido',
                  'cliente_id': 'client',
                  'tipo_operacion': operation,
                  'resultado_entrega': 'pendiente',
                  'facturado': operation == 'pedido',
                },
                client: client,
                requestStore: requests,
                balanceRepository: FakeBalanceRepository(),
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
          final controller = tester.widget<TextField>(quantity).controller;
          final link = find.text('Ver ficha');
          await tester.ensureVisible(link);
          final scrollable = find
              .descendant(
                of: find.byType(ManageOrderPage),
                matching: find.byType(Scrollable),
              )
              .first;
          final offset = tester
              .state<ScrollableState>(scrollable)
              .position
              .pixels;
          await tester.tap(link);
          await tester.pumpAndSettle();
          expect(find.text('Ficha del cliente'), findsOneWidget);
          expect(find.text('Calle de prueba 123'), findsOneWidget);
          expect(
            find.text('ABRIR EN MAPA'),
            operation == 'venta_directa' ? findsOneWidget : findsNothing,
          );
          expect(find.text('Nuevo pedido'), findsNothing);
          expect(find.text('Ver saldo / Registrar pago'), findsNothing);
          await tester.pageBack();
          await tester.pumpAndSettle();
          expect(
            tester.state<ScrollableState>(scrollable).position.pixels,
            offset,
          );
          expect(detailReads, 1);
          expect(
            tester.widget<TextField>(quantity).controller,
            same(controller),
          );
          expect(controller!.text, '2');
          await tester.tap(find.byTooltip('Ver saldo / Registrar pago'));
          await tester.pumpAndSettle();
          expect(find.text('Saldo del cliente'), findsOneWidget);
          await tester.pageBack();
          await tester.pumpAndSettle();
          expect(tester.widget<TextField>(quantity).controller!.text, '2');
          await requests.prepare(
            'fixture-pedido',
            operational(),
            physicalDate: DateTime.utc(2026, 11, 5),
          );
          await tester.tap(find.byTooltip('Ver saldo / Registrar pago'));
          await tester.pumpAndSettle();
          expect(find.textContaining('Solo consulta mientras'), findsOneWidget);
          expect(find.text('Registrar pago'), findsNothing);
          await tester.pageBack();
          await tester.pumpAndSettle();
          expect(tester.widget<TextField>(quantity).controller!.text, '2');
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
