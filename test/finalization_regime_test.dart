import 'dart:convert';
import 'package:distribuidora_alberdi/core/app_config.dart';
import 'package:distribuidora_alberdi/features/orders/finalization_request.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const url = 'https://blcgugdeluzxvpwqkhjq.supabase.co';
const epoch = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
Map<String, dynamic> input() => {
  'p_estado': 'pendiente',
  'p_originales': [],
  'p_agregados': [],
  'p_tipo_pago': 'sin_pago',
  'p_motivo_no_entrega': null,
  'p_importe_pago': null,
  'p_medio_pago': null,
};
Map<String, dynamic> context(String id) => {
  'solicitud_id': id,
  'pedido_id': 'order',
  'actor_id': 'actor',
  'regimen_id': epoch,
  'protocolo': 2,
  'fecha_fisica': '2020-01-01T00:00:00.123456Z',
};
AppConfig config() => AppConfig.resolve(
  environment: 'testing',
  testingUrl: url,
  testingKey: 'sb_publishable_fake_fixture_123456789',
);
http.Response reply(Object? v, [int code = 200]) => http.Response(
  jsonEncode(v),
  code,
  headers: {'content-type': 'application/json'},
  request: http.Request('POST', Uri.parse(url)),
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final field in [
    'solicitud_id',
    'pedido_id',
    'actor_id',
    'regimen_id',
    'protocolo',
    'fecha_fisica',
  ]) {
    test('invalid context $field cannot be persisted', () async {
      final db = LocalOutbox.memory();
      addTearDown(db.close);
      final store = FinalizationRequestStore(db, '$url/rest/v1', 'actor');
      await expectLater(
        store.prepare(
          'order',
          input(),
          serverContext: (id) async => {...context(id), field: 'invalid'},
        ),
        throwsA(isA<FinalizationClockException>()),
      );
      expect(store.read('order'), isNull);
    });
  }
  test(
    'context, date and UUID are durable before guarded V2 and survive retry',
    () async {
      final db = LocalOutbox.memory();
      addTearDown(db.close);
      final store = FinalizationRequestStore(db, '$url/rest/v1', 'actor');
      var preparations = 0, executions = 0;
      final sent = <dynamic>[];
      final client = SupabaseClient(
        url,
        'fake',
        httpClient: MockClient((req) async {
          final name = req.url.path.split('/').last,
              body = jsonDecode(req.body) as Map;
          if (name == 'preparar_finalizacion_contexto') {
            preparations++;
            expect(store.read('order'), isNull);
            return reply(context(body['p_solicitud_id']));
          }
          if (name == 'consultar_finalizacion_solicitud') {
            return reply({'estado': 'inexistente'});
          }
          expect(name, 'finalizar_gestion_pedido_contexto');
          expect(body, store.read('order'));
          sent.add(body);
          if (++executions == 1) throw http.ClientException('response lost');
          return reply({
            'pedido_id': 'order',
            'solicitud_id': body['p_solicitud_id'],
            'resultado_entrega': 'entregado',
          });
        }),
      );
      addTearDown(client.dispose);
      final p = await prepareCurrentFinalization(
        client,
        store,
        'order',
        input(),
        config: config(),
      );
      expect(p['p_regimen_id'], epoch);
      expect(p['p_protocolo'], 2);
      expect(p['p_fecha_fisica'], '2020-01-01T00:00:00.123456Z');
      await expectLater(
        reconcileFinalization(
          client,
          p,
          store: store,
          retry: true,
          config: config(),
        ),
        throwsA(isA<http.ClientException>()),
      );
      final reopened = FinalizationRequestStore(db, '$url/rest/v1', 'actor');
      expect(
        await prepareCurrentFinalization(client, reopened, 'order', {
          'p_estado': 'otro',
        }, config: config()),
        p,
      );
      await reconcileFinalization(
        client,
        p,
        store: reopened,
        retry: true,
        config: config(),
      );
      expect(preparations, 1);
      expect(sent, [p, p]);
    },
  );
  for (final code in [
    'regimen_incompatible',
    'contexto_regimen_requerido',
    'solicitud_incompatible',
    'stock_en_mantenimiento',
  ]) {
    test(
      '$code retains exact request; only definite conflicts enter review',
      () async {
        final db = LocalOutbox.memory();
        addTearDown(db.close);
        final store = FinalizationRequestStore(db, '$url/rest/v1', 'actor');
        final p = await store.prepare(
          'order',
          input(),
          serverContext: (id) async => context(id),
        );
        final client = SupabaseClient(
          url,
          'fake',
          httpClient: MockClient(
            (r) async => r.url.path.endsWith('consultar_finalizacion_solicitud')
                ? reply({'estado': 'inexistente'})
                : reply({'code': 'PT409', 'message': code}, 409),
          ),
        );
        addTearDown(client.dispose);
        await expectLater(
          reconcileFinalization(
            client,
            p,
            store: store,
            retry: true,
            config: config(),
          ),
          throwsA(isA<PostgrestException>()),
        );
        expect(store.read('order'), p);
        final row = db.read(store.key('order'))!;
        expect(row.result, isNull);
        expect(
          row.state,
          code == 'stock_en_mantenimiento' ? 'prepared' : 'review',
        );
      },
    );
  }
  test(
    'legacy local request is returned unchanged without acquiring context',
    () async {
      final db = LocalOutbox.memory();
      addTearDown(db.close);
      final store = FinalizationRequestStore(db, '$url/rest/v1', 'actor');
      final old = await store.prepare(
        'order',
        input(),
        physicalDate: DateTime.utc(2020),
      );
      final client = SupabaseClient(
        url,
        'fake',
        httpClient: MockClient(
          (r) async => throw StateError('No HTTP allowed'),
        ),
      );
      addTearDown(client.dispose);
      expect(
        await prepareCurrentFinalization(
          client,
          store,
          'order',
          input(),
          config: config(),
        ),
        old,
      );
      expect(old.containsKey('p_regimen_id'), false);
    },
  );
  test(
    'audit enumerates other actors and acknowledged receipts without mutations',
    () async {
      final db = LocalOutbox.memory();
      addTearDown(db.close);
      for (final actor in ['actor', 'other']) {
        final store = FinalizationRequestStore(db, '$url/rest/v1', actor);
        final saved = await store.prepare(
          actor,
          input(),
          physicalDate: DateTime.utc(2020),
        );
        if (actor == 'actor') {
          db.confirm(store.key(actor), saved, {
            'pedido_id': actor,
            'solicitud_id': saved['p_solicitud_id'],
            'resultado_entrega': 'entregado',
          });
          db.acknowledge(store.key(actor));
        }
      }
      final before = db.auditScope('$url/rest/v1');
      expect(before.map((r) => r['actor']), ['actor', 'other']);
      expect(before.first['state'], 'acknowledged');
      expect(before.first['result'], isNotNull);
      expect(db.auditScope('other-project'), isEmpty);
      expect(db.auditScope('$url/rest/v1'), before);
    },
  );
  test(
    'maintenance at preparation creates no SQLite operation and no V2 fallback',
    () async {
      final db = LocalOutbox.memory();
      addTearDown(db.close);
      final store = FinalizationRequestStore(db, '$url/rest/v1', 'actor');
      var count = 0;
      final client = SupabaseClient(
        url,
        'fake',
        httpClient: MockClient((r) async {
          count++;
          expect(r.url.path.endsWith('preparar_finalizacion_contexto'), true);
          return reply({
            'code': 'PT409',
            'message': 'stock_en_mantenimiento',
          }, 409);
        }),
      );
      addTearDown(client.dispose);
      await expectLater(
        prepareCurrentFinalization(
          client,
          store,
          'order',
          input(),
          config: config(),
        ),
        throwsA(isA<PostgrestException>()),
      );
      expect(count, 1);
      expect(store.pendingOrderIds, isEmpty);
    },
  );
}
