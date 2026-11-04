import 'dart:async';
import 'dart:convert';
import 'package:distribuidora_alberdi/features/orders/finalization_request.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'helpers/outbox_fixture.dart';

void main() {
  test('rejects secrets before persistence', () async {
    final store = memoryStore();
    await expectLater(
      store.prepare('fake', {'token': 'never-save'}),
      throwsArgumentError,
    );
    expect(store.pendingOrderIds, isEmpty);
  });
  test(
    'frozen snapshot survives caller mutations and later preparations',
    () async {
      final store = memoryStore();
      final gate = Completer<DateTime>();
      final input = operational();
      final pending = store.prepare(
        'fake',
        input,
        serverClock: () => gate.future,
      );
      input['p_originales'][0]['cantidad_entregada'] = 999;
      gate.complete(DateTime.utc(2026));
      final payload = await pending;
      payload['p_importe_pago'] = 999;
      final again = await store.prepare(
        'fake',
        operational(amount: 999),
        physicalDate: DateTime.utc(2030),
      );
      expect(again['p_originales'][0]['cantidad_entregada'], 2);
      expect(again['p_importe_pago'], 200);
      expect(again['p_fecha_fisica'], '2026-01-01T00:00:00.000Z');
    },
  );
  test('concurrent preparations acquire one UUID and clock', () async {
    final store = memoryStore();
    final gate = Completer<DateTime>();
    var clocks = 0;
    Future<DateTime> clock() {
      clocks++;
      return gate.future;
    }

    final a = store.prepare('fake', operational(), serverClock: clock);
    final b = store.prepare(
      'fake',
      operational(amount: 999),
      serverClock: clock,
    );
    await Future<void>.delayed(Duration.zero);
    gate.complete(DateTime.utc(2026));
    final results = await Future.wait([a, b]);
    expect(results[0], results[1]);
    expect(clocks, 1);
  });
  test(
    'lost commit response recovers once, preserving payload and receipt',
    () async {
      final store = memoryStore();
      final payload = await store.prepare(
        'fake',
        operational(),
        physicalDate: DateTime.utc(2026),
      );
      Map<String, dynamic>? confirmed;
      var writes = 0;
      final client = mockClient((request) async {
        if (request.url.path.endsWith('consultar_finalizacion_solicitud')) {
          return jsonResponse(
            request,
            confirmed == null
                ? {'estado': 'inexistente'}
                : {'estado': 'confirmada', 'resultado': confirmed},
          );
        }
        expect(jsonDecode(request.body), payload);
        if (confirmed != null) return jsonResponse(request, confirmed);
        writes++;
        confirmed = receipt(payload);
        throw http.ClientException('Injected lost response after commit');
      });
      await expectLater(
        reconcile(client, store, payload),
        throwsA(isA<Exception>()),
      );
      final restarted = FinalizationRequestStore(
        store.database,
        fixtureScope,
        'admin',
      );
      expect(
        await reconcile(client, restarted, restarted.read('fake')!),
        confirmed,
      );
      await restarted.acknowledge('fake');
      expect(restarted.pendingOrderIds, isEmpty);
      expect(await reconcile(client, restarted, payload), confirmed);
      expect(writes, 1);
      expect(
        await restarted.prepare('fake', {}, physicalDate: DateTime.utc(2030)),
        payload,
      );
    },
  );
  test('unsaved or changed payload cannot reach any RPC', () async {
    final store = memoryStore();
    var calls = 0;
    final client = mockClient((r) async {
      calls++;
      throw StateError('Forbidden');
    });
    await expectLater(
      reconcile(client, store, {'p_pedido_id': 'fake'}),
      throwsA(isA<LocalOutboxException>()),
    );
    final payload = await store.prepare(
      'fake',
      operational(),
      physicalDate: DateTime.utc(2026),
    );
    await expectLater(
      reconcile(client, store, {...payload, 'p_importe_pago': 999}),
      throwsA(isA<LocalOutboxException>()),
    );
    expect(calls, 0);
  });
  test('concurrent dispatches serialize and reuse confirmed result', () async {
    final store = memoryStore();
    final payload = await store.prepare(
      'fake',
      operational(),
      physicalDate: DateTime.utc(2026),
    );
    var writes = 0, queries = 0;
    final client = mockClient((r) async {
      if (r.url.path.endsWith('consultar_finalizacion_solicitud')) {
        queries++;
        return jsonResponse(r, {'estado': 'inexistente'});
      }
      writes++;
      await Future<void>.delayed(Duration.zero);
      return jsonResponse(r, receipt(payload));
    });
    final results = await Future.wait([
      reconcile(client, store, payload),
      reconcile(client, store, payload),
    ]);
    expect(results[0], results[1]);
    expect(writes, 1);
    expect(queries, 1);
  });
  test(
    'query only never dispatches; unknown status blocks; no legacy fallback',
    () async {
      final store = memoryStore();
      final payload = await store.prepare(
        'fake',
        operational(),
        physicalDate: DateTime.utc(2026),
      );
      var status = 'inexistente';
      var calls = 0;
      final client = mockClient((r) async {
        calls++;
        expect(r.url.path, endsWith('consultar_finalizacion_solicitud'));
        return jsonResponse(r, {'estado': status});
      });
      expect(await reconcile(client, store, payload, retry: false), {
        'estado': 'inexistente',
      });
      status = 'desconocido';
      await expectLater(
        reconcile(client, store, payload),
        throwsA(isA<LocalOutboxException>()),
      );
      expect(calls, 2);
    },
  );
  test(
    'confirmation with another identity is rejected and request retained',
    () async {
      final store = memoryStore();
      final payload = await store.prepare(
        'fake',
        operational(),
        physicalDate: DateTime.utc(2026),
      );
      final client = mockClient(
        (r) async => jsonResponse(
          r,
          r.url.path.endsWith('consultar_finalizacion_solicitud')
              ? {'estado': 'confirmada'}
              : {...receipt(payload), 'pedido_id': 'another'},
        ),
      );
      await expectLater(
        reconcile(client, store, payload),
        throwsA(isA<LocalOutboxException>()),
      );
      expect(store.database.read(store.key('fake'))!.state, 'prepared');
    },
  );
  test(
    'confirmation persistence failure recovers server result without second write',
    () async {
      var fail = false;
      final db = memoryDatabase(
        fault: (s) {
          if (fail && s == 'before_commit') throw StateError('Injected');
        },
      );
      final store = FinalizationRequestStore(db, fixtureScope, 'admin');
      final payload = await store.prepare(
        'fake',
        operational(),
        physicalDate: DateTime.utc(2026),
      );
      Map<String, dynamic>? confirmed;
      var writes = 0;
      final client = mockClient((r) async {
        if (r.url.path.endsWith('consultar_finalizacion_solicitud')) {
          return jsonResponse(
            r,
            confirmed == null
                ? {'estado': 'inexistente'}
                : {'estado': 'confirmada', 'resultado': confirmed},
          );
        }
        if (confirmed == null) {
          writes++;
          confirmed = receipt(payload);
        }
        return jsonResponse(r, confirmed);
      });
      fail = true;
      await expectLater(
        reconcile(client, store, payload),
        throwsA(isA<LocalOutboxException>()),
      );
      fail = false;
      expect(await reconcile(client, store, payload), confirmed);
      expect(writes, 1);
    },
  );
  test('review blocks resend without deleting identity or payload', () async {
    final store = memoryStore();
    final payload = await store.prepare(
      'fake',
      operational(),
      physicalDate: DateTime.utc(2026),
    );
    store.markForReview('fake', 'PT422');
    final client = mockClient((r) async => throw StateError('Forbidden'));
    await expectLater(
      reconcile(client, store, payload),
      throwsA(isA<LocalOutboxException>()),
    );
    expect(store.read('fake'), payload);
  });
  for (final entry in {
    'stock_insuficiente': 'Stock insuficiente',
    'stock_no_inicializado': 'stock inicial',
    'solicitud_incompatible': 'otro contenido',
    'actualizacion_requerida': 'Actualizá',
    'operacion_ya_finalizada': 'ya fue finalizado',
  }.entries) {
    test('safe error ${entry.key}', () {
      final message = finalizationErrorMessage(
        PostgrestException(
          message: 'private_secret',
          code: 'PT409',
          details: {'codigo': entry.key},
        ),
      );
      expect(message, contains(entry.value));
      expect(message, isNot(contains('private_secret')));
    });
  }
  for (final scenario in [
    ('full', 2, 200, 'entregado', <Map<String, dynamic>>[]),
    ('partial', 1, 100, 'parcial', <Map<String, dynamic>>[]),
    ('none', 0, 0, 'no_entregado', <Map<String, dynamic>>[]),
    (
      'substitution',
      0,
      3000,
      'parcial',
      [
        {
          'producto_id': 'fake-A',
          'cantidad_entregada': 2,
          'tipo_precio': 'normal',
        },
      ],
    ),
    (
      'addition',
      2,
      1000,
      'entregado',
      [
        {
          'producto_id': 'fake-C',
          'cantidad_entregada': 1,
          'tipo_precio': 'normal',
        },
      ],
    ),
  ]) {
    test(
      'storage preserves commercial payload ${scenario.$1} with operational pendiente',
      () async {
        final store = memoryStore();
        final input = operational(
          quantity: scenario.$2,
          amount: scenario.$3,
          additions: scenario.$5,
        );
        final payload = await store.prepare(
          'fake-${scenario.$1}',
          input,
          physicalDate: DateTime.utc(2026),
        );
        final client = mockClient((r) async {
          if (r.url.path.endsWith('consultar_finalizacion_solicitud')) {
            return jsonResponse(r, {'estado': 'inexistente'});
          }
          expect(jsonDecode(r.body), payload);
          expect(store.read('fake-${scenario.$1}'), payload);
          return jsonResponse(r, receipt(payload, outcome: scenario.$4));
        });
        final result = await reconcile(client, store, payload);
        expect(result['resultado_entrega'], scenario.$4);
        expect(payload['p_estado'], 'pendiente');
        expect(payload['p_originales'], input['p_originales']);
        expect(payload['p_agregados'], input['p_agregados']);
        expect(payload['p_importe_pago'], scenario.$3);
      },
    );
  }
  test(
    'legacy SQL result contract without optional IDs remains accepted',
    () async {
      final store = memoryStore();
      final payload = await store.prepare(
        'fake',
        operational(),
        physicalDate: DateTime.utc(2026),
      );
      final client = mockClient(
        (r) async => jsonResponse(
          r,
          r.url.path.endsWith('consultar_finalizacion_solicitud')
              ? {'estado': 'confirmada'}
              : {'resultado_entrega': 'entregado'},
        ),
      );
      expect(await reconcile(client, store, payload), {
        'resultado_entrega': 'entregado',
      });
    },
  );
}
