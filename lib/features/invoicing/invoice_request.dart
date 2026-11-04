import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_config.dart';
import '../../core/local_outbox.dart';

typedef InvoiceRpc =
    Future<dynamic> Function(String name, Map<String, dynamic> params);

/// Both a TESTING binary opt-in and the server's disabled-by-default switch
/// are required. Merely installing this source/migration activates nothing.
bool transactionalInvoicesEnabled(AppConfig config) =>
    config.isTesting &&
    const bool.fromEnvironment('ENABLE_INTERNAL_BOLETAS', defaultValue: false);

Map<String, dynamic> _copy(Map<String, dynamic> value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);

String _canonical(dynamic value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return '{${keys.map((k) => '${jsonEncode(k)}:${_canonical(value[k])}').join(',')}}';
  }
  if (value is List) return '[${value.map(_canonical).join(',')}]';
  return jsonEncode(value);
}

class InvoiceStore {
  InvoiceStore(this.database, this.projectUrl, this.actor);
  final LocalOutbox database;
  final String projectUrl, actor;
  String get scope => 'boletas_v1:$projectUrl';
  OutboxKey key(String order) => OutboxKey(scope, actor, order);
  OutboxRecord? read(String order) => database.read(key(order));
  List<String> get pending => database.pending(scope, actor);

  Future<Map<String, dynamic>> prepare(
    String order,
    Map<String, dynamic> input,
    Future<String> Function() regime,
  ) {
    if (input.keys.any((k) => !{'p_originales', 'p_agregados'}.contains(k))) {
      throw ArgumentError('Campos de boleta no admitidos.');
    }
    for (final group in ['p_originales', 'p_agregados']) {
      final items = input[group];
      if (items is! List ||
          items.length > 500 ||
          (group == 'p_originales' && items.isEmpty)) {
        throw ArgumentError('Líneas de boleta inválidas.');
      }
      final allowed = group == 'p_originales'
          ? {'detalle_id', 'cantidad_facturada'}
          : {'producto_id', 'tipo_precio', 'cantidad_facturada'};
      for (final line in items) {
        if (line is! Map ||
            line.length != allowed.length ||
            line.keys.any((k) => !allowed.contains(k))) {
          throw ArgumentError('Solo se permiten datos operativos de boleta.');
        }
        final q = line['cantidad_facturada'];
        if (q is! num ||
            !q.isFinite ||
            q < 0 ||
            (group == 'p_agregados' && q == 0)) {
          throw ArgumentError('Cantidad de boleta inválida.');
        }
      }
    }
    final frozen = _copy(input);
    return database.prepare(
      key(order),
      (uuid) async => {
        ...frozen,
        'p_pedido_id': order,
        'p_solicitud_id': uuid,
        'p_regimen_id': await regime(),
      },
    );
  }
}

class InvoiceDocument {
  InvoiceDocument._(this._receipt);
  final Map<String, dynamic> _receipt;
  Map<String, dynamic> get receipt => _copy(_receipt);
  Map<String, dynamic> get result =>
      Map<String, dynamic>.from(receipt['resultado'] as Map);
  Map<String, dynamic> get snapshot =>
      _copy(Map<String, dynamic>.from(receipt['captura'] as Map));
  String get number => result['numero'] as String;

  factory InvoiceDocument.validate(
    Map<String, dynamic> receipt, {
    required String order,
    Map<String, dynamic>? payload,
  }) {
    try {
      final r = Map<String, dynamic>.from(receipt['resultado'] as Map);
      final c = Map<String, dynamic>.from(receipt['captura'] as Map);
      final total = r['total'];
      if (r['version'] != 1 ||
          c['version'] != 1 ||
          r['pedido_id'] != order ||
          c['pedido_id'] != order ||
          r['comprobante_id'] is! String ||
          r['solicitud_id'] is! String ||
          r['numero'] is! String ||
          !RegExp(r'^[1-9][0-9]*$').hasMatch(r['numero'] as String) ||
          c['numero'] != r['numero'] ||
          c['naturaleza'] != 'boleta_interna_no_fiscal' ||
          c['tipo'] != 'boleta_preventa' ||
          c['moneda'] != 'ARS' ||
          c['fecha_emision'] != r['fecha_emision'] ||
          DateTime.tryParse(r['fecha_emision'] as String) == null ||
          total is! num ||
          !total.isFinite ||
          total <= 0 ||
          c['total'] != total ||
          c['cliente'] is! Map ||
          c['actor'] is! Map ||
          c['actor']['id'] != receipt['actor_id'] ||
          r['captura_hash'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(r['captura_hash'] as String) ||
          c['lineas'] is! List ||
          (c['lineas'] as List).isEmpty ||
          (payload != null && r['solicitud_id'] != payload['p_solicitud_id'])) {
        throw const FormatException();
      }
      var sum = 0.0;
      for (final line in c['lineas'] as List) {
        final q = line['cantidad_documentada'];
        final price = line['precio_unitario'];
        final subtotal = line['subtotal'];
        if (q is! num ||
            !q.isFinite ||
            q <= 0 ||
            price is! num ||
            !price.isFinite ||
            price < 0 ||
            subtotal is! num ||
            !subtotal.isFinite ||
            line['nombre'] is! String ||
            ((q * price * 100).round() - (subtotal * 100).round()).abs() > 0) {
          throw const FormatException();
        }
        sum += subtotal;
      }
      if ((sum * 100).round() != (total * 100).round()) {
        throw const FormatException();
      }
      return InvoiceDocument._(_copy(receipt));
    } catch (_) {
      throw const LocalOutboxException(
        'El comprobante recibido no es consistente. Se conserva la solicitud para revisión.',
      );
    }
  }
}

class InvoiceService {
  InvoiceService(
    this.store,
    this.rpc, {
    required this.enabled,
    required this.requireScope,
  });
  final InvoiceStore store;
  final InvoiceRpc rpc;
  final bool enabled;
  final void Function() requireScope;

  Future<void> runLegacyIfClear(
    String order,
    Future<void> Function() action,
  ) => store.database.withKeyLock(store.key(order), () async {
    requireScope();
    if (enabled ||
        store.database
            .auditScope(store.scope)
            .any((r) => r['order'] == order) ||
        await lookup(order) != null) {
      throw const LocalOutboxException(
        'Existe un comprobante o una solicitud nueva. No se permite emitir por el circuito anterior.',
      );
    }
    requireScope();
    await action();
  });

  Future<dynamic> _call(String name, Map<String, dynamic> params) {
    requireScope();
    return rpc(name, params).timeout(const Duration(seconds: 20));
  }

  Future<Map<String, dynamic>> prepare(
    String order,
    Map<String, dynamic> input,
  ) async {
    requireScope();
    if (store.read(order) != null) return store.read(order)!.payload;
    if (!enabled) {
      throw const LocalOutboxException(
        'La emisión nueva de boletas no está habilitada.',
      );
    }
    return store.prepare(order, input, () async {
      final raw = Map<String, dynamic>.from(
        await _call('stock_estado_transicion', {}) as Map,
      );
      requireScope();
      final t = raw['transicion'] as Map;
      final r = raw['regimen'] as Map;
      if (t['mantenimiento'] != false ||
          t['paso_instalacion'] != 3 ||
          r['protocolo'] != 2 ||
          t['regimen_id'] != r['id'] ||
          r['cerrado_at'] != null ||
          r['id'] is! String ||
          !RegExp(r'^[a-fA-F0-9-]{36}$').hasMatch(r['id'] as String)) {
        throw const LocalOutboxException(
          'El régimen no está disponible para emitir. No se preparó otra boleta.',
        );
      }
      return r['id'] as String;
    });
  }

  Future<InvoiceDocument?> reconcile(
    String order, {
    bool sendIfAbsent = false,
  }) {
    requireScope();
    return store.database.withKeyLock(store.key(order), () async {
      requireScope();
      final saved = store.read(order);
      if (saved == null) {
        throw const LocalOutboxException(
          'No existe una solicitud persistida de boleta.',
        );
      }
      final payload = _copy(saved.payload);
      store.database.requirePersisted(store.key(order), payload);
      if (saved.result != null) {
        return InvoiceDocument.validate(
          saved.result!,
          order: order,
          payload: payload,
        );
      }
      try {
        final state = Map<String, dynamic>.from(
          await _call('consultar_boleta_interna', {
                'p_solicitud_id': payload['p_solicitud_id'],
              })
              as Map,
        );
        if (state['estado'] != 'confirmada') {
          if (state['estado'] != 'inexistente') {
            throw const FormatException('Estado ambiguo');
          }
          if (!sendIfAbsent) return null;
          if (!enabled) {
            throw const LocalOutboxException(
              'La boleta sigue pendiente. La emisión está deshabilitada; no se creó otra solicitud.',
            );
          }
        }
        // A confirmed UUID alone does not prove that this local content matches.
        store.database.requirePersisted(store.key(order), payload);
        final result = Map<String, dynamic>.from(
          await _call('emitir_boleta_preventa', payload) as Map,
        );
        final full = Map<String, dynamic>.from(
          await _call('consultar_boleta_interna', {
                'p_solicitud_id': payload['p_solicitud_id'],
              })
              as Map,
        );
        if (full['estado'] != 'confirmada' ||
            _canonical(full['resultado']) != _canonical(result) ||
            full['actor_id'] != store.actor) {
          throw const LocalOutboxException(
            'Confirmación ambigua. Conservá la solicitud; no emitas otra.',
          );
        }
        final document = InvoiceDocument.validate(
          full,
          order: order,
          payload: payload,
        );
        requireScope();
        store.database.confirm(store.key(order), payload, document.receipt);
        return InvoiceDocument.validate(
          store.read(order)!.result!,
          order: order,
          payload: payload,
        );
      } on PostgrestException catch (e) {
        if (e.code == 'PT422' ||
            (e.code == 'PT409' &&
                [
                  'solicitud_incompatible',
                  'pedido_ya_documentado',
                  'contexto_regimen_incompatible',
                ].any(e.message.contains))) {
          store.database.review(
            store.key(order),
            e.message.contains('solicitud_incompatible')
                ? 'solicitud_incompatible'
                : 'revision_boleta',
          );
        }
        rethrow;
      }
    });
  }

  /// Read-only lookup; never creates a historical document or emits a new one.
  Future<InvoiceDocument?> lookup(String order) async {
    requireScope();
    final local = store.read(order);
    if (local != null) {
      if (local.result != null) {
        return InvoiceDocument.validate(
          local.result!,
          order: order,
          payload: local.payload,
        );
      }
      throw const LocalOutboxException(
        'Hay una boleta pendiente o en revisión. Recuperala antes de imprimir.',
      );
    }
    requireScope();
    try {
      final raw = Map<String, dynamic>.from(
        await _call('consultar_comprobante_pedido', {'p_pedido_id': order})
            as Map,
      );
      if (raw['estado'] == 'sin_comprobante_nuevo') return null;
      if (raw['estado'] != 'confirmada') {
        throw const FormatException('Respuesta ambigua');
      }
      return InvoiceDocument.validate(raw, order: order);
    } on PostgrestException catch (e) {
      // Explicitly absent RPC on the old schema is the only compatibility case.
      if (!enabled && e.code == 'PGRST202') return null;
      rethrow;
    }
  }

  Future<bool> printConfirmed(
    String order,
    Future<bool> Function(InvoiceDocument) print,
  ) => store.database.withKeyLock(store.key(order), () async {
    requireScope();
    final saved = store.read(order);
    if (saved?.result == null) {
      throw const LocalOutboxException('La boleta no está confirmada.');
    }
    final document = InvoiceDocument.validate(
      saved!.result!,
      order: order,
      payload: saved.payload,
    );
    final accepted = await print(
      document,
    ); // Errors/cancellation leave confirmed + pending print.
    requireScope();
    if (accepted) store.database.acknowledge(store.key(order));
    return accepted;
  });
}

Future<LocalOutbox>? _openingInvoices;
Future<InvoiceService> invoiceService(SupabaseClient client) async {
  appConfig.requireV2Client(client.rest.url);
  final actor = client.auth.currentUser?.id;
  if (actor == null) throw const LocalOutboxException('Sesión requerida.');
  final support = await getApplicationSupportDirectory();
  LocalOutbox db;
  try {
    db = await (_openingInvoices ??= LocalOutbox.open(
      p.join(support.path, 'boletas_internas_outbox_testing'),
    ));
  } catch (_) {
    _openingInvoices = null;
    rethrow;
  }
  return InvoiceService(
    InvoiceStore(db, client.rest.url, actor),
    (name, params) async => client.rpc(name, params: params),
    enabled: transactionalInvoicesEnabled(appConfig),
    requireScope: () {
      appConfig.requireV2Client(client.rest.url);
      if (client.auth.currentUser?.id != actor) {
        throw const LocalOutboxException(
          'La sesión cambió. No se envió la boleta.',
        );
      }
    },
  );
}
