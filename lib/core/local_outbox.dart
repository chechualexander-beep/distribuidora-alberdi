import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

class LocalOutboxException implements Exception {
  const LocalOutboxException(this.message);
  final String message;
  @override
  String toString() => message;
}

class OutboxKey {
  const OutboxKey(this.scope, this.actor, this.order);
  final String scope, actor, order;
  List<String> get values => [scope, actor, order];
  String get encoded => jsonEncode(values);
}

class OutboxRecord {
  OutboxRecord(this.payload, this.state, this.result);
  final Map<String, dynamic> payload;
  final String state;
  final Map<String, dynamic>? result;
}

/// A native, local-only queue. No network, device-time scheduling or automatic
/// synchronization. Platform-independent on Dart IO (Windows and Android).
class LocalOutbox {
  LocalOutbox._(this._db, this._directory, this._fault);
  final Database _db;
  final String? _directory;
  final void Function(String stage)? _fault;
  bool _closed = false;
  static final Map<String, Future<void>> _serial = {};
  static const _applicationId = 1095516722;

  static String digest(String value) =>
      sha256.convert(utf8.encode(value)).toString();

  static String uuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final s = bytes.map((n) => n.toRadixString(16).padLeft(2, '0')).join();
    return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
  }

  static Future<T> _exclusive<T>(
    String id,
    String? lockPath,
    Future<T> Function() action,
  ) async {
    final previous = _serial[id] ?? Future<void>.value();
    final done = Completer<void>();
    _serial[id] = done.future;
    await previous;
    RandomAccessFile? handle;
    var locked = false;
    try {
      if (lockPath != null) {
        handle = await File(lockPath).open(mode: FileMode.append);
        await handle.lock(FileLock.blockingExclusive);
        locked = true;
      }
      return await action();
    } finally {
      try {
        if (locked) await handle!.unlock();
      } finally {
        try {
          await handle?.close();
        } finally {
          done.complete();
          if (identical(_serial[id], done.future)) _serial.remove(id);
        }
      }
    }
  }

  static Future<LocalOutbox> open(
    String directory, {
    void Function(String)? testingFault,
  }) async {
    final root = p.normalize(p.absolute(directory));
    await Directory(root).create(recursive: true);
    return _exclusive('bootstrap:$root', p.join(root, 'bootstrap.lock'), () async {
      final file = File(p.join(root, 'outbox.sqlite'));
      final marker = File(p.join(root, 'identity.json'));
      final existed = await file.exists();
      final hasMarker = await marker.exists();
      if (existed != hasMarker || (existed && await file.length() < 100)) {
        throw const LocalOutboxException(
          'El almacén local está incompleto o dañado. Se conserva para revisión; no inicies otra gestión.',
        );
      }
      Database? db;
      try {
        if (!existed) {
          // If creation fails after this durable marker, reopening fails closed.
          await marker.writeAsString(
            jsonEncode({'version': 1, 'identity': uuid()}),
            flush: true,
          );
        }
        final identity = jsonDecode(await marker.readAsString()) as Map;
        if (identity['version'] != 1 || identity['identity'] is! String) {
          throw const FormatException();
        }
        db = sqlite3.open(file.path);
        db.execute('PRAGMA busy_timeout=5000');
        db.execute('PRAGMA journal_mode=WAL');
        db.execute('PRAGMA synchronous=FULL');
        db.execute('PRAGMA foreign_keys=ON');
        if (db.select('PRAGMA journal_mode').single.values.first != 'wal' ||
            db.select('PRAGMA synchronous').single.values.first != 2) {
          throw const FormatException('Durability settings unavailable');
        }
        if (existed) {
          if (db.select('PRAGMA quick_check').single.values.first != 'ok' ||
              db.select('PRAGMA application_id').single.values.first !=
                  _applicationId ||
              db.select('PRAGMA user_version').single.values.first != 1 ||
              db.select('SELECT value FROM outbox_meta WHERE name=?', [
                    'identity',
                  ]).single['value'] !=
                  identity['identity']) {
            throw const FormatException();
          }
        } else {
          _createSchema(db, identity['identity'] as String);
        }
        await Directory(p.join(root, 'locks')).create(recursive: true);
        return LocalOutbox._(db, root, testingFault);
      } catch (_) {
        db?.close();
        throw const LocalOutboxException(
          'No se pudo abrir el almacén local. No se borró ni restableció; requiere revisión.',
        );
      }
    });
  }

  /// No application/profile path is resolved for tests.
  factory LocalOutbox.memory({void Function(String)? testingFault}) {
    final db = sqlite3.openInMemory();
    db.execute('PRAGMA synchronous=FULL');
    _createSchema(db, uuid());
    return LocalOutbox._(db, null, testingFault);
  }

  static void _createSchema(Database db, String identity) {
    db.execute('BEGIN IMMEDIATE');
    try {
      db.execute(
        '''CREATE TABLE outbox_meta(name TEXT PRIMARY KEY,value TEXT NOT NULL)''',
      );
      db.execute(
        '''CREATE TABLE outbox_records(
        scope TEXT NOT NULL, actor TEXT NOT NULL, order_id TEXT NOT NULL,
        request_id TEXT NOT NULL UNIQUE, payload TEXT NOT NULL, payload_hash TEXT NOT NULL,
        state TEXT NOT NULL CHECK(state IN ('prepared','confirmed','acknowledged','review')),
        result TEXT, result_hash TEXT, last_error TEXT,
        PRIMARY KEY(scope,actor,order_id),
        CHECK((state IN ('confirmed','acknowledged') AND result IS NOT NULL AND result_hash IS NOT NULL)
          OR (state IN ('prepared','review') AND result IS NULL AND result_hash IS NULL)))''',
      );
      db.execute(
        'CREATE UNIQUE INDEX one_order_per_project ON outbox_records(scope,order_id)',
      );
      db.execute('INSERT INTO outbox_meta VALUES(?,?)', ['identity', identity]);
      db.execute('PRAGMA application_id=$_applicationId');
      db.execute('PRAGMA user_version=1');
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  void _ensureOpen() {
    if (_closed) {
      throw const LocalOutboxException('El almacén local está cerrado.');
    }
  }

  T _transaction<T>(T Function() action) {
    _ensureOpen();
    var committed = false;
    try {
      _db.execute('BEGIN IMMEDIATE');
      final value = action();
      _fault?.call('before_commit');
      _db.execute('COMMIT');
      committed = true;
      _fault?.call('after_commit');
      return value;
    } catch (_) {
      if (!committed) {
        try {
          _db.execute('ROLLBACK');
        } catch (_) {
          /* No transaction began. */
        }
      }
      throw const LocalOutboxException(
        'No se pudo confirmar el almacenamiento local. No inicies otra gestión; revisá la solicitud guardada.',
      );
    }
  }

  Future<T> withKeyLock<T>(OutboxKey key, Future<T> Function() action) {
    _ensureOpen();
    final name = digest(jsonEncode([key.scope, key.order]));
    final id = '${_directory ?? identityHashCode(this)}:$name';
    return _exclusive(
      id,
      _directory == null ? null : p.join(_directory, 'locks', '$name.lock'),
      action,
    );
  }

  OutboxRecord? read(OutboxKey key) {
    _ensureOpen();
    try {
      final rows = _db.select(
        'SELECT * FROM outbox_records WHERE scope=? AND actor=? AND order_id=?',
        key.values,
      );
      if (rows.isEmpty) return null;
      final row = rows.single;
      final raw = row['payload'] as String;
      if (digest(raw) != row['payload_hash']) throw const FormatException();
      final payload = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      if (payload['p_pedido_id'] != key.order ||
          payload['p_solicitud_id'] != row['request_id']) {
        throw const FormatException();
      }
      Map<String, dynamic>? result;
      if (row['result'] != null) {
        final rawResult = row['result'] as String;
        if (digest(rawResult) != row['result_hash']) {
          throw const FormatException();
        }
        result = Map<String, dynamic>.from(jsonDecode(rawResult) as Map);
      }
      return OutboxRecord(payload, row['state'] as String, result);
    } catch (_) {
      throw const LocalOutboxException(
        'La solicitud local está dañada o no se puede leer. Se conserva para revisión.',
      );
    }
  }

  /// Read-only export for an authorized administrative audit, across actors.
  /// Includes acknowledged receipts and fails closed on any damaged record.
  List<Map<String, dynamic>> auditScope(String scope) {
    _ensureOpen();
    try {
      return _db
          .select(
            'SELECT actor,order_id,payload_hash,last_error FROM outbox_records WHERE scope=? ORDER BY actor,order_id',
            [scope],
          )
          .map((row) {
            final key = OutboxKey(
              scope,
              row['actor'] as String,
              row['order_id'] as String,
            );
            final record = read(key)!;
            return <String, dynamic>{
              'scope': scope,
              'actor': key.actor,
              'order': key.order,
              'state': record.state,
              'payload': record.payload,
              'payload_hash': row['payload_hash'],
              'result': record.result,
              'last_error': row['last_error'],
            };
          })
          .toList(growable: false);
    } catch (_) {
      throw const LocalOutboxException(
        'No se pudo auditar íntegramente la cola. Se conserva para revisión.',
      );
    }
  }

  List<String> pending(String scope, String actor) {
    _ensureOpen();
    try {
      final rows = _db.select(
        "SELECT order_id FROM outbox_records WHERE scope=? AND actor=? AND state<>'acknowledged' ORDER BY order_id",
        [scope, actor],
      );
      final ids = rows.map((row) => row['order_id'] as String).toList();
      for (final order in ids) {
        read(OutboxKey(scope, actor, order));
      }
      return ids;
    } catch (_) {
      throw const LocalOutboxException(
        'No se pudieron leer las solicitudes locales. No restablezcas el almacén.',
      );
    }
  }

  Future<Map<String, dynamic>> prepare(
    OutboxKey key,
    Future<Map<String, dynamic>> Function(String uuid) build,
  ) => withKeyLock(key, () async {
    final old = read(key);
    if (old != null) return old.payload;
    if (_db.select(
      'SELECT actor FROM outbox_records WHERE scope=? AND order_id=?',
      [key.scope, key.order],
    ).isNotEmpty) {
      throw const LocalOutboxException(
        'El pedido ya tiene una solicitud local de otro usuario. Requiere revisión; no se preparó otra.',
      );
    }
    final payload = await build(uuid());
    final raw = jsonEncode(payload);
    _transaction(() {
      // Database uniqueness is the final defense across processes/isolates.
      if (read(key) != null) return;
      _db.execute(
        'INSERT INTO outbox_records(scope,actor,order_id,request_id,payload,payload_hash,state) VALUES(?,?,?,?,?,?,?)',
        [
          ...key.values,
          payload['p_solicitud_id'],
          raw,
          digest(raw),
          'prepared',
        ],
      );
    });
    return read(key)!.payload;
  });

  void requirePersisted(OutboxKey key, Map<String, dynamic> payload) {
    final record = read(key);
    if (record == null || jsonEncode(record.payload) != jsonEncode(payload)) {
      throw const LocalOutboxException(
        'La solicitud no coincide con una copia local confirmada. No se envió V2.',
      );
    }
    if (record.state == 'review') {
      throw const LocalOutboxException(
        'La solicitud requiere revisión por un rechazo anterior. Se conserva sin reenviar.',
      );
    }
  }

  void confirm(
    OutboxKey key,
    Map<String, dynamic> payload,
    Map<String, dynamic> result,
  ) {
    requirePersisted(key, payload);
    final old = read(key)!;
    if (old.result != null) {
      if (jsonEncode(old.result) != jsonEncode(result)) {
        throw const LocalOutboxException(
          'La confirmación local tiene otro contenido.',
        );
      }
      return;
    }
    final raw = jsonEncode(result);
    _transaction(
      () => _db.execute(
        "UPDATE outbox_records SET state='confirmed',result=?,result_hash=? WHERE scope=? AND actor=? AND order_id=?",
        [raw, digest(raw), ...key.values],
      ),
    );
  }

  void acknowledge(OutboxKey key) {
    final old = read(key);
    if (old == null || old.result == null) {
      throw const LocalOutboxException(
        'Solo se puede cerrar una solicitud confirmada.',
      );
    }
    if (old.state == 'acknowledged') return;
    _transaction(
      () => _db.execute(
        "UPDATE outbox_records SET state='acknowledged' WHERE scope=? AND actor=? AND order_id=?",
        key.values,
      ),
    );
    // Keep the immutable receipt/tombstone. Never delete a request to clean UI.
  }

  void review(OutboxKey key, String code) {
    if (read(key)?.result != null) return;
    _transaction(
      () => _db.execute(
        "UPDATE outbox_records SET state='review',last_error=? WHERE scope=? AND actor=? AND order_id=? AND state='prepared'",
        [code, ...key.values],
      ),
    );
  }

  bool legacyImported(String id) => _db.select(
    'SELECT value FROM outbox_meta WHERE name=?',
    ['legacy:$id'],
  ).isNotEmpty;

  void importLegacy(
    Map<OutboxKey, Map<String, dynamic>> records, {
    String? migrationId,
  }) {
    // One transaction; never delete or modify the legacy source.
    _transaction(() {
      for (final entry in records.entries) {
        final old = read(entry.key);
        final raw = jsonEncode(entry.value);
        if (old != null) {
          if (jsonEncode(old.payload) != raw) {
            throw const FormatException('Conflicting legacy request');
          }
          continue;
        }
        _db.execute(
          'INSERT INTO outbox_records(scope,actor,order_id,request_id,payload,payload_hash,state) VALUES(?,?,?,?,?,?,?)',
          [
            ...entry.key.values,
            entry.value['p_solicitud_id'],
            raw,
            digest(raw),
            'prepared',
          ],
        );
      }
      if (migrationId != null) {
        _db.execute(
          'INSERT OR IGNORE INTO outbox_meta(name,value) VALUES(?,?)',
          ['legacy:$migrationId', 'complete'],
        );
      }
    });
  }

  void close() {
    if (!_closed) {
      _db.close();
      _closed = true;
    }
  }
}
