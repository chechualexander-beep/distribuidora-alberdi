import 'dart:async';
import 'dart:convert';
import 'package:distribuidora_alberdi/features/orders/finalization_request.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'helpers/outbox_fixture.dart';

void main() {
  test(
    'confirmed lookup validates exact durable payload even without retry authorization',
    () async {
      final store = memoryStore();
      final payload = await store.prepare(
        'fake',
        operational(),
        physicalDate: DateTime.utc(2026),
      );
      final result = receipt(payload);
      final paths = <String>[];
      final client = mockClient((request) async {
        paths.add(request.url.path.split('/').last);
        expect(store.database.read(store.key('fake'))!.result, isNull);
        if (request.url.path.endsWith('consultar_finalizacion_solicitud')) {
          return jsonResponse(request, {
            'estado': 'confirmada',
            'resultado': {'untrusted': 'lookup is not content verification'},
          });
        }
        expect(jsonDecode(request.body), store.read('fake'));
        expect(jsonDecode(request.body), payload);
        return jsonResponse(request, result);
      });
      expect(await reconcile(client, store, payload, retry: false), result);
      expect(paths, [
        'consultar_finalizacion_solicitud',
        'finalizar_gestion_pedido_v2',
      ]);
      expect(store.database.read(store.key('fake'))!.result, result);
    },
  );
  final changes = <String, Map<String, dynamic> Function(Map<String, dynamic>)>{
    'amount': (p) => {...p, 'p_importe_pago': 999},
    'quantities': (p) => {
      ...p,
      'p_originales': [
        {'detalle_id': 'fake-detail', 'cantidad_entregada': 1},
      ],
    },
    'added products': (p) => {
      ...p,
      'p_agregados': [
        {
          'producto_id': 'fake-C',
          'cantidad_entregada': 1,
          'tipo_precio': 'normal',
        },
      ],
    },
    'payment method': (p) => {...p, 'p_medio_pago': 'Transferencia'},
    'payment type': (p) => {
      ...p,
      'p_tipo_pago': 'parcial',
      'p_importe_pago': 100,
    },
    'physical date': (p) => {
      ...p,
      'p_fecha_fisica': '2025-12-31T23:59:59.000Z',
    },
  };
  for (final entry in changes.entries) {
    test(
      'incompatible migrated ${entry.key} is preserved in review, never confirmed',
      () async {
        final source = memoryStore();
        final original = await source.prepare(
          'fake',
          operational(),
          physicalDate: DateTime.utc(2026),
        );
        final payload = entry.value(original);
        final store = memoryStore();
        store.importLegacyValues({
          'preventa_v1:${Uri.encodeComponent(fixtureScope)}:admin:fake':
              jsonEncode(payload),
        });
        var calls = 0;
        final client = mockClient((request) async {
          calls++;
          if (request.url.path.endsWith('consultar_finalizacion_solicitud')) {
            return jsonResponse(request, {
              'estado': 'confirmada',
              'resultado': receipt(original),
            });
          }
          expect(jsonDecode(request.body), payload);
          return jsonResponse(request, {
            'code': 'PT409',
            'message': 'solicitud_incompatible',
            'details': null,
            'hint': null,
          }, 409);
        });
        await expectLater(
          reconcile(client, store, payload),
          throwsA(
            isA<PostgrestException>().having(
              (e) => e.code,
              'SQLSTATE',
              'PT409',
            ),
          ),
        );
        final saved = store.database.read(store.key('fake'))!;
        expect(saved.state, 'review');
        expect(saved.result, isNull);
        expect(saved.payload, payload);
        expect(store.pendingOrderIds, ['fake']);
        expect(
          await store.prepare(
            'fake',
            operational(amount: 500),
            physicalDate: DateTime.utc(2030),
          ),
          payload,
        );
        await expectLater(
          reconcile(client, store, payload),
          throwsA(isA<LocalOutboxException>()),
        );
        expect(calls, 2);
        final message = finalizationErrorMessage(
          const PostgrestException(
            code: 'PT409',
            message: 'solicitud_incompatible',
          ),
        );
        expect(message, contains('sin confirmar'));
        expect(message, contains('revisión'));
      },
    );
  }
  for (final fault in ['network', 'ambiguous result']) {
    test(
      'verification $fault failure never accepts lookup result and remains recoverable',
      () async {
        final store = memoryStore();
        final payload = await store.prepare(
          'fake',
          operational(),
          physicalDate: DateTime.utc(2026),
        );
        var attempts = 0;
        final submitted = <Object?>[];
        final client = mockClient((request) async {
          if (request.url.path.endsWith('consultar_finalizacion_solicitud')) {
            return jsonResponse(request, {
              'estado': 'confirmada',
              'resultado': receipt(payload),
            });
          }
          submitted.add(jsonDecode(request.body));
          attempts++;
          if (attempts == 1) {
            if (fault == 'network') {
              throw http.ClientException('Injected verification response loss');
            }
            return jsonResponse(request, {'unexpected': 'ambiguous'});
          }
          return jsonResponse(request, receipt(payload));
        });
        await expectLater(
          reconcile(client, store, payload),
          throwsA(isA<Exception>()),
        );
        expect(store.database.read(store.key('fake'))!.state, 'prepared');
        expect(store.database.read(store.key('fake'))!.result, isNull);
        expect(store.read('fake'), payload);
        expect(await reconcile(client, store, payload), receipt(payload));
        expect(submitted, [payload, payload]);
      },
    );
  }
  test(
    'failure recording review cannot confirm or hide the conflict',
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
        operational(amount: 999),
        physicalDate: DateTime.utc(2026),
      );
      final client = mockClient((request) async {
        if (request.url.path.endsWith('consultar_finalizacion_solicitud')) {
          return jsonResponse(request, {'estado': 'confirmada'});
        }
        return jsonResponse(request, {
          'code': 'PT409',
          'message': 'solicitud_incompatible',
        }, 409);
      });
      fail = true;
      await expectLater(
        reconcile(client, store, payload),
        throwsA(
          isA<LocalOutboxException>().having(
            (e) => e.message,
            'message',
            contains('requiere revisión'),
          ),
        ),
      );
      expect(store.read('fake'), payload);
      expect(db.read(store.key('fake'))!.state, 'prepared');
      expect(db.read(store.key('fake'))!.result, isNull);
    },
  );
  test(
    'concurrent recoveries hold the lock through V2 validation and persist once',
    () async {
      final store = memoryStore();
      final payload = await store.prepare(
        'fake',
        operational(),
        physicalDate: DateTime.utc(2026),
      );
      final gate = Completer<void>();
      var calls = 0;
      final client = mockClient((request) async {
        calls++;
        if (request.url.path.endsWith('consultar_finalizacion_solicitud')) {
          return jsonResponse(request, {'estado': 'confirmada'});
        }
        expect(store.database.read(store.key('fake'))!.result, isNull);
        await gate.future;
        return jsonResponse(request, receipt(payload));
      });
      final a = reconcile(client, store, payload);
      final b = reconcile(client, store, payload);
      await Future<void>.delayed(Duration.zero);
      gate.complete();
      final results = await Future.wait([a, b]);
      expect(results, [receipt(payload), receipt(payload)]);
      expect(calls, 2);
    },
  );
}
