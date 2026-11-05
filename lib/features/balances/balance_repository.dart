import 'dart:convert';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/app_config.dart';
import '../../core/payment_money.dart';

typedef BalanceRow = Map<String, dynamic>;

class BalancePage {
  BalancePage(this.rows, this.total);
  final List<BalanceRow> rows;
  final int total;
}

Future<List<BalanceRow>> allBalancePages(
  Future<BalancePage> Function(int offset) fetch,
) async {
  final rows = <BalanceRow>[];
  int? expected;
  while (true) {
    final page = await fetch(rows.length);
    expected ??= page.total;
    if (expected != page.total ||
        page.total < 0 ||
        rows.length + page.rows.length > expected ||
        (page.rows.isEmpty && rows.length < expected)) {
      throw StateError('Los saldos cambiaron durante la lectura. Actualizá.');
    }
    rows.addAll(page.rows);
    if (rows.length == expected) return rows;
  }
}

class BalanceRepository {
  BalanceRepository(this.client, {AppConfig? config})
    : config = config ?? appConfig,
      actor = client.auth.currentUser?.id ?? '';
  final SupabaseClient client;
  final AppConfig config;
  final String actor;
  String get scope => '${config.environment.name}:${config.project}';
  bool get sessionMatches =>
      actor.isNotEmpty &&
      client.auth.currentUser?.id == actor &&
      client.rest.url.replaceFirst(RegExp(r'/$'), '') ==
          '${config.supabaseUrl}/rest/v1';

  Future<void> requireAdmin() async {
    if (!sessionMatches) throw StateError('Sesión no autorizada.');
    final row = await client
        .from('usuarios')
        .select('rol,activo')
        .eq('id', actor)
        .single();
    if (row['rol'] != 'administrador' || row['activo'] != true) {
      throw StateError('Solo administración activa.');
    }
  }

  /// Read-only OpenAPI capability check under the current actor. Failure keeps
  /// payments disabled, while balances remain available for consultation.
  Future<bool> paymentsAvailable() async {
    final http = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      await requireAdmin();
      final session = client.auth.currentSession!;
      final request = await http.getUrl(
        Uri.parse('${config.supabaseUrl}/rest/v1/'),
      );
      final headers = {
        ...client.headers,
        'Authorization': 'Bearer ${session.accessToken}',
        'Accept': 'application/openapi+json',
        'Accept-Profile': 'public',
      };
      headers.forEach((name, value) => request.headers.set(name, value));
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      if (!sessionMatches || response.statusCode != 200) return false;
      final bodyText = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 10));
      final doc = jsonDecode(bodyText) as Map;
      final operation =
          doc['paths']?['/rpc/registrar_pago_cliente_contextual']?['post'];
      final parameters = operation?['parameters'] as List?;
      if (parameters == null) return false;
      final body = parameters.where((p) => p['in'] == 'body').firstOrNull;
      final schema = body?['schema'] as Map?;
      final properties = schema?['properties'] as Map?;
      const keys = [
        'p_solicitud_id',
        'p_cliente_id',
        'p_importe',
        'p_medio_pago',
        'p_observacion',
      ];
      return properties != null && keys.every(properties.containsKey);
    } catch (_) {
      return false;
    } finally {
      http.close(force: true);
    }
  }

  Future<List<BalanceRow>> _rows(
    String table,
    String fields,
    String order, {
    String? clientId,
    bool debtors = false,
  }) async {
    final rows = await allBalancePages((offset) async {
      if (!sessionMatches) throw StateError('Cambió la sesión.');
      var query = client.from(table).select(fields);
      if (clientId != null) query = query.eq('cliente_id', clientId);
      if (debtors) query = query.gt('saldo_pendiente', 0);
      final page = await query
          .order(order)
          .range(offset, offset + 199)
          .count(CountOption.exact);
      if (!sessionMatches) throw StateError('Cambió la sesión.');
      return BalancePage(List<BalanceRow>.from(page.data), page.count);
    });
    if (rows.map((row) => row[order]).toSet().length != rows.length) {
      throw StateError('La lectura contiene filas repetidas. Actualizá.');
    }
    return rows;
  }

  Future<List<BalanceRow>> debtors() => _rows(
    'saldos_pendientes_clientes',
    'cliente_id,nombre_comercio,saldo_pendiente,cantidad_pedidos_con_saldo',
    'cliente_id',
    debtors: true,
  );

  Future<BalanceRow> account(String id) async {
    final rows = await _rows(
      'saldos_pendientes_clientes',
      'cliente_id,nombre_comercio,saldo_pendiente,saldo_a_favor,cantidad_pedidos_con_saldo',
      'cliente_id',
      clientId: id,
    );
    if (rows.length != 1) {
      throw StateError('No se pudo identificar la cuenta del cliente.');
    }
    return rows.single;
  }

  Future<List<BalanceRow>> debts(String id) => _rows(
    'saldos_pendientes_pedidos',
    'pedido_id,cliente_id,created_at,fecha_finalizacion,total_entregado,total_pagado,total_notas_credito,credito_aplicado,saldo_pendiente',
    'pedido_id',
    clientId: id,
    debtors: true,
  );

  Future<List<BalanceRow>> history(String id) => _rows(
    'cobros_cliente',
    'id,importe,medio_pago,fecha_pago,observacion',
    'id',
    clientId: id,
  );

  Future<Object?> pay(String name, Map<String, dynamic> payload) async {
    if (name != 'registrar_pago_cliente_contextual') {
      throw StateError('RPC incompatible.');
    }
    await requireAdmin();
    final session = client.auth.currentSession!;
    if (!sessionMatches || session.user.id != actor) {
      throw StateError('Cambió la sesión.');
    }
    return await client
        .rpc(name, params: payload)
        .setHeader('Authorization', 'Bearer ${session.accessToken}');
  }
}

int debtorTotal(List<BalanceRow> rows) =>
    rows.fold(0, (total, row) => total + paymentCents(row['saldo_pendiente']));

String balanceDate(Object? value) {
  final instant = DateTime.tryParse(value?.toString() ?? '');
  if (instant == null) return 'Fecha no disponible';
  final local = instant.toUtc().subtract(const Duration(hours: 3));
  return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
}
