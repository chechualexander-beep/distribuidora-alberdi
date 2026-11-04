import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:distribuidora_alberdi/features/invoicing/invoice_request.dart';
import 'package:distribuidora_alberdi/features/invoicing/invoice_snapshot_pdf.dart';
import 'package:distribuidora_alberdi/features/orders/finalization_request.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'helpers/outbox_fixture.dart';

const regime = '11111111-1111-4111-8111-111111111111';
Map<String, dynamic> input({num quantity = 1}) => {
  'p_originales': [
    {'detalle_id': 'detail', 'cantidad_facturada': quantity},
  ],
  'p_agregados': [],
};
Map<String, dynamic> copy(Map<String, dynamic> v) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(v)) as Map);

class FakeInvoices {
  Map<String, dynamic>? payload, document;
  int emissions = 0, documents = 0;
  bool loseResponse = false;
  final names = <String>[];
  void Function()? beforeEmission;
  Future<dynamic> call(String name, Map<String, dynamic> p) async {
    names.add(name);
    switch (name) {
      case 'stock_estado_transicion':
        return {
          'transicion': {
            'mantenimiento': false,
            'paso_instalacion': 3,
            'regimen_id': regime,
          },
          'regimen': {'id': regime, 'protocolo': 2, 'cerrado_at': null},
        };
      case 'consultar_boleta_interna':
        return document == null ||
                document!['resultado']['solicitud_id'] != p['p_solicitud_id']
            ? {'estado': 'inexistente'}
            : copy(document!);
      case 'consultar_comprobante_pedido':
        return document == null ||
                document!['resultado']['pedido_id'] != p['p_pedido_id']
            ? {'estado': 'sin_comprobante_nuevo'}
            : copy(document!);
      case 'emitir_boleta_preventa':
        beforeEmission?.call();
        emissions++;
        if (payload != null && jsonEncode(payload) != jsonEncode(p)) {
          throw const PostgrestException(
            message: 'solicitud_incompatible',
            code: 'PT409',
          );
        }
        if (document == null) {
          documents++;
          payload = copy(p);
          final q =
              (p['p_originales'] as List).first['cantidad_facturada'] as num;
          final result = {
            'version': 1,
            'comprobante_id': 'doc',
            'solicitud_id': p['p_solicitud_id'],
            'pedido_id': p['p_pedido_id'],
            'numero': '9',
            'fecha_emision': '2026-10-29T03:03:12Z',
            'total': q * 100,
            'captura_hash': List.filled(64, 'a').join(),
          };
          document = {
            'estado': 'confirmada',
            'actor_id': 'admin',
            'resultado': result,
            'captura': {
              'version': 1,
              'numero': '9',
              'pedido_id': p['p_pedido_id'],
              'fecha_emision': result['fecha_emision'],
              'naturaleza': 'boleta_interna_no_fiscal',
              'tipo': 'boleta_preventa',
              'moneda': 'ARS',
              'cliente': {'nombre': 'CLIENTE CAPTURADO', 'direccion': 'LOCAL'},
              'actor': {'id': 'admin'},
              'total': q * 100,
              'lineas': [
                {
                  'nombre': 'NOMBRE CAPTURADO',
                  'cantidad_documentada': q,
                  'precio_unitario': 100,
                  'subtotal': q * 100,
                },
              ],
            },
          };
        }
        if (loseResponse) {
          loseResponse = false;
          throw TimeoutException('simulated lost response after commit');
        }
        return copy(Map<String, dynamic>.from(document!['resultado'] as Map));
      default:
        throw StateError('Unexpected RPC, no legacy allowed: $name');
    }
  }
}

InvoiceService service(
  LocalOutbox db,
  FakeInvoices server, {
  bool enabled = true,
  void Function()? scope,
}) => InvoiceService(
  InvoiceStore(db, fixtureScope, 'admin'),
  server.call,
  enabled: enabled,
  requireScope: scope ?? () {},
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'legacy mode cannot bypass an existing pending invoice across actors',
    () async {
      final db = memoryDatabase(), server = FakeInvoices();
      final s = service(db, server);
      await s.prepare('order', input());
      var legacy = 0;
      await expectLater(
        service(db, server, enabled: false).runLegacyIfClear('order', () async {
          legacy++;
        }),
        throwsA(isA<LocalOutboxException>()),
      );
      final other = InvoiceService(
        InvoiceStore(db, fixtureScope, 'other-admin'),
        server.call,
        enabled: false,
        requireScope: () {},
      );
      await expectLater(
        other.runLegacyIfClear('order', () async {
          legacy++;
        }),
        throwsA(isA<LocalOutboxException>()),
      );
      expect(legacy, 0);
    },
  );
  test(
    'legacy mode available only with no new request or server document',
    () async {
      final db = memoryDatabase(),
          server = FakeInvoices(),
          s = service(db, server, enabled: false);
      var legacy = 0;
      await s.runLegacyIfClear('old', () async {
        legacy++;
      });
      expect(legacy, 1);
      final newMode = service(db, server);
      final p = await newMode.prepare('different', input());
      await server.call('emitir_boleta_preventa', p);
      final remoteOnly = service(memoryDatabase(), server, enabled: false);
      await expectLater(
        remoteOnly.runLegacyIfClear('different', () async {
          legacy++;
        }),
        throwsA(isA<LocalOutboxException>()),
      );
      expect(legacy, 1);
    },
  );
  test(
    'after-commit storage fault retains UUID for next preparation',
    () async {
      var fail = true;
      final db = memoryDatabase(
        fault: (stage) {
          if (fail && stage == 'after_commit') {
            throw StateError('local acknowledgment lost');
          }
        },
      );
      final server = FakeInvoices(), s = service(db, server);
      await expectLater(
        s.prepare('order', input()),
        throwsA(isA<LocalOutboxException>()),
      );
      fail = false;
      final saved = s.store.read('order')!.payload;
      expect(await s.prepare('order', input(quantity: 999)), saved);
      expect(server.emissions, 0);
    },
  );
  test('new circuit disabled by default in TESTING', () {
    expect(transactionalInvoicesEnabled(fixtureConfig()), isFalse);
  });
  test('confirmed only after persistence, one document', () async {
    final db = memoryDatabase(),
        server = FakeInvoices(),
        s = service(db, server);
    final p = await s.prepare('order', input());
    server.beforeEmission = () => db.requirePersisted(s.store.key('order'), p);
    final doc = await s.reconcile('order', sendIfAbsent: true);
    expect(doc!.number, '9');
    expect(server.documents, 1);
    expect(s.store.read('order')!.state, 'confirmed');
  });
  test(
    'response lost after commit recovered with exact UUID and content',
    () async {
      final db = memoryDatabase(),
          server = FakeInvoices()..loseResponse = true,
          s = service(db, server);
      final p = await s.prepare('order', input());
      await expectLater(
        s.reconcile('order', sendIfAbsent: true),
        throwsA(isA<TimeoutException>()),
      );
      expect(s.store.read('order')!.result, isNull);
      final doc = await s.reconcile('order');
      expect(doc!.result['solicitud_id'], p['p_solicitud_id']);
      expect(server.documents, 1);
      expect(server.emissions, 2);
    },
  );
  test('existing pending payload wins over edited form', () async {
    final db = memoryDatabase(),
        server = FakeInvoices(),
        s = service(db, server);
    final initial = input();
    final pending = s.prepare('order', initial);
    initial['p_originales'][0]['cantidad_facturada'] = 999;
    final a = await pending, b = await s.prepare('order', input(quantity: 777));
    expect(a, b);
    expect(b['p_originales'][0]['cantidad_facturada'], 1);
  });
  test('concurrent preparations one UUID and one regime read', () async {
    final db = memoryDatabase(),
        server = FakeInvoices(),
        s = service(db, server);
    final results = await Future.wait([
      s.prepare('order', input()),
      s.prepare('order', input(quantity: 2)),
    ]);
    expect(results[0], results[1]);
    expect(server.names.where((n) => n == 'stock_estado_transicion').length, 1);
  });
  test('same UUID incompatible payload never confirms locally', () async {
    final db = memoryDatabase(),
        server = FakeInvoices(),
        s = service(db, server);
    final p = await s.prepare('order', input(quantity: 999));
    await server.call('emitir_boleta_preventa', {
      ...p,
      'p_originales': input(quantity: 2)['p_originales'],
    });
    await expectLater(s.reconcile('order'), throwsA(isA<PostgrestException>()));
    expect(s.store.read('order')!.state, 'review');
    expect(s.store.read('order')!.result, isNull);
    expect(server.documents, 1);
    expect(s.store.read('order')!.payload, p);
  });
  test('unknown result stays pending and no automatic emission', () async {
    final db = memoryDatabase(),
        server = FakeInvoices(),
        s = service(db, server);
    await s.prepare('order', input());
    expect(await s.reconcile('order'), isNull);
    expect(server.emissions, 0);
  });
  test('confirmed receipt can recover with client switch off', () async {
    final db = memoryDatabase(),
        server = FakeInvoices(),
        s = service(db, server);
    final p = await s.prepare('order', input());
    await server.call('emitir_boleta_preventa', p);
    expect(
      await service(db, server, enabled: false).reconcile('order'),
      isNotNull,
    );
    expect(server.documents, 1);
  });
  test('switch off blocks absent request, without legacy fallback', () async {
    final db = memoryDatabase(),
        server = FakeInvoices(),
        s = service(db, server);
    await s.prepare('order', input());
    await expectLater(
      service(
        db,
        server,
        enabled: false,
      ).reconcile('order', sendIfAbsent: true),
      throwsA(isA<LocalOutboxException>()),
    );
    expect(server.emissions, 0);
  });
  test(
    'write failure blocks send and after-commit uncertainty keeps UUID',
    () async {
      var fail = true;
      final db = memoryDatabase(
        fault: (_) {
          if (fail) throw StateError('simulated disk');
        },
      );
      final server = FakeInvoices(), s = service(db, server);
      await expectLater(
        s.prepare('order', input()),
        throwsA(isA<LocalOutboxException>()),
      );
      expect(server.emissions, 0);
      fail = false;
      expect(s.store.read('order'), isNull);
    },
  );
  test(
    'confirmation storage failure recovers original server result',
    () async {
      var fail = false;
      final db = memoryDatabase(
        fault: (_) {
          if (fail) throw StateError('simulated disk');
        },
      );
      final server = FakeInvoices(), s = service(db, server);
      await s.prepare('order', input());
      fail = true;
      await expectLater(
        s.reconcile('order', sendIfAbsent: true),
        throwsA(isA<LocalOutboxException>()),
      );
      fail = false;
      expect(await s.reconcile('order'), isNotNull);
      expect(server.documents, 1);
    },
  );
  test('print failure after confirm and reprint never emit again', () async {
    final db = memoryDatabase(),
        server = FakeInvoices(),
        s = service(db, server);
    await s.prepare('order', input());
    await s.reconcile('order', sendIfAbsent: true);
    await expectLater(
      s.printConfirmed('order', (_) async => throw StateError('printer')),
      throwsStateError,
    );
    expect(s.store.read('order')!.state, 'confirmed');
    expect(await s.printConfirmed('order', (_) async => false), isFalse);
    expect(s.store.pending, ['order']);
    expect(await s.printConfirmed('order', (_) async => true), isTrue);
    expect(s.store.pending, isEmpty);
    await s.printConfirmed('order', (_) async => true);
    expect(server.emissions, 1);
  });
  test('failed print acknowledgment preserves confirmed receipt', () async {
    var fail = false;
    final db = memoryDatabase(
      fault: (_) {
        if (fail) throw StateError('simulated disk');
      },
    );
    final server = FakeInvoices(), s = service(db, server);
    await s.prepare('order', input());
    await s.reconcile('order', sendIfAbsent: true);
    fail = true;
    await expectLater(
      s.printConfirmed('order', (_) async => true),
      throwsA(isA<LocalOutboxException>()),
    );
    fail = false;
    expect(s.store.read('order')!.result, isNotNull);
    expect(s.store.read('order')!.state, 'confirmed');
  });
  test('historical lookup is read-only, no retroactive document', () async {
    final db = memoryDatabase(),
        server = FakeInvoices(),
        s = service(db, server);
    expect(await s.lookup('old'), isNull);
    expect(server.names, ['consultar_comprobante_pedido']);
    expect(s.store.pending, isEmpty);
    expect(server.documents, 0);
  });
  test('missing old-schema RPC only allowed when switch off', () async {
    final db = memoryDatabase();
    final s = InvoiceService(
      InvoiceStore(db, fixtureScope, 'admin'),
      (_, _) async =>
          throw const PostgrestException(message: 'absent', code: 'PGRST202'),
      enabled: false,
      requireScope: () {},
    );
    expect(await s.lookup('old'), isNull);
    final strict = InvoiceService(
      s.store,
      s.rpc,
      enabled: true,
      requireScope: () {},
    );
    await expectLater(strict.lookup('old'), throwsA(isA<PostgrestException>()));
  });
  test('network error does not become historical fallback', () async {
    final db = memoryDatabase();
    final s = InvoiceService(
      InvoiceStore(db, fixtureScope, 'admin'),
      (_, _) async => throw const SocketException('offline'),
      enabled: false,
      requireScope: () {},
    );
    await expectLater(s.lookup('old'), throwsA(isA<SocketException>()));
  });
  test('boletas and finalization queues do not share uniqueness', () async {
    final db = memoryDatabase(),
        server = FakeInvoices(),
        s = service(db, server);
    final f = FinalizationRequestStore(db, fixtureScope, 'admin');
    final bill = await s.prepare('order', input());
    final delivery = await f.prepare(
      'order',
      operational(),
      physicalDate: DateTime.utc(2026),
    );
    expect(bill['p_solicitud_id'], isNot(delivery['p_solicitud_id']));
    expect(f.pendingOrderIds, ['order']);
    expect(s.store.pending, ['order']);
    await s.reconcile('order', sendIfAbsent: true);
    expect(f.database.read(f.key('order'))!.state, 'prepared');
  });
  test('session mismatch prevents sending', () async {
    final db = memoryDatabase(),
        server = FakeInvoices(),
        s = service(db, server, scope: () => throw StateError('other user'));
    await expectLater(s.prepare('order', input()), throwsStateError);
    expect(server.names, isEmpty);
  });
  test('PDF uses immutable snapshot, never server catalog', () async {
    final db = memoryDatabase(),
        server = FakeInvoices(),
        s = service(db, server);
    await s.prepare('order', input());
    final doc = (await s.reconcile('order', sendIfAbsent: true))!;
    final mutable = doc.snapshot;
    mutable['lineas'][0]['nombre'] = 'WRONG NEW NAME';
    expect(doc.snapshot['lineas'][0]['nombre'], 'NOMBRE CAPTURADO');
    final calls = server.names.length;
    final bytes = await InvoiceSnapshotPdf.generate(doc);
    expect(ascii.decode(bytes.take(4).toList()), '%PDF');
    expect(server.names.length, calls);
  });
  test('inconsistent confirmed metadata stays pending', () async {
    final db = memoryDatabase(),
        server = FakeInvoices(),
        s = service(db, server);
    final p = await s.prepare('order', input());
    await server.call('emitir_boleta_preventa', p);
    server.document!['captura']['total'] = 999;
    await expectLater(
      s.reconcile('order'),
      throwsA(isA<LocalOutboxException>()),
    );
    expect(s.store.read('order')!.result, isNull);
  });
  test(
    'disk restart retains original pending UUID without preferences',
    () async {
      final root = await Directory.systemTemp.createTemp('invoice113b-');
      addTearDown(() => root.delete(recursive: true));
      var db = await LocalOutbox.open(root.path);
      final server = FakeInvoices();
      var s = service(db, server);
      final p = await s.prepare('order', input());
      db.close();
      db = await LocalOutbox.open(root.path);
      addTearDown(db.close);
      s = service(db, server);
      expect(s.store.read('order')!.payload, p);
      await s.reconcile('order', sendIfAbsent: true);
      expect(server.documents, 1);
    },
  );
}
