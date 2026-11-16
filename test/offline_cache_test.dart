import 'dart:convert';
import 'dart:io';

import 'package:distribuidora_alberdi/core/app_config.dart';
import 'package:distribuidora_alberdi/core/network_status.dart';
import 'package:distribuidora_alberdi/core/offline_cache.dart';
import 'package:distribuidora_alberdi/core/offline_queries.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'helpers/outbox_fixture.dart';

String token(String sub) {
  String part(Object v) => base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');
  return '${part({'alg': 'HS256'})}.${part({'sub': sub, 'exp': 4102444800})}.firma';
}

void main() {
  late Directory dir;
  late OfflineCache cache;
  setUp(() async {
    activateAppConfig(fixtureConfig());
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('cache-alberdi-');
    cache = await OfflineCache.open(dir.path);
    connectionProblem.value = false;
    showingCachedSince.value = null;
  });
  tearDown(() async {
    connectionProblem.value = false;
    showingCachedSince.value = null;
    await dir.delete(recursive: true);
  });

  test('la clave ordena los parámetros y separa usuarios y formatos', () {
    final a = Uri.parse('https://x.test/rest/v1/clientes?select=*&activo=eq.true&order=nombre');
    final b = Uri.parse('https://x.test/rest/v1/clientes?order=nombre&activo=eq.true&select=*');
    final h1 = {'Authorization': 'Bearer ${token('u1')}', 'Accept': 'application/json'};
    final h2 = {'Authorization': 'Bearer ${token('u2')}', 'Accept': 'application/json'};
    expect(cacheKey(a, h1), cacheKey(b, h1));
    expect(cacheKey(a, h1), isNot(cacheKey(a, h2)));
    expect(
      cacheKey(a, h1),
      isNot(cacheKey(a, {...h1, 'Accept': 'application/vnd.pgrst.object+json'})),
    );
    expect(isCacheableRequest('GET', a), isTrue);
    expect(isCacheableRequest('POST', a), isFalse);
    expect(isCacheableRequest('GET', Uri.parse('https://x.test/auth/v1/user')), isFalse);
    expect(isCacheableRequest('GET', Uri.parse('https://x.test/storage/v1/object/a.jpg')), isFalse);
  });

  test('sin señal devuelve lo guardado y avisa de cuándo es; sin respaldo falla', () async {
    var online = true;
    final inner = MockClient((request) async {
      if (!online) throw http.ClientException('sin red');
      return http.Response('[{"id":1}]', 200, headers: {'content-type': 'application/json'});
    });
    final client = ResilientHttpClient(inner, cache: () => cache);
    final url = Uri.parse('https://x.test/rest/v1/productos?select=id');
    final headers = {'Authorization': 'Bearer ${token('u1')}'};
    expect((await client.get(url, headers: headers)).body, '[{"id":1}]');
    online = false;
    final copia = await client.get(url, headers: headers);
    expect(copia.statusCode, 200);
    expect(copia.body, '[{"id":1}]');
    expect(connectionProblem.value, isTrue);
    expect(showingCachedSince.value, isNotNull);
    // Otro usuario no ve la copia de este.
    await expectLater(
      client.get(url, headers: {'Authorization': 'Bearer ${token('u2')}'}),
      throwsA(isA<http.ClientException>()),
    );
    // "Preparar" nunca toma lo guardado como si fuera nuevo.
    await expectLater(
      withoutCacheFallback(() => client.get(url, headers: headers)),
      throwsA(isA<http.ClientException>()),
    );
    // Al volver la señal, la franja se va.
    online = true;
    await client.get(url, headers: headers);
    expect(connectionProblem.value, isFalse);
    expect(showingCachedSince.value, isNull);
    // Al cerrar sesión se borra.
    await cache.clear();
    online = false;
    await expectLater(client.get(url, headers: headers), throwsA(isA<http.ClientException>()));
  });

  test('un error del servidor (no de conexión) no se tapa con la copia', () async {
    var status = 200;
    final client = ResilientHttpClient(
      MockClient((request) async => http.Response('[]', status)),
      cache: () => cache,
    );
    final url = Uri.parse('https://x.test/rest/v1/clientes?select=*');
    await client.get(url);
    status = 401;
    expect((await client.get(url)).statusCode, 401);
  });

  test('"Preparar" guarda lo que después usan las pantallas sin señal', () async {
    var online = true;
    final pedidas = <String>[];
    final http.Client red = MockClient((request) async {
      if (!online) throw http.ClientException('sin red');
      pedidas.add(request.url.pathSegments.last);
      final params = request.url.queryParameters;
      Object body;
      switch (request.url.pathSegments.last) {
        case 'usuarios':
          body = {'nombre': 'Mary', 'apellido': 'Ana', 'rol': 'preventista', 'activo': true};
        case 'clientes':
          body = params['id'] != null
              ? [
                  {'id': 'c1', 'nombre_comercio': 'Kiosco'},
                ]
              : [
                  {'id': 'c1', 'nombre_comercio': 'Kiosco'},
                  {'id': 'c2', 'nombre_comercio': 'Almacén'},
                ];
        case 'productos':
          body = [
            {'id': 'p1', 'nombre': 'Tutuca', 'precio_normal': 100},
          ];
        case 'saldos_pendientes_clientes':
          body = [
            {'saldo_pendiente': 250, 'cantidad_pedidos_con_saldo': 1},
          ];
        case 'saldos_pendientes_pedidos':
          body = [
            {'pedido_id': 'x', 'saldo_pendiente': 250},
          ];
        default:
          return http.Response('no', 404);
      }
      return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});
    });
    final client = SupabaseClient(
      fixtureUrl,
      'fixture-public-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: ResilientHttpClient(red, cache: () => cache),
    );
    addTearDown(client.dispose);
    await client.auth.setInitialSession(
      jsonEncode({
        'access_token': token('u-mary'),
        'refresh_token': 'r',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': {
          'id': 'u-mary',
          'aud': 'authenticated',
          'role': 'authenticated',
          'app_metadata': {},
          'user_metadata': {},
          'created_at': '2026-01-01T00:00:00Z',
        },
      }),
    );
    final hechos = <int>[];
    final r = await prepararSinConexion(client, progreso: (h, t) => hechos.add(h));
    expect(r.clientes, 2);
    expect(r.productos, 1);
    expect(hechos.last, 8); // 4 consultas por cliente
    expect((await leerPreparacion('u-mary'))!.clientes, 2);

    // Sin señal: las mismas consultas de las pantallas responden con lo guardado.
    online = false;
    expect((await consultarPerfilInicio(client, 'u-mary'))['nombre'], 'Mary');
    expect((await consultarRolActivo(client, 'u-mary'))['rol'], 'preventista');
    expect(await consultarClientesActivos(client, uid: 'u-mary', administrador: false), hasLength(2));
    expect(await consultarClientesParaPedido(client, uid: 'u-mary', administrador: false), hasLength(2));
    expect(await consultarProductosParaPedido(client), hasLength(1));
    expect(await consultarProductosCatalogo(client), hasLength(1));
    expect((await consultarSaldoResumen(client, 'c2'))!['saldo_pendiente'], 250);
    expect((await consultarSaldoDetalle(client, 'c1'))!['saldo_pendiente'], 250);
    expect(await consultarPedidosConSaldo(client, 'c2'), hasLength(1));
    expect(
      await consultarClienteParaPedido(client, uid: 'u-mary', administrador: false, clienteId: 'c1'),
      isNotNull,
    );
    expect(showingCachedSince.value, isNotNull);

    await borrarDatosSinConexion('u-mary');
    expect(await leerPreparacion('u-mary'), isNull);
  });
}
