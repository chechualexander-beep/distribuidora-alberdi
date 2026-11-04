import 'dart:convert';

import 'package:distribuidora_alberdi/core/app_config.dart';
import 'package:distribuidora_alberdi/features/orders/finalization_request.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'helpers/outbox_fixture.dart' show memoryDatabase;
import 'package:supabase_flutter/supabase_flutter.dart';

const _url = 'https://blcgugdeluzxvpwqkhjq.supabase.co';
const _date = '2020-01-02T03:04:05.123456+00:00';

AppConfig _config() => AppConfig.resolve(
  environment: 'testing',
  testingUrl: _url,
  testingKey: 'sb_publishable_local_fixture_123456789',
);

http.Response _json(http.Request request, Object? value, [int status = 200]) =>
    http.Response(
      jsonEncode(value),
      status,
      headers: {'content-type': 'application/json'},
      request: request,
    );

Map<String, dynamic> _context(http.Request request) {
  final params = jsonDecode(request.body) as Map;
  return {
    'solicitud_id': params['p_solicitud_id'],
    'pedido_id': params['p_pedido_id'],
    'actor_id': 'admin',
    'regimen_id': 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
    'protocolo': 2,
    'fecha_fisica': _date,
  };
}

Map<String, dynamic> _input() => {
  'p_estado': 'pendiente',
  'p_originales': [
    {'detalle_id': 'fixture-detail', 'cantidad_entregada': 2},
  ],
  'p_agregados': [],
  'p_tipo_pago': 'completo',
  'p_importe_pago': 200,
  'p_medio_pago': 'Efectivo',
  'p_motivo_no_entrega': null,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'server instant and UUID are durable before V2; pendiente is preserved',
    () async {
      final preferences = memoryDatabase();
      final store = FinalizationRequestStore(
        preferences,
        '$_url/rest/v1',
        'admin',
      );
      final paths = <String>[];
      final client = SupabaseClient(
        _url,
        'fixture',
        httpClient: MockClient((req) async {
          paths.add(req.url.path.split('/').last);
          if (req.url.path.endsWith('preparar_finalizacion_contexto')) {
            expect(store.read('order'), isNull);
            return _json(req, _context(req));
          }
          final durable = FinalizationRequestStore(
            preferences,
            '$_url/rest/v1',
            'admin',
          ).read('order');
          expect(durable, isNotNull);
          expect(durable!['p_fecha_fisica'], '2020-01-02T03:04:05.123456Z');
          expect(durable['p_estado'], 'pendiente');
          expect(
            durable['p_solicitud_id'],
            matches(RegExp(r'^[a-f0-9-]{36}$')),
          );
          if (req.url.path.endsWith('consultar_finalizacion_solicitud')) {
            return _json(req, {'estado': 'inexistente'});
          }
          expect(jsonDecode(req.body), durable);
          return _json(req, {
            'pedido_id': 'order',
            'solicitud_id': store.read('order')!['p_solicitud_id'],
            'resultado_entrega': 'entregado',
            'movimientos_stock': 0,
          });
        }),
      );
      try {
        final request = await prepareCurrentFinalization(
          client,
          store,
          'order',
          _input(),
          config: _config(),
        );
        expect(paths, ['preparar_finalizacion_contexto']);
        expect(
          await reconcileFinalization(
            client,
            request,
            store: store,
            retry: true,
            config: _config(),
          ),
          {
            'pedido_id': 'order',
            'solicitud_id': store.read('order')!['p_solicitud_id'],
            'resultado_entrega': 'entregado',
            'movimientos_stock': 0,
          },
        );
        expect(paths, [
          'preparar_finalizacion_contexto',
          'consultar_finalizacion_solicitud',
          'finalizar_gestion_pedido_contexto',
        ]);
      } finally {
        await client.dispose();
      }
    },
  );

  test(
    'pending request survives restart and never acquires another date or UUID',
    () async {
      final prefs = memoryDatabase();
      final first = FinalizationRequestStore(prefs, '$_url/rest/v1', 'admin');
      final original = await first.prepare(
        'order',
        _input(),
        physicalDate: DateTime.utc(2099),
      );
      var calls = 0;
      final client = SupabaseClient(
        _url,
        'fixture',
        httpClient: MockClient((req) async {
          calls++;
          throw StateError(
            'Must not acquire a new timestamp or submit an operation',
          );
        }),
      );
      try {
        final restarted = FinalizationRequestStore(
          prefs,
          '$_url/rest/v1',
          'admin',
        );
        final recovered = await prepareCurrentFinalization(
          client,
          restarted,
          'order',
          {'p_importe_pago': 999},
          config: _config(),
        );
        expect(recovered, original);
        expect(calls, 0);
        expect(first.read('order'), original);
      } finally {
        await client.dispose();
      }
    },
  );

  test(
    'lost response after commit recovers without another clock call or write',
    () async {
      final prefs = memoryDatabase();
      final store = FinalizationRequestStore(prefs, '$_url/rest/v1', 'admin');
      var clockCalls = 0;
      var effects = 0;
      Map<String, dynamic>? committed;
      final client = SupabaseClient(
        _url,
        'fixture',
        httpClient: MockClient((req) async {
          if (req.url.path.endsWith('preparar_finalizacion_contexto')) {
            clockCalls++;
            return _json(req, _context(req));
          }
          if (req.url.path.endsWith('consultar_finalizacion_solicitud')) {
            return _json(
              req,
              committed == null
                  ? {'estado': 'inexistente'}
                  : {'estado': 'confirmada', 'resultado': committed},
            );
          }
          expect(jsonDecode(req.body), store.read('order'));
          if (committed != null) {
            return _json(req, committed);
          }
          effects++;
          committed = {
            'pedido_id': 'order',
            'solicitud_id': store.read('order')!['p_solicitud_id'],
            'resultado_entrega': 'entregado',
          };
          throw http.ClientException('Lost response after commit');
        }),
      );
      try {
        final request = await prepareCurrentFinalization(
          client,
          store,
          'order',
          _input(),
          config: _config(),
        );
        await expectLater(
          reconcileFinalization(
            client,
            request,
            store: store,
            retry: true,
            config: _config(),
          ),
          throwsA(isA<Exception>()),
        );
        final restarted = FinalizationRequestStore(
          prefs,
          '$_url/rest/v1',
          'admin',
        );
        final recovered = await prepareCurrentFinalization(
          client,
          restarted,
          'order',
          _input(),
          config: _config(),
        );
        expect(recovered, request);
        expect(
          await reconcileFinalization(
            client,
            recovered,
            store: store,
            retry: true,
            config: _config(),
          ),
          committed,
        );
        expect(clockCalls, 1);
        expect(effects, 1);
      } finally {
        await client.dispose();
      }
    },
  );

  test(
    'a failed V2 request retries the same persisted instant and complete payload',
    () async {
      final prefs = memoryDatabase();
      final store = FinalizationRequestStore(prefs, '$_url/rest/v1', 'admin');
      var clockCalls = 0;
      var writes = 0;
      final payloads = <Object?>[];
      final client = SupabaseClient(
        _url,
        'fixture',
        httpClient: MockClient((req) async {
          if (req.url.path.endsWith('preparar_finalizacion_contexto')) {
            clockCalls++;
            return _json(req, _context(req));
          }
          if (req.url.path.endsWith('consultar_finalizacion_solicitud')) {
            return _json(req, {'estado': 'inexistente'});
          }
          payloads.add(jsonDecode(req.body));
          if (++writes == 1) throw http.ClientException('Not committed');
          return _json(req, {
            'pedido_id': 'order',
            'solicitud_id': store.read('order')!['p_solicitud_id'],
            'resultado_entrega': 'entregado',
          });
        }),
      );
      try {
        final request = await prepareCurrentFinalization(
          client,
          store,
          'order',
          _input(),
          config: _config(),
        );
        await expectLater(
          reconcileFinalization(
            client,
            request,
            store: store,
            retry: true,
            config: _config(),
          ),
          throwsA(isA<Exception>()),
        );
        final restarted = FinalizationRequestStore(
          prefs,
          '$_url/rest/v1',
          'admin',
        );
        final retry = await prepareCurrentFinalization(
          client,
          restarted,
          'order',
          _input(),
          config: _config(),
        );
        await reconcileFinalization(
          client,
          retry,
          store: store,
          retry: true,
          config: _config(),
        );
        expect(payloads, [request, request]);
        expect(clockCalls, 1);
      } finally {
        await client.dispose();
      }
    },
  );

  for (final raw in [null, {}, 'infinity', '2020-01-02T03:04:05', 'invalidZ']) {
    test('invalid server clock $raw cannot persist or finalize', () async {
      final store = FinalizationRequestStore(
        memoryDatabase(),
        '$_url/rest/v1',
        'admin',
      );
      final paths = <String>[];
      final client = SupabaseClient(
        _url,
        'fixture',
        httpClient: MockClient((req) async {
          paths.add(req.url.path.split('/').last);
          return _json(req, raw);
        }),
      );
      try {
        await expectLater(
          prepareCurrentFinalization(
            client,
            store,
            'order',
            _input(),
            config: _config(),
          ),
          throwsA(isA<FinalizationClockException>()),
        );
        expect(store.pendingOrderIds, isEmpty);
        expect(paths, ['preparar_finalizacion_contexto']);
      } finally {
        await client.dispose();
      }
    });
  }

  for (final failWithPermission in [false, true]) {
    test(
      'clock ${failWithPermission ? 'permission' : 'network'} failure sends no V2',
      () async {
        final store = FinalizationRequestStore(
          memoryDatabase(),
          '$_url/rest/v1',
          'admin',
        );
        final paths = <String>[];
        final client = SupabaseClient(
          _url,
          'fixture',
          httpClient: MockClient((req) async {
            paths.add(req.url.path.split('/').last);
            if (failWithPermission) {
              return _json(req, {
                'code': '42501',
                'message': 'Solo administración activa',
              }, 403);
            }
            throw http.ClientException('Offline');
          }),
        );
        try {
          await expectLater(
            prepareCurrentFinalization(
              client,
              store,
              'order',
              _input(),
              config: _config(),
            ),
            throwsA(isA<FinalizationClockException>()),
          );
          expect(store.read('order'), isNull);
          expect(paths, ['preparar_finalizacion_contexto']);
        } finally {
          await client.dispose();
        }
      },
    );
  }

  test(
    'no device-clock fallback for new requests; explicit historical date remains supported',
    () async {
      final store = FinalizationRequestStore(
        memoryDatabase(),
        '$_url/rest/v1',
        'admin',
      );
      await expectLater(store.prepare('order', _input()), throwsStateError);
      expect(store.pendingOrderIds, isEmpty);
      final historical = DateTime.utc(2020);
      expect(
        (await store.prepare(
          'order',
          _input(),
          physicalDate: historical,
        ))['p_fecha_fisica'],
        historical.toIso8601String(),
      );
    },
  );

  test(
    'production client or configuration cannot use the new clock flow',
    () async {
      final store = FinalizationRequestStore(
        memoryDatabase(),
        '$_url/rest/v1',
        'admin',
      );
      var calls = 0;
      final productionClient = SupabaseClient(
        'https://vmbncsqapqdyffscwfwo.supabase.co',
        'fixture',
        httpClient: MockClient((req) async {
          calls++;
          return _json(req, _context(req));
        }),
      );
      final testingClient = SupabaseClient(
        _url,
        'fixture',
        httpClient: MockClient((req) async {
          calls++;
          return _json(req, _context(req));
        }),
      );
      try {
        await expectLater(
          prepareCurrentFinalization(
            productionClient,
            store,
            'order',
            _input(),
            config: _config(),
          ),
          throwsStateError,
        );
        await expectLater(
          prepareCurrentFinalization(
            testingClient,
            store,
            'order',
            _input(),
            config: AppConfig.resolve(
              productionKey: 'sb_publishable_local_fixture_123456789',
            ),
          ),
          throwsStateError,
        );
        expect(calls, 0);
        expect(
          AppConfig.resolve(
            productionKey: 'sb_publishable_local_fixture_123456789',
          ).usesV2For('pedido'),
          isFalse,
        );
        expect(_config().usesV2For('pedido'), isTrue);
        expect(_config().usesV2For('venta_directa'), isFalse);
      } finally {
        await productionClient.dispose();
        await testingClient.dispose();
      }
    },
  );

  test(
    'date errors have a specific safe message without changing the pending payload',
    () async {
      final store = FinalizationRequestStore(
        memoryDatabase(),
        '$_url/rest/v1',
        'admin',
      );
      final original = await store.prepare(
        'order',
        _input(),
        physicalDate: DateTime.utc(2099),
      );
      const error = PostgrestException(
        message: 'Fecha o solicitud inválida',
        code: 'PT422',
      );
      expect(isFinalizationDateError(error), isTrue);
      expect(finalizationErrorMessage(error), contains('se conserva'));
      expect(finalizationErrorMessage(error), contains('fecha'));
      expect(store.read('order'), original);
      expect(
        isFinalizationDateError(
          const PostgrestException(
            message: 'Cambió el saldo a cobrar',
            code: 'PT422',
          ),
        ),
        isFalse,
      );
    },
  );
}
