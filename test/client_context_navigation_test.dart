import 'dart:convert';

import 'package:distribuidora_alberdi/core/app_config.dart';
import 'package:distribuidora_alberdi/features/clients/client_detail_link.dart';
import 'package:distribuidora_alberdi/features/clients/client_detail_page.dart';
import 'package:distribuidora_alberdi/features/orders/admin_orders_page.dart';
import 'package:distribuidora_alberdi/features/orders/new_order_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'helpers/outbox_fixture.dart';

const actor = '58d3ff72-9919-4a01-9fd9-28988d5121f6';
const clientId = '108ac3fe-b37e-49cb-b5de-25d5de57ae27';
const customer = {
  'id': clientId,
  'activo': true,
  'preventista_id': actor,
  'nombre_comercio': 'Comercio ficticio',
  'direccion': 'Dirección original',
  'tipo_precio_habitual': 'interior',
};

void main() {
  late SupabaseClient client;
  late String role;
  late bool active, clientAvailable;
  late int clientReads, accountReads, historyReads;

  setUp(() async {
    role = 'preventista';
    active = true;
    clientAvailable = true;
    clientReads = accountReads = historyReads = 0;
    activateAppConfig(fixtureConfig());
    client = mockClient((request) async {
      expect(request.method, 'GET');
      final params = request.url.queryParameters;
      switch (request.url.pathSegments.last) {
        case 'usuarios':
          expect(params['id'], 'eq.$actor');
          return jsonResponse(request, {'rol': role, 'activo': active});
        case 'clientes':
          clientReads++;
          expect(params['id'], 'eq.$clientId');
          if (params['select'] != '*') {
            expect(params['activo'], 'eq.true');
            expect(
              params['preventista_id'],
              role == 'preventista' ? 'eq.$actor' : null,
            );
          }
          return jsonResponse(
            request,
            clientAvailable
                ? [
                    {...customer, 'direccion': 'Dirección actualizada'},
                  ]
                : [],
          );
        case 'saldos_pendientes_clientes':
          accountReads++;
          expect(params['cliente_id'], 'eq.$clientId');
          return jsonResponse(request, [
            {'saldo_pendiente': 200, 'cantidad_pedidos_con_saldo': 1},
          ]);
        case 'pedidos':
          if (params['cliente_id'] == null) {
            return jsonResponse(
              request,
              List.generate(
                24,
                (i) => {
                  'id': 'pedido-$i',
                  'cliente_id': clientId,
                  'tipo_operacion':
                      params['tipo_operacion'] == 'eq.venta_directa'
                      ? 'venta_directa'
                      : 'pedido',
                  'resultado_entrega': 'pendiente',
                  'total': 500,
                  'clientes': {'nombre_comercio': 'Comercio $i'},
                },
              ),
            );
          }
          historyReads++;
          expect(params['cliente_id'], 'eq.$clientId');
          return jsonResponse(request, []);
        case 'saldos_pendientes_pedidos':
        case 'cobros_cliente':
          expect(params['cliente_id'], 'eq.$clientId');
          return jsonResponse(request, []);
        case 'pedido_detalles':
          expect(params['pedido_id'], startsWith('in.'));
          return jsonResponse(request, []);
        default:
          fail('Lectura inesperada: ${request.url.pathSegments.last}');
      }
    }, autoRefreshToken: false);
    await client.auth.setInitialSession(
      jsonEncode({
        'access_token': 'e30.eyJleHAiOjQxMDI0NDQ4MDB9.fixture',
        'refresh_token': 'fixture',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': {
          'id': actor,
          'aud': 'authenticated',
          'role': 'authenticated',
          'app_metadata': {},
          'user_metadata': {},
          'created_at': '2026-01-01T00:00:00Z',
        },
      }),
    );
  });

  testWidgets(
    'La lista de reparto mantiene el filtro, la selección y el desplazamiento',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1500, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.windows),
          home: AdminOrdersPage(client: client),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('VENTA DIRECTA'));
      await tester.pumpAndSettle();
      final vertical = find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .last;
      final position = tester.state<ScrollableState>(vertical).position;
      position.jumpTo(265);
      await tester.pumpAndSettle();
      final checkbox = find.byType(Checkbox).hitTestable().first;
      await tester.tap(checkbox);
      await tester.pumpAndSettle();
      final offset = position.pixels;
      await tester.tap(find.text('Ver ficha').hitTestable().first);
      await tester.pumpAndSettle();
      expect(find.text('Ficha del cliente'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(tester.state<ScrollableState>(vertical).position, same(position));
      expect(position.pixels, offset);
      expect(
        tester
            .widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>))
            .selected,
        {true},
      );
      expect(tester.widget<Checkbox>(checkbox).value, isTrue);
    },
  );

  testWidgets(
    'La ficha abre Nuevo pedido por UUID y conserva su estado al cancelar',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ClientDetailPage(cliente: {...customer}, client: client),
        ),
      );
      await tester.pumpAndSettle();
      final detailState = tester.state(find.byType(ClientDetailPage));
      await tester.tap(find.text('Nuevo pedido'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<NewOrderPage>(find.byType(NewOrderPage)).clienteId,
        clientId,
      );
      expect(find.text('Cliente seleccionado'), findsOneWidget);
      expect(find.text('Dirección actualizada'), findsOneWidget);
      expect(clientReads, 1);
      expect(accountReads, 2);
      expect(historyReads, 2);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(ClientDetailPage)), same(detailState));
      expect(find.text('Dirección original'), findsOneWidget);
      expect(clientReads, 1);
    },
  );

  testWidgets('Un cliente desactivado o ajeno no ofrece Nuevo pedido', (
    tester,
  ) async {
    for (final values in [
      {'activo': false},
      {'preventista_id': 'otro-preventista'},
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: ClientDetailPage(
            key: UniqueKey(),
            cliente: {...customer, ...values},
            client: client,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Nuevo pedido'), findsNothing);
    }
    expect(clientReads, 0);
  });

  testWidgets('Un usuario inactivo no puede abrir un pedido contextual', (
    tester,
  ) async {
    active = false;
    await tester.pumpWidget(
      MaterialApp(
        home: NewOrderPage(clienteId: clientId, client: client),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Tu usuario no tiene permiso para crear pedidos.'),
      findsOneWidget,
    );
    expect(clientReads, 0);
  });

  testWidgets(
    'Un cliente eliminado o fuera del alcance tiene mensajes claros',
    (tester) async {
      clientAvailable = false;
      await tester.pumpWidget(
        MaterialApp(
          home: NewOrderPage(clienteId: clientId, client: client),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('El cliente no está disponible para crear pedidos.'),
        findsOneWidget,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ClientDetailLink(clientId: clientId, client: client),
          ),
        ),
      );
      await tester.tap(find.text('Ver ficha'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'El cliente ya no existe o no está disponible para tu usuario.',
        ),
        findsOneWidget,
      );
    },
  );
}
