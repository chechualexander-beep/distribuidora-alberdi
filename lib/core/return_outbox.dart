import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'local_outbox.dart' show LocalOutbox;

enum ReturnOperation {
  issue('emitir_nota_credito_contextual'),
  receive('recibir_nota_credito_contextual');

  const ReturnOperation(this.rpc);
  final String rpc;
}

class ReturnRequest {
  ReturnRequest(this.id, this.operation, this.payload, this.state, this.result);
  final String id, state;
  final ReturnOperation operation;
  final Map<String, dynamic> payload;
  final Map<String, dynamic>? result;
}

class ReturnReview implements Exception {
  const ReturnReview();
}

/// A separate database. An unresolved operation reserves the entire order
/// across actors, while completed requests remain available for audit.
class ReturnOutbox {
  ReturnOutbox._(this._db, this._directory);
  final Database _db;
  final String _directory;
  static final _sending = <String>{};

  factory ReturnOutbox.open(String directory) {
    directory = p.normalize(p.absolute(directory));
    Directory(directory).createSync(recursive: true);
    final bootstrap = File(
      p.join(directory, 'bootstrap.lock'),
    ).openSync(mode: FileMode.append);
    Database? opened;
    try {
      bootstrap.lockSync(FileLock.exclusive);
      final marker = File(p.join(directory, 'identity.json'));
      final file = File(p.join(directory, 'returns.sqlite'));
      final existing = file.existsSync();
      if (existing != marker.existsSync() ||
          (existing && file.lengthSync() < 100)) {
        throw StateError('La cola de devoluciones está incompleta.');
      }
      if (!existing) marker.writeAsStringSync(LocalOutbox.uuid(), flush: true);
      final identity = marker.readAsStringSync();
      final db = opened = sqlite3.open(file.path);
      db.execute('PRAGMA busy_timeout=5000');
      db.execute('PRAGMA journal_mode=WAL');
      db.execute('PRAGMA synchronous=FULL');
      if (db.select('PRAGMA quick_check').single.values.first != 'ok' ||
          db.select('PRAGMA journal_mode').single.values.first != 'wal' ||
          db.select('PRAGMA synchronous').single.values.first != 2) {
        throw StateError('La cola de devoluciones requiere revisión.');
      }
      if (existing) {
        if (db.select('PRAGMA application_id').single.values.first !=
                1095516723 ||
            db.select('PRAGMA user_version').single.values.first != 1 ||
            db
                    .select('SELECT identity FROM return_identity')
                    .single['identity'] !=
                identity) {
          throw StateError('Identidad de cola incompatible.');
        }
        return ReturnOutbox._(db, directory);
      }
      db.execute('BEGIN IMMEDIATE');
      db.execute('PRAGMA application_id=1095516723');
      db.execute('PRAGMA user_version=1');
      db.execute('CREATE TABLE return_identity(identity TEXT NOT NULL)');
      db.execute('INSERT INTO return_identity VALUES (?)', [identity]);
      db.execute('''CREATE TABLE return_requests (
        id TEXT PRIMARY KEY, scope TEXT NOT NULL, actor TEXT NOT NULL,
        order_id TEXT NOT NULL, operation TEXT NOT NULL, payload TEXT NOT NULL,
        digest TEXT NOT NULL, state TEXT NOT NULL
          CHECK(state IN ('pending','review','confirmed','seen')),
        result TEXT,
        CHECK((result IS NOT NULL) = (state IN ('confirmed','seen')))
      )''');
      db.execute('''CREATE UNIQUE INDEX one_active_return
        ON return_requests(scope,order_id) WHERE state <> 'seen' ''');
      db.execute('COMMIT');
      return ReturnOutbox._(db, directory);
    } catch (_) {
      opened?.close();
      rethrow;
    } finally {
      bootstrap.closeSync();
    }
  }

  ReturnRequest _read(Row row) {
    final raw = row['payload'] as String;
    final payload = jsonDecode(raw) as Map<String, dynamic>;
    if (LocalOutbox.digest(raw) != row['digest'] ||
        payload['p_solicitud_id'] != row['id']) {
      throw StateError('La solicitud guardada requiere revisión.');
    }
    return ReturnRequest(
      row['id'] as String,
      ReturnOperation.values.byName(row['operation'] as String),
      payload,
      row['state'] as String,
      row['result'] == null
          ? null
          : jsonDecode(row['result'] as String) as Map<String, dynamic>,
    );
  }

  ReturnRequest? active(String scope, String actor, String order) {
    final rows = _db.select(
      "SELECT * FROM return_requests WHERE scope=? AND order_id=? AND state<>'seen'",
      [scope, order],
    );
    if (rows.isEmpty) return null;
    if (rows.single['actor'] != actor) throw const ReturnReview();
    return _read(rows.single);
  }

  ReturnRequest prepare(
    String scope,
    String actor,
    String order,
    ReturnOperation operation,
    Map<String, dynamic> params,
  ) {
    final id = LocalOutbox.uuid();
    final raw = jsonEncode({...params, 'p_solicitud_id': id});
    _db.execute('BEGIN IMMEDIATE');
    try {
      if (active(scope, actor, order) != null) throw const ReturnReview();
      _db.execute(
        "INSERT INTO return_requests VALUES(?,?,?,?,?,?,?,'pending',NULL)",
        [id, scope, actor, order, operation.name, raw, LocalOutbox.digest(raw)],
      );
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
    return active(scope, actor, order)!;
  }

  Future<Map<String, dynamic>> send({
    required String scope,
    required String actor,
    required String order,
    required String id,
    required bool Function() sessionMatches,
    required Future<Object?> Function(String, Map<String, dynamic>) rpc,
    required bool Function(Object) requiresReview,
  }) async {
    if (!_sending.add(id)) {
      throw const ReturnReview();
    }
    RandomAccessFile? lock;
    try {
      // A process exit releases the lock. Pending data stays on disk for replay.
      final key = LocalOutbox.digest(jsonEncode([scope, order]));
      lock = File(
        p.join(_directory, '$key.lock'),
      ).openSync(mode: FileMode.append);
      lock.lockSync(FileLock.exclusive);
      final request = active(scope, actor, order);
      if (!sessionMatches() ||
          request == null ||
          request.id != id ||
          request.state == 'review') {
        throw const ReturnReview();
      }
      if (request.result != null) return request.result!;
      final Object? response;
      try {
        response = await rpc(request.operation.rpc, request.payload);
      } catch (error) {
        if (requiresReview(error)) {
          _db.execute(
            "UPDATE return_requests SET state='review' WHERE id=? AND state='pending'",
            [id],
          );
        }
        rethrow;
      }
      final identityKey = request.operation == ReturnOperation.issue
          ? 'nota_id'
          : 'recepcion_id';
      if (response is! Map<String, dynamic> ||
          response['solicitud_id'] != id ||
          response['actor_id'] != actor ||
          response[identityKey] is! String ||
          (request.operation == ReturnOperation.receive &&
              response['detalle_id'] != request.payload['p_detalle_id'])) {
        throw StateError('Respuesta sin confirmación verificable.');
      }
      _db.execute(
        "UPDATE return_requests SET state='confirmed',result=? WHERE id=? AND state IN ('pending','review')",
        [jsonEncode(response), id],
      );
      return active(scope, actor, order)!.result!;
    } finally {
      try {
        lock?.closeSync();
      } finally {
        _sending.remove(id);
      }
    }
  }

  void seen(String scope, String actor, String order, String id) {
    _db.execute(
      "UPDATE return_requests SET state='seen' WHERE scope=? AND actor=? AND order_id=? AND id=? AND state='confirmed'",
      [scope, actor, order, id],
    );
  }

  void close() => _db.close();
}
