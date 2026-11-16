import 'dart:async';
import 'dart:convert';

import 'package:distribuidora_alberdi/core/app_config.dart';
import 'package:distribuidora_alberdi/core/network_status.dart';
import 'package:distribuidora_alberdi/core/offline_queries.dart';
import 'package:distribuidora_alberdi/core/pending_orders.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'helpers/outbox_fixture.dart';

PendingOrder pedido(String id, {String tipo = 'pedido'}) => PendingOrder(
  params: {'p_id': id, 'p_tipo_operacion': tipo, 'p_detalles': []},
  clientName: 'Kiosco $id',
  total: 1500,
  createdAt: DateTime(2026, 11, 16, 9),
);

PendingOrder pedidoDe(String id, String clienteId) => PendingOrder(
  params: {'p_id': id, 'p_cliente_id': clienteId, 'p_tipo_operacion': 'pedido', 'p_detalles': []},
  clientName: 'Almacén nuevo',
  total: 900,
  createdAt: DateTime(2026, 11, 16, 10),
);

PendingOrder clienteNuevo(String id) => PendingOrder.client({
  'id': id,
  'nombre_comercio': 'Almacén nuevo',
  'direccion': 'Ruta 5 km 12',
  'preventista_id': 'mary',
  'activo': true,
}, createdAt: DateTime(2026, 11, 16, 9, 30));

Future<SupabaseClient> sesion(String uid) async {
  final client = mockClient((request) async => jsonResponse(request, {}), autoRefreshToken: false);
  await client.auth.setInitialSession(
    jsonEncode({
      'access_token': 'e30.eyJleHAiOjQxMDI0NDQ4MDB9.fixture',
      'refresh_token': 'r',
      'token_type': 'bearer',
      'expires_in': 3600,
      'user': {
        'id': uid,
        'aud': 'authenticated',
        'role': 'authenticated',
        'app_metadata': {},
        'user_metadata': {},
        'created_at': '2026-01-01T00:00:00Z',
      },
    }),
  );
  return client;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final cola = PendingOrders.instance;
  setUp(() {
    activateAppConfig(fixtureConfig());
    SharedPreferences.setMockInitialValues({});
    connectionProblem.value = false;
  });
  tearDown(() {
    cola.stop();
    connectionProblem.value = false;
  });

  test('sin señal queda guardado; al volver se envía una sola vez con la misma solicitud', () async {
    var online = false;
    final enviados = <String>[];
    final client = await sesion('mary');
    await cola.start(client, send: (params) async {
      if (!online) throw http.ClientException('sin red');
      enviados.add(params['p_id'] as String);
    });
    await cola.add(pedido('a'));
    await cola.add(pedido('b', tipo: 'venta_directa'));
    await cola.add(pedido('a')); // el mismo pedido no se duplica en la cola
    expect(cola.items.value.map((o) => o.id), ['b', 'a']);
    expect(await cola.sendAll(), 0);
    expect(cola.items.value, hasLength(2));

    // Al reabrir la app siguen ahí.
    cola.stop();
    await cola.start(client, send: (params) async {
      if (!online) throw TimeoutException('lento');
      enviados.add(params['p_id'] as String);
    });
    expect(cola.items.value, hasLength(2));
    expect(cola.items.value.last.isDirectSale, isFalse);
    expect(cola.items.value.first.isDirectSale, isTrue);

    // La señal vuelve justo mientras sigue el intento que hizo al abrir: igual se envía.
    online = true;
    connectionProblem.value = true;
    connectionProblem.value = false; // "volvió la conexión": envía solo
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(enviados, ['b', 'a']);
    expect(cola.items.value, isEmpty);
  });

  test('si el servidor lo rechaza queda marcado para revisar y no se reintenta', () async {
    var llamadas = 0;
    final client = await sesion('mary');
    await cola.start(client, send: (params) async {
      llamadas++;
      throw const PostgrestException(message: 'Los precios cambiaron. Actualizá los productos', code: 'P0001');
    });
    await cola.add(pedido('c'));
    await cola.sendAll();
    expect(cola.items.value.single.rejected, contains('precios cambiaron'));
    final antes = llamadas;
    await cola.sendAll();
    expect(llamadas, antes, reason: 'los rechazados no se reenvían solos');
    await cola.discard('c');
    expect(cola.items.value, isEmpty);
  });

  test('cada usuario tiene su propia cola', () async {
    await cola.start(await sesion('mary'), send: (_) async => throw http.ClientException('x'));
    await cola.add(pedido('m'));
    cola.stop();
    await cola.start(await sesion('juan'), send: (_) async => throw http.ClientException('x'));
    expect(cola.items.value, isEmpty);
    cola.stop();
    await cola.start(await sesion('mary'), send: (_) async => throw http.ClientException('x'));
    expect(cola.items.value.single.id, 'm');
  });

  test('errores dudosos vs. rechazos del servidor', () {
    expect(isUncertainRequestError(TimeoutException('x')), isTrue);
    expect(isUncertainRequestError(http.ClientException('x')), isTrue);
    expect(isUncertainRequestError(const PostgrestException(message: 'gw', code: '502')), isTrue);
    expect(isUncertainRequestError(const PostgrestException(message: 'no', code: 'P0001')), isFalse);
  });

  test('reintenta solo cada 30 segundos mientras haya pendientes', () {
    expect(PendingOrders.retryEvery, const Duration(seconds: 30));
  });

  test('al volver a la app intenta enviar enseguida', () async {
    final binding = TestWidgetsFlutterBinding.instance;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    var online = false;
    final enviados = <String>[];
    await cola.start(await sesion('mary'), send: (params) async {
      if (!online) throw http.ClientException('sin red');
      enviados.add(params['p_id'] as String);
    });
    await cola.add(pedido('r'));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    online = true;
    // Simula que el usuario vuelve a la app (desde WhatsApp, o al desbloquear).
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(enviados, ['r']);
    expect(cola.items.value, isEmpty);
  });

  test('cliente nuevo sin señal: sale primero y su pedido espera hasta que llegue', () async {
    var online = false;
    var clienteRechazado = false;
    final enviados = <String>[];
    await cola.start(
      await sesion('mary'),
      send: (params) async {
        if (!online) throw http.ClientException('sin red');
        enviados.add('pedido ${params['p_id']}');
      },
      sendClient: (row) async {
        if (!online) throw http.ClientException('sin red');
        if (clienteRechazado) {
          throw const PostgrestException(message: 'dato inválido', code: '23514');
        }
        enviados.add('cliente ${row['id']}');
      },
    );
    // El pedido se guardó antes en la cola, pero igual sale después del cliente.
    await cola.add(pedidoDe('p1', 'c1'));
    await cola.add(clienteNuevo('c1'));
    await cola.add(pedido('otro'));
    expect(cola.isPendingClient('c1'), isTrue);
    expect(cola.pendingClient('c1')?[PendingOrders.sinEnviarKey], isTrue);
    expect(cola.ordersOf('c1'), 1);

    // Al reabrir sigue sabiendo que es un cliente.
    final guardado = cola.items.value.firstWhere((o) => o.id == 'c1');
    final copia = PendingOrder.fromJson(guardado.toJson());
    expect(copia.isClient, isTrue);
    expect(copia.clientId, 'c1');
    expect(copia.params.containsKey(PendingOrders.sinEnviarKey), isFalse,
        reason: 'la marca nunca se manda al servidor');

    online = true;
    expect(await cola.sendAll(), 3);
    expect(enviados, ['cliente c1', 'pedido p1', 'pedido otro']);
    expect(cola.isPendingClient('c1'), isFalse);

    // Si el servidor rechaza el cliente, su pedido no se manda (fallaría) y espera.
    enviados.clear();
    clienteRechazado = true;
    await cola.add(clienteNuevo('c2'));
    await cola.add(pedidoDe('p2', 'c2'));
    await cola.sendAll();
    expect(enviados, isEmpty);
    expect(cola.items.value.firstWhere((o) => o.id == 'c2').rejected, contains('dato inválido'));
    expect(cola.items.value.firstWhere((o) => o.id == 'p2').rejected, isNull);

    // Descartar el cliente descarta también sus pedidos.
    await cola.discard('c2');
    expect(cola.items.value, isEmpty);
  });

  test('alta del cliente: si ya había llegado (respuesta perdida) cuenta como enviado', () async {
    var respuesta = 409;
    var cuerpo = {'code': '23505', 'message': 'duplicate key value violates unique constraint "clientes_pkey"'};
    final client = mockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, endsWith('/rest/v1/clientes'));
      return jsonResponse(request, cuerpo, respuesta);
    });
    await insertPendingClient(client, {'id': 'c1', 'nombre_comercio': 'A', 'direccion': 'B'});

    respuesta = 400;
    cuerpo = {'code': '23514', 'message': 'violates check constraint'};
    await expectLater(
      insertPendingClient(client, {'id': 'c1', 'nombre_comercio': 'A', 'direccion': 'B'}),
      throwsA(isA<PostgrestException>()),
    );
  });

  test('el cliente sin enviar aparece en las listas y su ficha no va a internet', () async {
    await cola.start(await sesion('mary'), send: (_) async => throw http.ClientException('x'),
        sendClient: (_) async => throw http.ClientException('x'));
    await cola.add(clienteNuevo('c9'));
    final lista = conClientesSinEnviar([
      {'id': 'a', 'nombre_comercio': 'Zapatería'},
      {'id': 'b', 'nombre_comercio': 'Bazar'},
    ]);
    expect(lista.map((c) => c['nombre_comercio']), ['Almacén nuevo', 'Bazar', 'Zapatería']);
    expect(conClientesSinEnviar([{'id': 'c9', 'nombre_comercio': 'Almacén nuevo'}]), hasLength(1),
        reason: 'cuando ya llegó, no se repite');

    // Sin red: estas consultas contestan desde el teléfono.
    final sinRed = mockClient((request) async => throw http.ClientException('sin red'));
    expect(
      (await consultarClienteParaPedido(sinRed, uid: 'mary', administrador: false, clienteId: 'c9'))?['direccion'],
      'Ruta 5 km 12',
    );
    expect(await consultarSaldoResumen(sinRed, 'c9'), isNull);
    expect(await consultarSaldoDetalle(sinRed, 'c9'), isNull);
    expect(await consultarPedidosConSaldo(sinRed, 'c9'), isEmpty);
    expect((await consultarTelefonoCliente(sinRed, 'c9'))?['preventista_id'], 'mary');
  });
}
