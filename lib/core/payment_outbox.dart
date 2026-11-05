import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'local_outbox.dart' show LocalOutbox;
import 'payment_money.dart';

class PaymentRequest {
  PaymentRequest(this.id, this.payload, this.state, this.result);
  final String id, state;
  final Map<String, dynamic> payload;
  final Map<String, dynamic>? result;
}

class PaymentReview implements Exception {
  const PaymentReview();
}

/// A separate database. An unresolved operation reserves the entire client
/// across actors, while completed requests remain available for audit.
class PaymentOutbox {
  PaymentOutbox._(this._db, this._directory);
  final Database _db;
  final String _directory;
  static final _sending = <String>{};

  factory PaymentOutbox.open(String directory) {
    directory = p.normalize(p.absolute(directory));
    Directory(directory).createSync(recursive: true);
    final bootstrap = File(
      p.join(directory, 'bootstrap.lock'),
    ).openSync(mode: FileMode.append);
    Database? opened;
    try {
      bootstrap.lockSync(FileLock.exclusive);
      final marker = File(p.join(directory, 'identity.json'));
      final file = File(p.join(directory, 'payments.sqlite'));
      final existing = file.existsSync();
      if (existing != marker.existsSync() ||
          (existing && file.lengthSync() < 100)) {
        throw StateError('La cola de cobros está incompleta.');
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
        throw StateError('La cola de cobros requiere revisión.');
      }
      if (existing) {
        if (db.select('PRAGMA application_id').single.values.first !=
                1095516724 ||
            db.select('PRAGMA user_version').single.values.first != 1 ||
            db
                    .select('SELECT identity FROM payment_identity')
                    .single['identity'] !=
                identity) {
          throw StateError('Identidad de cola incompatible.');
        }
        return PaymentOutbox._(db, directory);
      }
      db.execute('BEGIN IMMEDIATE');
      db.execute('PRAGMA application_id=1095516724');
      db.execute('PRAGMA user_version=1');
      db.execute('CREATE TABLE payment_identity(identity TEXT NOT NULL)');
      db.execute('INSERT INTO payment_identity VALUES (?)', [identity]);
      db.execute('''CREATE TABLE payment_requests (
        id TEXT PRIMARY KEY, scope TEXT NOT NULL, actor TEXT NOT NULL,
        client_id TEXT NOT NULL, payload TEXT NOT NULL,
        digest TEXT NOT NULL, state TEXT NOT NULL
          CHECK(state IN ('pending','review','confirmed','seen')),
        result TEXT,
        CHECK((result IS NOT NULL) = (state IN ('confirmed','seen')))
      )''');
      db.execute('''CREATE UNIQUE INDEX one_active_payment
        ON payment_requests(scope,client_id) WHERE state <> 'seen' ''');
      db.execute('COMMIT');
      return PaymentOutbox._(db, directory);
    } catch (_) {
      opened?.close();
      rethrow;
    } finally {
      bootstrap.closeSync();
    }
  }

  PaymentRequest _read(Row row) {
    final raw = row['payload'] as String;
    final payload = jsonDecode(raw) as Map<String, dynamic>;
    if (LocalOutbox.digest(raw) != row['digest'] ||
        payload['p_solicitud_id'] != row['id'] ||
        payload['p_cliente_id'] != row['client_id']) {
      throw StateError('La solicitud guardada requiere revisión.');
    }
    return PaymentRequest(
      row['id'] as String,
      payload,
      row['state'] as String,
      row['result'] == null
          ? null
          : jsonDecode(row['result'] as String) as Map<String, dynamic>,
    );
  }

  PaymentRequest? active(String scope, String actor, String client) {
    final rows = _db.select(
      "SELECT * FROM payment_requests WHERE scope=? AND client_id=? AND state<>'seen'",
      [scope, client],
    );
    if (rows.isEmpty) return null;
    if (rows.single['actor'] != actor) throw const PaymentReview();
    return _read(rows.single);
  }

  List<String> pendingClients(String scope, String actor) {
    final ids = _db
        .select(
          "SELECT client_id FROM payment_requests WHERE scope=? AND actor=? AND state<>'seen' ORDER BY client_id",
          [scope, actor],
        )
        .map((row) => row['client_id'] as String)
        .toList();
    for (final id in ids) {
      active(scope, actor, id);
    }
    return ids;
  }

  PaymentRequest prepare(
    String scope,
    String actor,
    String client,
    Map<String, dynamic> params,
  ) {
    final id = LocalOutbox.uuid();
    final raw = jsonEncode({...params, 'p_solicitud_id': id});
    _db.execute('BEGIN IMMEDIATE');
    try {
      if (active(scope, actor, client) != null) throw const PaymentReview();
      _db.execute(
        "INSERT INTO payment_requests VALUES(?,?,?,?,?,?,'pending',NULL)",
        [id, scope, actor, client, raw, LocalOutbox.digest(raw)],
      );
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
    return active(scope, actor, client)!;
  }

  Future<Map<String, dynamic>> send({
    required String scope,
    required String actor,
    required String client,
    required String id,
    required bool Function() sessionMatches,
    required Future<Object?> Function(String, Map<String, dynamic>) rpc,
    required bool Function(Object) requiresReview,
  }) async {
    if (!_sending.add(id)) {
      throw const PaymentReview();
    }
    RandomAccessFile? lock;
    try {
      // A process exit releases the lock. Pending data stays on disk for replay.
      final key = LocalOutbox.digest(jsonEncode([scope, client]));
      lock = File(
        p.join(_directory, '$key.lock'),
      ).openSync(mode: FileMode.append);
      lock.lockSync(FileLock.exclusive);
      final request = active(scope, actor, client);
      if (!sessionMatches() ||
          request == null ||
          request.id != id ||
          request.state == 'review') {
        throw const PaymentReview();
      }
      if (request.result != null) return request.result!;
      final Object? response;
      try {
        response = await rpc(
          'registrar_pago_cliente_contextual',
          request.payload,
        );
      } catch (error) {
        if (requiresReview(error)) {
          _db.execute(
            "UPDATE payment_requests SET state='review' WHERE id=? AND state='pending'",
            [id],
          );
        }
        rethrow;
      }
      if (response is! Map<String, dynamic> ||
          response['solicitud_id'] != id ||
          response['actor_id'] != actor ||
          response['cliente_id'] != client ||
          response['operacion'] != 'cobro_cliente' ||
          response['cobro_id'] is! String ||
          response['imputaciones'] is! List ||
          response['medio_pago'] != request.payload['p_medio_pago'] ||
          response['importe'] != request.payload['p_importe']) {
        throw StateError('Respuesta sin confirmación verificable.');
      }
      final lines = response['imputaciones'] as List;
      var applied = 0;
      final orders = <String>{};
      for (final line in lines) {
        if (line is! Map ||
            line['pedido_id'] is! String ||
            !orders.add(line['pedido_id'] as String)) {
          throw StateError('Imputación inválida.');
        }
        final amount = paymentCents(line['importe_aplicado']);
        if (amount <= 0 || paymentCents(line['saldo_restante']) < 0) {
          throw StateError('Imputación inválida.');
        }
        applied += amount;
      }
      if (applied != paymentCents(request.payload['p_importe'])) {
        throw StateError('El cobro no coincide con las imputaciones.');
      }
      _db.execute(
        "UPDATE payment_requests SET state='confirmed',result=? WHERE id=? AND state IN ('pending','review')",
        [jsonEncode(response), id],
      );
      return active(scope, actor, client)!.result!;
    } finally {
      try {
        lock?.closeSync();
      } finally {
        _sending.remove(id);
      }
    }
  }

  void seen(String scope, String actor, String client, String id) {
    _db.execute(
      "UPDATE payment_requests SET state='seen' WHERE scope=? AND actor=? AND client_id=? AND id=? AND state='confirmed'",
      [scope, actor, client, id],
    );
  }

  void close() => _db.close();
}
