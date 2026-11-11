import 'dart:convert';

import 'package:distribuidora_alberdi/core/app_config.dart';
import 'package:distribuidora_alberdi/features/orders/admin_orders_page.dart';
import 'package:distribuidora_alberdi/features/orders/order_detail_page.dart';
import 'package:distribuidora_alberdi/features/orders/order_summary_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'helpers/outbox_fixture.dart';

Future<void> pickDate(WidgetTester tester) async {
  await tester.pumpAndSettle();
  final dialog = find.byType(DatePickerDialog);
  await tester.tap(
    find.descendant(of: dialog, matching: find.byIcon(Icons.edit_outlined)),
  );
  await tester.pumpAndSettle();
  await tester.enterText(
    find.descendant(of: dialog, matching: find.byType(TextFormField)),
    '11/12/2026',
  );
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

void main() {
  const order = {
    'id': 'order',
    'cliente_id': 'client',
    'clientes': {'nombre_comercio': 'Comercio QA'},
    'tipo_operacion': 'pedido',
    'tipo_precio': 'promo',
    'origen': 'catalogo',
    'estado': 'pendiente',
    'resultado_entrega': 'pendiente',
    'total': 800,
  };
  late SupabaseClient client;
  late String? date;
  late bool admin, invoiced;
  late List<String> reads;
  late List<Map<String, dynamic>> writes;

  setUp(() async {
    activateAppConfig(fixtureConfig());
    date = null;
    admin = true;
    invoiced = false;
    reads = [];
    writes = [];
    client = mockClient((request) async {
      final path = request.url.pathSegments.last;
      final q = request.url.queryParameters;
      if (request.method == 'POST') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        writes.add({...body, 'rpc': path});
        expect(
          path,
          anyOf('programar_entrega_catalogo', 'actualizar_pedido_activo'),
        );
        date = body['p_fecha_entrega'] as String;
        return jsonResponse(request, null);
      }
      expect(request.method, 'GET');
      switch (path) {
        case 'usuarios':
          return jsonResponse(request, [
            {'rol': admin ? 'administrador' : 'preventista', 'activo': true},
          ]);
        case 'pedidos':
          final row = {
            ...order,
            'fecha_entrega': date,
            'facturado': invoiced,
            'observacion': '[Catálogo web] QA',
          };
          if (q.containsKey('id')) return jsonResponse(request, row);
          final filter = q['fecha_entrega'] ?? '';
          reads.add(filter);
          if (filter == 'is.null') {
            expect(q['origen'], 'eq.catalogo');
            expect(q['facturado'], isNull);
            return jsonResponse(request, date == null ? [row] : []);
          }
          expect(q['facturado'], 'eq.true');
          return jsonResponse(
            request,
            invoiced && (filter.isEmpty || filter == 'eq.$date') ? [row] : [],
          );
        case 'pedido_detalles':
          return jsonResponse(request, [
            {
              'id': 'line',
              'pedido_id': 'order',
              'producto_id': 'product',
              'cantidad': 1,
              'precio_unitario': 800,
              'subtotal': 800,
              'tipo_precio': 'promo',
              'productos': {'nombre': 'Producto QA', 'codigo': 'QA'},
            },
          ]);
        case 'productos':
          return jsonResponse(request, [
            {'id': 'product', 'nombre': 'Producto QA', 'precio_promo': 900},
          ]);
        case 'pedido_pagos':
        case 'saldos_pendientes_pedidos':
        case 'correcciones_operacion':
          return jsonResponse(request, []);
        default:
          fail('Solicitud inesperada: $path');
      }
    }, autoRefreshToken: false);
    await client.auth.setInitialSession(
      jsonEncode({
        'access_token': 'e30.eyJleHAiOjQxMDI0NDQ4MDB9.fixture',
        'refresh_token': 'fixture',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': {
          'id': 'admin',
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
    'Administración encuentra, programa y filtra un pedido de catálogo',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1450, 950));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.windows),
          home: AdminOrdersPage(client: client),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Filtrar por fecha'));
      await pickDate(tester);
      expect(reads.last, 'eq.2026-11-12');
      await tester.tap(find.text('Sin programar'));
      await tester.pumpAndSettle();
      expect(reads.last, 'is.null');
      final program = find.textContaining(
        RegExp(r'^(Programar|PROGRAMAR ENTREGA)$'),
      );
      await tester.ensureVisible(program);
      await tester.tap(program);
      await tester.pumpAndSettle();
      expect(find.text('Entrega sin programar'), findsOneWidget);
      await tester.tap(find.text('Asignar fecha de entrega'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(writes, isEmpty);
      await tester.tap(find.text('Asignar fecha de entrega'));
      await pickDate(tester);
      expect(writes.single, {
        'rpc': 'programar_entrega_catalogo',
        'p_pedido_id': 'order',
        'p_fecha_entrega': '2026-11-12',
      });
      expect(find.text('Fecha de entrega: 2026-11-12'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        find.text('No hay pedidos de catálogo sin programar.'),
        findsOneWidget,
      );
      invoiced = true; // Simula el paso de facturación por separado.
      await tester.tap(find.text('Volver a reparto'));
      await tester.pumpAndSettle();
      expect(reads.last, 'eq.2026-11-12');
      expect(find.text('Comercio QA'), findsOneWidget);
    },
  );

  testWidgets(
    'Editor guarda cantidades y fecha elegida sin cambiar el precio previo',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: OrderDetailPage(pedido: order, client: client),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Editar pedido'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.add_circle));
      await tester.tap(find.text('Elegir fecha'));
      await pickDate(tester);
      await tester.tap(find.text('VER PEDIDO'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OrderSummaryPage>(find.byType(OrderSummaryPage))
            .fechaEntrega,
        DateTime(2026, 11, 12),
      );
      final save = find.text('CONFIRMAR PEDIDO');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(writes.single['rpc'], 'actualizar_pedido_activo');
      expect(writes.single['p_fecha_entrega'], '2026-11-12');
      expect(writes.single['p_observacion'], '[Catálogo web] QA');
      expect(
        (writes.single['p_detalles'] as List).single,
        containsPair('cantidad', 2),
      );
      expect(
        (writes.single['p_detalles'] as List).single,
        containsPair('precio_unitario', 800),
      );
      await tester.tap(find.text('ACEPTAR'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Un preventista no ve la acción administrativa y conserva la fecha existente',
    (tester) async {
      admin = false;
      date = '2026-11-12';
      await tester.pumpWidget(
        MaterialApp(
          home: OrderDetailPage(pedido: order, client: client),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Fecha de entrega: 2026-11-12'), findsOneWidget);
      expect(find.text('Asignar fecha de entrega'), findsNothing);
      await tester.tap(find.byTooltip('Editar pedido'));
      await tester.pumpAndSettle();
      expect(find.text('Elegir fecha'), findsNothing);
      await tester.tap(find.text('VER PEDIDO'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OrderSummaryPage>(find.byType(OrderSummaryPage))
            .fechaEntrega,
        DateTime(2026, 11, 12),
      );
      expect(writes, isEmpty);
    },
  );
}
