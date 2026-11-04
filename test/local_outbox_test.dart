import 'dart:convert';
import 'dart:io';
import 'package:distribuidora_alberdi/core/local_outbox.dart';
import 'package:distribuidora_alberdi/features/orders/finalization_request.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'helpers/outbox_fixture.dart';

Future<Directory> fixtureDirectory() async {
  final root = Directory(
    p.join(Directory.current.path, '.dart_tool', 'outbox_fixtures'),
  );
  await root.create(recursive: true);
  return root.createTemp('fake-');
}

Future<Map<String, dynamic>> prepare(
  FinalizationRequestStore store, [
  String order = 'fake',
]) => store.prepare(order, operational(), physicalDate: DateTime.utc(2026));

void main() {
  for (final stage in ['before_commit', 'after_commit']) {
    test('preparation failure $stage has no cache false success', () async {
      var fail = true;
      final db = memoryDatabase(
        fault: (s) {
          if (fail && s == stage) throw StateError('Injected storage failure');
        },
      );
      final store = FinalizationRequestStore(db, fixtureScope, 'admin');
      await expectLater(prepare(store), throwsA(isA<LocalOutboxException>()));
      final persisted = store.read('fake');
      expect(persisted == null, stage == 'before_commit');
      if (stage == 'before_commit') {
        await expectLater(prepare(store), throwsA(isA<LocalOutboxException>()));
      }
      fail = false;
      final saved = await prepare(store);
      if (persisted != null) expect(saved, persisted);
    });
    test('cleanup failure $stage preserves confirmation and UUID', () async {
      var fail = false;
      final db = memoryDatabase(
        fault: (s) {
          if (fail && s == stage) throw StateError('Injected cleanup failure');
        },
      );
      final store = FinalizationRequestStore(db, fixtureScope, 'admin');
      final payload = await prepare(store);
      db.confirm(store.key('fake'), payload, receipt(payload));
      fail = true;
      await expectLater(
        store.acknowledge('fake'),
        throwsA(isA<LocalOutboxException>()),
      );
      expect(store.read('fake'), payload);
      expect(db.read(store.key('fake'))!.result, receipt(payload));
      fail = false;
      await store.acknowledge('fake');
      expect(store.pendingOrderIds, isEmpty);
      expect(await prepare(store), payload);
    });
  }
  test(
    'fresh database handle recovers full prepared and confirmed records',
    () async {
      final dir = await fixtureDirectory();
      final db = await LocalOutbox.open(dir.path);
      final store = FinalizationRequestStore(db, fixtureScope, 'admin');
      final payload = await prepare(store);
      db.close();
      final reopened = await LocalOutbox.open(dir.path);
      final restart = FinalizationRequestStore(reopened, fixtureScope, 'admin');
      expect(restart.read('fake'), payload);
      reopened.confirm(restart.key('fake'), payload, receipt(payload));
      reopened.close();
      final third = await LocalOutbox.open(dir.path);
      expect(third.read(restart.key('fake'))!.result, receipt(payload));
      third.close();
    },
  );
  for (final content in [
    '',
    '{truncated',
    'arbitrary-corruption',
    List.filled(512, 'x').join(),
  ]) {
    test('damaged SQLite $content blocks without reset', () async {
      final dir = await fixtureDirectory();
      final db = await LocalOutbox.open(dir.path);
      db.close();
      final file = File(p.join(dir.path, 'outbox.sqlite'));
      await file.writeAsString(content, flush: true);
      await expectLater(
        LocalOutbox.open(dir.path),
        throwsA(isA<LocalOutboxException>()),
      );
      expect(await file.readAsString(), content);
    });
  }
  test(
    'missing marker or database cannot silently create replacement',
    () async {
      for (final name in ['identity.json', 'outbox.sqlite']) {
        final dir = await fixtureDirectory();
        final db = await LocalOutbox.open(dir.path);
        db.close();
        await File(p.join(dir.path, name)).delete();
        await expectLater(
          LocalOutbox.open(dir.path),
          throwsA(isA<LocalOutboxException>()),
        );
      }
    },
  );
  test('tampered payload hash is detected and preserved', () async {
    final dir = await fixtureDirectory();
    final db = await LocalOutbox.open(dir.path);
    final store = FinalizationRequestStore(db, fixtureScope, 'admin');
    await prepare(store);
    final other = sqlite3.open(p.join(dir.path, 'outbox.sqlite'));
    other.execute("UPDATE outbox_records SET payload='{}'");
    other.close();
    expect(() => store.read('fake'), throwsA(isA<LocalOutboxException>()));
    await expectLater(prepare(store), throwsA(isA<LocalOutboxException>()));
    db.close();
  });
  test('project and actor scopes remain isolated', () async {
    final store = memoryStore();
    await prepare(store);
    expect(
      FinalizationRequestStore(
        store.database,
        'other-project',
        'admin',
      ).read('fake'),
      isNull,
    );
    expect(
      FinalizationRequestStore(
        store.database,
        fixtureScope,
        'other-actor',
      ).read('fake'),
      isNull,
    );
  });
  for (final content in ['', '{', '[]', 'null']) {
    test('legacy file $content fails closed', () {
      expect(
        () => FinalizationRequestStore.parseLegacyFile(content),
        throwsA(isA<LocalOutboxException>()),
      );
    });
  }
  test(
    'valid legacy import preserves byte-equivalent payload and source',
    () async {
      final original = memoryStore();
      final payload = await prepare(original);
      final store = memoryStore();
      final name =
          'flutter.preventa_v1:${Uri.encodeComponent(fixtureScope)}:admin:fake';
      final source = jsonEncode({
        name: jsonEncode(payload),
        'flutter.unrelated': 'keep',
      });
      final values = FinalizationRequestStore.parseLegacyFile(source);
      store.importLegacyValues(values);
      store.importLegacyValues(values);
      expect(store.read('fake'), payload);
      expect(jsonEncode(values), source);
      expect(store.pendingOrderIds, ['fake']);
    },
  );
  test(
    'legacy corruption or conflict blocks whole batch without partial import',
    () async {
      final old = memoryStore();
      final a = await prepare(old, 'a');
      final b = await prepare(old, 'b');
      final store = memoryStore();
      String name(String order) =>
          'preventa_v1:${Uri.encodeComponent(fixtureScope)}:admin:$order';
      expect(
        () => store.importLegacyValues({
          name('a'): jsonEncode(a),
          name('b'): '{broken',
        }),
        throwsA(isA<LocalOutboxException>()),
      );
      expect(store.pendingOrderIds, isEmpty);
      final existing = await prepare(store, 'b');
      expect(
        () => store.importLegacyValues({
          name('a'): jsonEncode(a),
          name('b'): jsonEncode(b),
        }),
        throwsA(isA<LocalOutboxException>()),
      );
      expect(store.read('a'), isNull);
      expect(store.read('b'), existing);
    },
  );
  test(
    'legacy storage failure rolls back all imports and retry is safe',
    () async {
      final old = memoryStore();
      final payload = await prepare(old);
      var fail = true;
      final db = memoryDatabase(
        fault: (s) {
          if (fail && s == 'before_commit') throw StateError('Injected');
        },
      );
      final store = FinalizationRequestStore(db, fixtureScope, 'admin');
      final values = {
        'preventa_v1:${Uri.encodeComponent(fixtureScope)}:admin:fake':
            jsonEncode(payload),
      };
      expect(
        () => store.importLegacyValues(values),
        throwsA(isA<LocalOutboxException>()),
      );
      expect(store.pendingOrderIds, isEmpty);
      fail = false;
      store.importLegacyValues(values);
      expect(store.read('fake'), payload);
    },
  );
  test('transaction uniqueness rolls back duplicate UUID batch', () async {
    final db = memoryDatabase();
    final original = memoryStore();
    final a = await prepare(original, 'a');
    final b = {...a, 'p_pedido_id': 'b'};
    expect(
      () => db.importLegacy({
        const OutboxKey(fixtureScope, 'admin', 'a'): a,
        const OutboxKey(fixtureScope, 'admin', 'b'): b,
      }),
      throwsA(isA<LocalOutboxException>()),
    );
    expect(db.pending(fixtureScope, 'admin'), isEmpty);
  });
  test(
    'one project/order cannot acquire another UUID under another actor',
    () async {
      final store = memoryStore();
      final payload = await prepare(store);
      final other = FinalizationRequestStore(
        store.database,
        fixtureScope,
        'other-actor',
      );
      await expectLater(prepare(other), throwsA(isA<LocalOutboxException>()));
      expect(store.read('fake'), payload);
      expect(other.read('fake'), isNull);
    },
  );
  test(
    'migration completes atomically and subsequent launches do not read general preferences',
    () async {
      final source = memoryStore();
      final payload = await prepare(source);
      final store = memoryStore();
      var reads = 0;
      final values = {
        'preventa_v1:${Uri.encodeComponent(fixtureScope)}:admin:fake':
            jsonEncode(payload),
      };
      await store.migrateLegacy(() async {
        reads++;
        return values;
      });
      await store.migrateLegacy(() async {
        reads++;
        throw StateError('General preferences now damaged');
      });
      expect(reads, 1);
      expect(store.read('fake'), payload);
    },
  );
  test(
    'failed migration does not mark complete and can be retried unchanged',
    () async {
      final source = memoryStore();
      final payload = await prepare(source);
      var fail = true;
      final db = memoryDatabase(
        fault: (stage) {
          if (fail && stage == 'before_commit') throw StateError('Injected');
        },
      );
      final store = FinalizationRequestStore(db, fixtureScope, 'admin');
      var reads = 0;
      Future<Map<String, Object?>> loader() async {
        reads++;
        return {
          'preventa_v1:${Uri.encodeComponent(fixtureScope)}:admin:fake':
              jsonEncode(payload),
        };
      }

      await expectLater(
        store.migrateLegacy(loader),
        throwsA(isA<LocalOutboxException>()),
      );
      expect(store.pendingOrderIds, isEmpty);
      fail = false;
      await store.migrateLegacy(loader);
      expect(reads, 2);
      expect(store.read('fake'), payload);
    },
  );
  test(
    'conflicting flutter-prefixed legacy aliases are never overwritten',
    () async {
      final source = memoryStore();
      final payload = await prepare(source);
      final store = memoryStore();
      final name =
          'preventa_v1:${Uri.encodeComponent(fixtureScope)}:admin:fake';
      expect(
        () => store.importLegacyValues({
          name: jsonEncode(payload),
          'flutter.$name': jsonEncode({...payload, 'p_importe_pago': 999}),
        }),
        throwsA(isA<LocalOutboxException>()),
      );
      expect(store.pendingOrderIds, isEmpty);
    },
  );
  test('file SQLite uses WAL and synchronous FULL', () async {
    final dir = await fixtureDirectory();
    final db = await LocalOutbox.open(dir.path);
    final connection = sqlite3.open(p.join(dir.path, 'outbox.sqlite'));
    expect(connection.select('PRAGMA journal_mode').single.values.first, 'wal');
    connection.close();
    db.close();
  });
}
