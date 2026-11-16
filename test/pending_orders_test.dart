import 'dart:async';
import 'dart:convert';

import 'package:distribuidora_alberdi/core/app_config.dart';
import 'package:distribuidora_alberdi/core/network_status.dart';
import 'package:distribuidora_alberdi/core/pending_orders.dart';
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

    online = true;
    connectionProblem.value = true;
    connectionProblem.value = false; // "volvió la conexión": envía solo
    await Future<void>.delayed(const Duration(milliseconds: 20));
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
}
