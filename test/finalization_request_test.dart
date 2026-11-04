import 'package:distribuidora_alberdi/core/app_config.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:distribuidora_alberdi/features/orders/finalization_request.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('persistence rejects non-operational secrets and credentials', () async {
    final store = FinalizationRequestStore(
      await SharedPreferences.getInstance(),
      'testing',
      'admin',
    );
    await expectLater(
      store.prepare('order', {'token': 'fixture-never-save'}),
      throwsArgumentError,
    );
    expect(store.pendingOrderIds, isEmpty);
  });

  test(
    'lost response then restart reconciles committed result without repeating RPC',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final store = FinalizationRequestStore(prefs, 'testing', 'admin');
      final request = await store.prepare('order', {
        'p_originales': [
          {'detalle_id': 'detail', 'cantidad_entregada': 5},
        ],
        'p_agregados': [],
        'p_tipo_pago': 'completo',
        'p_importe_pago': 50,
      }, physicalDate: DateTime.utc(2026, 1));
      Map<String, dynamic>? committed;
      var effects = 0;
      final transport = MockClient((req) async {
        if (req.url.path.endsWith('consultar_finalizacion_solicitud')) {
          return http.Response(
            jsonEncode(
              committed == null
                  ? {'estado': 'inexistente'}
                  : {'estado': 'confirmada', 'resultado': committed},
            ),
            200,
            headers: {'content-type': 'application/json'},
            request: req,
          );
        }
        expect(jsonDecode(req.body), request);
        if (committed == null) {
          effects++;
          committed = {
            'resultado_entrega': 'entregado',
            'solicitud_id': request['p_solicitud_id'],
          };
        }
        throw http.ClientException('Simulated connection lost after commit');
      });
      final first = SupabaseClient(
        'https://blcgugdeluzxvpwqkhjq.supabase.co',
        'test-key',
        httpClient: transport,
      );
      try {
        await expectLater(
          _reconcile(first, request, retry: true),
          throwsA(isA<Object>()),
        );
        final restart = FinalizationRequestStore(prefs, 'testing', 'admin');
        final second = SupabaseClient(
          'https://blcgugdeluzxvpwqkhjq.supabase.co',
          'test-key',
          httpClient: transport,
        );
        try {
          final result = await _reconcile(
            second,
            restart.read('order')!,
            retry: true,
          );
          expect(result, committed);
          expect(effects, 1);
          expect(restart.read('order'), request);
          await restart.clear('order');
          expect(restart.read('order'), isNull);
        } finally {
          await second.dispose();
        }
      } finally {
        await first.dispose();
      }
    },
  );

  test('inexistent reconciliation retries exact durable parameters', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = FinalizationRequestStore(prefs, 'testing', 'admin');
    final request = await store.prepare('order', {'p_tipo_pago': 'sin_pago'});
    var writes = 0;
    final client = SupabaseClient(
      'https://blcgugdeluzxvpwqkhjq.supabase.co',
      'test-key',
      httpClient: MockClient((req) async {
        if (req.url.path.endsWith('consultar_finalizacion_solicitud')) {
          return http.Response(
            '{"estado":"inexistente"}',
            200,
            headers: {'content-type': 'application/json'},
            request: req,
          );
        }
        writes++;
        expect(jsonDecode(req.body), request);
        return http.Response(
          '{"resultado_entrega":"entregado"}',
          200,
          headers: {'content-type': 'application/json'},
          request: req,
        );
      }),
    );
    try {
      expect(await _reconcile(client, request), {'estado': 'inexistente'});
      expect(writes, 0);
      final restart = FinalizationRequestStore(prefs, 'testing', 'admin');
      expect(await _reconcile(client, restart.read('order')!, retry: true), {
        'resultado_entrega': 'entregado',
      });
      expect(writes, 1);
    } finally {
      await client.dispose();
    }
  });

  test(
    'restart recovers same UUID, physical date and immutable full request',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final store = FinalizationRequestStore(
        prefs,
        'https://blcgugdeluzxvpwqkhjq.supabase.co',
        'actor',
      );
      final input = <String, dynamic>{
        'p_originales': [
          {'detalle_id': 'detail', 'cantidad_entregada': 5},
        ],
        'p_agregados': [],
        'p_estado': 'en_reparto',
        'p_tipo_pago': 'completo',
        'p_importe_pago': 50,
        'p_medio_pago': 'Efectivo',
        'p_motivo_no_entrega': null,
      };
      final first = await store.prepare(
        'order',
        input,
        physicalDate: DateTime.utc(2026, 1),
      );
      expect(
        first['p_solicitud_id'],
        matches(
          RegExp(
            r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
          ),
        ),
      );
      input['p_importe_pago'] = 999;
      first['p_importe_pago'] = 999;
      final restarted = FinalizationRequestStore(
        prefs,
        'https://blcgugdeluzxvpwqkhjq.supabase.co',
        'actor',
      );
      final retry = await restarted.prepare('order', {
        'p_importe_pago': 999,
      }, physicalDate: DateTime.utc(2030));
      expect(retry, store.read('order'));
      expect(retry['p_importe_pago'], 50);
      expect(retry['p_fecha_fisica'], '2026-01-01T00:00:00.000Z');
      expect(restarted.pendingOrderIds, ['order']);
      await restarted.clear('order');
      expect(restarted.pendingOrderIds, isEmpty);
    },
  );

  test(
    'scope isolates projects and actors; corruption never generates another UUID',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final store = FinalizationRequestStore(prefs, 'testing', 'admin');
      await store.prepare('order', {});
      expect(
        FinalizationRequestStore(prefs, 'production', 'admin').read('order'),
        isNull,
      );
      expect(
        FinalizationRequestStore(prefs, 'testing', 'other').read('order'),
        isNull,
      );
      await prefs.setString('preventa_v1:testing:admin:order', '{broken');
      expect(() => store.read('order'), throwsFormatException);
      await expectLater(store.prepare('order', {}), throwsFormatException);
    },
  );

  for (final entry in {
    'stock_insuficiente': 'Stock insuficiente',
    'stock_no_inicializado': 'stock inicial',
    'solicitud_incompatible': 'otro contenido',
    'actualizacion_requerida': 'Actualizá',
    'operacion_ya_finalizada': 'ya fue finalizado',
  }.entries) {
    test('friendly mapping ${entry.key} without SQL details', () {
      final message = finalizationErrorMessage(
        PostgrestException(
          message: 'private_function_secret',
          code: 'PT409',
          details: {'codigo': entry.key},
        ),
      );
      expect(message, contains(entry.value));
      expect(message, isNot(contains('private_function_secret')));
    });
  }
}

Future<Map<String, dynamic>> _reconcile(
  SupabaseClient client,
  Map<String, dynamic> payload, {
  bool retry = false,
}) => reconcileFinalization(
  client,
  payload,
  retry: retry,
  config: AppConfig.resolve(
    environment: 'testing',
    testingUrl: 'https://blcgugdeluzxvpwqkhjq.supabase.co',
    testingKey: 'sb_publishable_local_fixture_123456789',
  ),
);
