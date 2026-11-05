import 'package:distribuidora_alberdi/features/balances/balance_repository.dart';

class FakeBalanceRepository implements BalanceRepository {
  bool admin = true, capable = true, validSession = true, failReads = false;
  bool loseResponse = false;
  @override
  String? capabilityIssue;
  int debt = 10000, calls = 0, accountReads = 0;
  num noteAmount = 10, appliedCredit = 20, favor = 0;
  final saved = <String, Map<String, dynamic>>{};

  @override
  String get actor => 'admin';
  @override
  String get scope => 'testing:fixture';
  @override
  bool get sessionMatches => validSession;
  @override
  Future<void> requireAdmin() async {
    if (!admin || !validSession) throw StateError('No autorizado');
  }

  @override
  Future<bool> paymentsAvailable() async => capable;
  @override
  Future<BalanceRow> account(String id) async {
    accountReads++;
    if (failReads) throw StateError('Lectura fallida');
    return {
      'cliente_id': id,
      'nombre_comercio': 'Cliente QA',
      'saldo_pendiente': debt / 100,
      'saldo_a_favor': favor,
      'cantidad_pedidos_con_saldo': debt == 0 ? 0 : 2,
    };
  }

  @override
  Future<List<BalanceRow>> debtors() async {
    if (failReads) throw StateError('Lectura fallida');
    return debt == 0 ? [] : [await account('client')];
  }

  @override
  Future<List<BalanceRow>> debts(String id) async {
    if (failReads) throw StateError('Lectura fallida');
    return debt == 0
        ? []
        : [
            {
              'pedido_id': 'old-order',
              'cliente_id': id,
              'created_at': '2026-11-05T01:00:00Z',
              'fecha_finalizacion': '2026-11-05T01:00:00Z',
              'total_entregado': 150,
              'total_pagado': 20,
              'total_notas_credito': noteAmount,
              'credito_aplicado': appliedCredit,
              'saldo_pendiente': debt / 100,
            },
          ];
  }

  @override
  Future<List<BalanceRow>> history(String id) async {
    if (failReads) throw StateError('Lectura fallida');
    return saved.values
        .map(
          (r) => {
            'id': r['cobro_id'],
            'importe': r['importe'],
            'medio_pago': r['medio_pago'],
            'fecha_pago': '2026-11-05T01:00:00Z',
            'observacion': r['observacion'],
          },
        )
        .toList();
  }

  @override
  Future<Object?> pay(String name, Map<String, dynamic> payload) async {
    if (!validSession || name != 'registrar_pago_cliente_contextual') {
      throw StateError('RPC no autorizada');
    }
    calls++;
    final id = payload['p_solicitud_id'] as String;
    final result = saved.putIfAbsent(id, () {
      final cents = ((payload['p_importe'] as num) * 100).round();
      debt -= cents;
      return {
        'solicitud_id': id,
        'actor_id': actor,
        'cliente_id': payload['p_cliente_id'],
        'operacion': 'cobro_cliente',
        'cobro_id': 'cash-$id',
        'importe': payload['p_importe'],
        'medio_pago': payload['p_medio_pago'],
        'observacion': payload['p_observacion'],
        'imputaciones': [
          {
            'pedido_id': 'old-order',
            'importe_aplicado': (cents ~/ 2) / 100,
            'saldo_restante': 0,
          },
          {
            'pedido_id': 'next-order',
            'importe_aplicado': (cents - cents ~/ 2) / 100,
            'saldo_restante': debt / 100,
          },
        ],
      };
    });
    if (loseResponse) {
      loseResponse = false;
      throw StateError('Respuesta perdida');
    }
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
