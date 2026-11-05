import 'dart:convert';

import 'package:distribuidora_alberdi/core/app_config.dart';
import 'package:distribuidora_alberdi/core/whatsapp_link.dart';
import 'package:distribuidora_alberdi/features/orders/order_detail_page.dart';
import 'package:distribuidora_alberdi/features/orders/order_summary_page.dart';
import 'package:distribuidora_alberdi/features/orders/order_whatsapp_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'helpers/outbox_fixture.dart';

const actor = '58d3ff72-9919-4a01-9fd9-28988d5121f6';
const customer = '108ac3fe-b37e-49cb-b5de-25d5de57ae27';
const mobile = '5491123456789';

void main() {
  test('Normaliza celulares argentinos solo con prefijo móvil inequívoco', () {
    for (final value in [
      '+54 (9) 11 2345-6789',
      '54 9 11 2345 6789',
      '9 11 2345 6789',
      '(011) 15-2345-6789',
      '11 15 2345 6789',
    ]) {
      expect(normalizeArgentineWhatsApp(value), mobile, reason: value);
    }
    expect(normalizeArgentineWhatsApp('(0341) 15 234-5678'), '5493412345678');
    expect(normalizeArgentineWhatsApp('02972 15 23-4567'), '5492972234567');
    for (final value in [
      null,
      '',
      '2345-6789',
      '15-2345-6789',
      '11 2345-6789',
      '+54 11 2345-6789',
      '011 2345-6789',
      '+1 202 555 0100',
      '+54 9 11 2345-6789 / 2345-6700',
      '11 15 2345-6789 int. 2',
      '+54 9 11 2345-678',
      '+54 9 011 2345-6789',
    ]) {
      expect(normalizeArgentineWhatsApp(value), isNull, reason: value);
    }
  });

  test('El enlace conserva saltos, acentos, signos y el importe', () {
    const text = 'Café & té\n2 x Queso + dulce — \$1.500\n¿Listo? #1\n';
    final uri = whatsAppLink(mobile, text: text);
    expect(uri.host, 'wa.me');
    expect(uri.path, '/$mobile');
    expect(uri.queryParameters, {'text': text});
    expect(uri.toString(), contains('%0A'));
    expect(whatsAppLink(mobile).hasQuery, isFalse);
  });

  group('Flujo de pedido guardado', () {
    late SupabaseClient client;
    late String? phone;
    late String owner;
    late int writes, creates;
    late bool launchOk, updateAllowed, allowCreate;
    late List<Uri> launches;

    setUp(() async {
      phone = null;
      owner = actor;
      writes = creates = 0;
      allowCreate = false;
      launchOk = updateAllowed = true;
      launches = [];
      activateAppConfig(fixtureConfig());
      client = mockClient((request) async {
        final table = request.url.pathSegments.last;
        final params = request.url.queryParameters;
        if (request.method == 'POST') {
          expect(allowCreate, isTrue);
          expect(table, 'crear_pedido_interno');
          expect(jsonDecode(request.body)['p_cliente_id'], customer);
          creates++;
          return jsonResponse(request, 'pedido');
        }
        if (request.method == 'PATCH') {
          writes++;
          expect(table, 'clientes');
          expect(params['id'], 'eq.$customer');
          expect(params['telefono'], phone == null ? 'is.null' : 'eq.$phone');
          expect(jsonDecode(request.body), {'telefono': '+$mobile'});
          if (!updateAllowed) {
            return jsonResponse(request, {
              'code': '42501',
              'message': 'denied',
            }, 403);
          }
          phone = '+$mobile';
          return jsonResponse(request, {'id': customer});
        }
        expect(request.method, 'GET');
        switch (table) {
          case 'clientes':
            expect(params['id'], 'eq.$customer');
            return jsonResponse(request, [
              {'telefono': phone, 'preventista_id': owner},
            ]);
          case 'usuarios':
            expect(params['id'], 'eq.$actor');
            return jsonResponse(request, [
              {'rol': 'preventista', 'activo': true},
            ]);
          case 'pedidos':
            expect(params['id'], 'eq.pedido');
            return jsonResponse(request, {
              'cliente_id': customer,
              'resultado_entrega': 'pendiente',
              'observacion': 'Entrega: timbre #2 & portón',
            });
          case 'pedido_detalles':
            return jsonResponse(request, [
              {
                'id': 'detalle',
                'cantidad': 2,
                'subtotal': 1500,
                'precio_unitario': 750,
                'productos': {'nombre': 'Café + té'},
              },
            ]);
          case 'pedido_pagos':
          case 'saldos_pendientes_pedidos':
            return jsonResponse(request, []);
          default:
            fail('Solicitud inesperada a $table');
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

    Future<void> openOrder(WidgetTester tester) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OrderWhatsAppButton(
            clientId: customer,
            client: client,
            message: () => 'Pedido ficticio',
            launch: (uri) async {
              launches.add(uri);
              return launchOk;
            },
          ),
        ),
      ),
    );

    Future<void> send(WidgetTester tester) async {
      await tester.tap(find.text('Enviar por WhatsApp'));
      await tester.pumpAndSettle();
    }

    testWidgets('Un teléfono cargado se usa directo y no se reescribe', (
      tester,
    ) async {
      phone = '(011) 15-2345-6789';
      await openOrder(tester);
      await send(tester);
      expect(launches.single.path, '/$mobile');
      expect(writes, 0);
      expect(find.text('Agregar número de WhatsApp'), findsNothing);
    });

    testWidgets('Valida el número y permite cancelar sin guardar ni abrir', (
      tester,
    ) async {
      await openOrder(tester);
      await send(tester);
      await tester.enterText(find.byType(TextFormField), '2345-6789');
      await tester.tap(find.text('Guardar y abrir'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Ingresá el celular como'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(writes, 0);
      expect(launches, isEmpty);
      expect(find.text('Enviar por WhatsApp'), findsOneWidget);
    });

    testWidgets('Guarda solo el teléfono una vez y lo reutiliza', (
      tester,
    ) async {
      await openOrder(tester);
      await send(tester);
      await tester.enterText(find.byType(TextFormField), '011 15 2345 6789');
      await tester.tap(find.text('Guardar y abrir'));
      await tester.pumpAndSettle();
      await send(tester);
      expect(launches.map((uri) => uri.path), ['/$mobile', '/$mobile']);
      expect(writes, 1);
    });

    testWidgets('Un preventista ajeno solo puede usarlo sin guardar', (
      tester,
    ) async {
      owner = 'otro-preventista';
      await openOrder(tester);
      await send(tester);
      expect(find.text('Guardar y abrir'), findsNothing);
      await tester.enterText(find.byType(TextFormField), '+$mobile');
      await tester.tap(find.text('Usar sin guardar'));
      await tester.pumpAndSettle();
      expect(launches.single.path, '/$mobile');
      expect(writes, 0);
    });

    testWidgets('La denegación de RLS interrumpe Guardar y abrir', (
      tester,
    ) async {
      updateAllowed = false;
      await openOrder(tester);
      await send(tester);
      await tester.enterText(find.byType(TextFormField), '+$mobile');
      await tester.tap(find.text('Guardar y abrir'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('No se pudo guardar el teléfono'),
        findsOneWidget,
      );
      expect(writes, 1);
      expect(launches, isEmpty);
    });

    testWidgets('Si falla el enlace, muestra el error y conserva el pedido', (
      tester,
    ) async {
      phone = '+$mobile';
      launchOk = false;
      await openOrder(tester);
      await send(tester);
      expect(find.textContaining('No se pudo abrir WhatsApp'), findsOneWidget);
      expect(find.text('Enviar por WhatsApp'), findsOneWidget);
      expect(writes, 0);
    });

    testWidgets('Un pedido recién guardado usa el teléfono del cliente nuevo', (
      tester,
    ) async {
      phone = '+$mobile';
      allowCreate = true;
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        launches.add(Uri.parse(call.arguments['url'] as String));
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await tester.binding.setSurfaceSize(const Size(900, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: OrderSummaryPage(
            client: client,
            cliente: const {
              'id': customer,
              'nombre_comercio': 'Comercio recién creado',
            },
            productos: const [
              {'id': 'p', 'nombre': 'Café', 'precio_normal': 750},
            ],
            cantidades: const {'p': 2},
            tipoPrecio: 'normal',
            preciosFijados: const {},
            tiposPrecioFijados: const {},
            fechaEntrega: DateTime(2026, 11, 5),
            tipoOperacion: 'pedido',
          ),
        ),
      );
      expect(find.text('Enviar por WhatsApp'), findsNothing);
      final confirm = find.text('CONFIRMAR PEDIDO');
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      // The saving indicator keeps animating beneath the confirmation dialog.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Pedido guardado'), findsOneWidget);
      await tester.tap(find.text('Enviar por WhatsApp'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(launches.single.path, '/$mobile');
      expect(
        launches.single.queryParameters['text'],
        contains('Comercio recién creado'),
      );
      expect(find.text('Pedido guardado'), findsOneWidget);
      expect(creates, 1);
      expect(writes, 0);
      await tester.tap(find.text('ACEPTAR'));
      await tester.pumpAndSettle();
    });

    testWidgets(
      'El detalle entrega exactamente el mismo texto a ambas acciones',
      (tester) async {
        phone = '+$mobile';
        const share = MethodChannel('dev.fluttercommunity.plus/share');
        const url = MethodChannel('plugins.flutter.io/url_launcher');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        String? sharedText;
        messenger.setMockMethodCallHandler(share, (call) async {
          expect(call.method, 'share');
          sharedText = call.arguments['text'] as String;
          return 'fixture';
        });
        messenger.setMockMethodCallHandler(url, (call) async {
          expect(call.method, 'launch');
          launches.add(Uri.parse(call.arguments['url'] as String));
          return true;
        });
        addTearDown(() {
          messenger.setMockMethodCallHandler(share, null);
          messenger.setMockMethodCallHandler(url, null);
        });
        await tester.pumpWidget(
          MaterialApp(
            home: OrderDetailPage(
              client: client,
              pedido: const {
                'id': 'pedido',
                'total': 1500,
                'tipo_operacion': 'pedido',
                'clientes': {'nombre_comercio': 'Almacén & Más'},
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        final state = tester.state(find.byType(OrderDetailPage));
        await tester.tap(find.byTooltip('Compartir pedido'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Enviar por WhatsApp'));
        await tester.pumpAndSettle();
        expect(sharedText, contains('Almacén & Más'));
        expect(sharedText, contains('2 x Café + té'));
        expect(
          sharedText,
          contains('Observación: Entrega: timbre #2 & portón'),
        );
        expect(launches.single.queryParameters['text'], sharedText);
        expect(tester.state(find.byType(OrderDetailPage)), same(state));
        expect(writes, 0);
      },
    );
  });
}
