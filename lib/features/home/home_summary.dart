import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_config.dart';
import '../stock/stock_data.dart';

/// Lo pendiente del día para la tarjeta "Hoy" del inicio. Cada número es null si no se pudo leer.
class HomeSummary {
  const HomeSummary({
    this.toInvoice,
    this.toDeliver,
    this.tripOpen,
    this.tripSince,
    this.negatives,
    this.weekOrders,
    this.salaryDue,
    this.envelopesDue,
    this.toReorder,
    required this.at,
    this.cached = false,
  });

  final int? toInvoice;
  final int? toDeliver;
  final bool? tripOpen;
  final DateTime? tripSince;
  final int? negatives;

  /// Preventista: sus pedidos de esta semana (desde el lunes).
  final int? weekOrders;

  /// Administración: el sueldo de la semana ya llegó (sábado) y no se pagó → importe; si no, null.
  final double? salaryDue;

  /// Administración, sábado o domingo: lo que falta poner en los sobres (null si nada).
  final double? envelopesDue;

  /// Productos "Para reponer".
  final int? toReorder;

  /// Cuándo se leyó.
  final DateTime at;

  /// true si es lo guardado de la última vez (sin señal).
  final bool cached;

  Map<String, dynamic> toJson() => {
    'facturar': toInvoice,
    'entregar': toDeliver,
    'viaje': tripOpen,
    'viaje_desde': tripSince?.toIso8601String(),
    'negativos': negatives,
    'semana': weekOrders,
    'sueldo': salaryDue,
    'sobres': envelopesDue,
    'reponer': toReorder,
    'at': at.toIso8601String(),
  };

  factory HomeSummary.fromJson(Map<String, dynamic> json, {bool cached = false}) => HomeSummary(
    toInvoice: json['facturar'] as int?,
    toDeliver: json['entregar'] as int?,
    tripOpen: json['viaje'] as bool?,
    tripSince: DateTime.tryParse(json['viaje_desde']?.toString() ?? ''),
    negatives: json['negativos'] as int?,
    weekOrders: json['semana'] as int?,
    salaryDue: (json['sueldo'] as num?)?.toDouble(),
    envelopesDue: (json['sobres'] as num?)?.toDouble(),
    toReorder: json['reponer'] as int?,
    at: DateTime.tryParse(json['at']?.toString() ?? '') ?? DateTime.now(),
    cached: cached,
  );

  /// Sin ningún dato (todo falló).
  bool get isEmpty =>
      toInvoice == null && toDeliver == null && tripOpen == null && negatives == null && weekOrders == null;
}

double? _salaryDue(Map<String, dynamic>? r) {
  final s = r?['sueldo'];
  return s is Map && s['pendiente'] == true ? stockNum(s['semanal']) : null;
}

double? _envelopesDue(Map<String, dynamic>? r) {
  if (r == null || r['fin_de_semana'] != true) return null;
  final v = stockNum(r['poner']);
  return v > 0 ? v : null;
}

String get _cacheKey => appConfig.localPreferenceKey('inicio_resumen');

Future<int?> _count(Future<int> Function() read) async {
  try {
    return await read();
  } catch (_) {
    return null;
  }
}

/// Lee los números del inicio. Sin señal devuelve lo de la última vez (marcado como guardado).
Future<HomeSummary> fetchHomeSummary(SupabaseClient client, {required bool admin, String? userId}) async {
  final now = DateTime.now();
  HomeSummary summary;
  if (admin) {
    final results = await Future.wait<Object?>([
      _count(() async {
        final r = await client
            .from('pedidos')
            .select('id')
            .eq('facturado', false)
            .eq('tipo_operacion', 'pedido')
            .count(CountOption.exact);
        return r.count;
      }),
      _count(() async {
        final r = await client
            .from('pedidos')
            .select('id')
            .eq('resultado_entrega', 'pendiente')
            .eq('tipo_operacion', 'pedido')
            .eq('facturado', true)
            .count(CountOption.exact);
        return r.count;
      }),
      () async {
        try {
          return await fetchVehicleStock(client);
        } catch (_) {
          return null;
        }
      }(),
      () async {
        try {
          final Object? r = await client.rpc('fin_sabado_estado', params: const {}, get: true);
          if (r is Map) return Map<String, dynamic>.from(r);
        } catch (_) {}
        return null;
      }(),
      _count(() async {
        final List<dynamic> rows = await client.rpc('stock_reponer', params: const {'p_todos': false}, get: true);
        return rows.length;
      }),
      _count(() async {
        final List<dynamic> estado = await client.rpc('stock_estado', params: const {}, get: true);
        return estado.where((raw) {
          final row = raw as Map;
          return row['control_stock'] == true && (stockNum(row['deposito']) < 0 || stockNum(row['vehiculo']) < 0);
        }).length;
      }),
    ]);
    final vehicle = results[2] as VehicleStock?;
    summary = HomeSummary(
      toInvoice: results[0] as int?,
      toDeliver: results[1] as int?,
      tripOpen: vehicle?.tripOpen,
      tripSince: vehicle?.openedAt,
      negatives: results[5] as int?,
      toReorder: results[4] as int?,
      salaryDue: _salaryDue(results[3] as Map<String, dynamic>?),
      envelopesDue: _envelopesDue(results[3] as Map<String, dynamic>?),
      at: now,
    );
  } else {
    final monday = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    summary = HomeSummary(
      weekOrders: userId == null
          ? null
          : await _count(() async {
              final r = await client
                  .from('pedidos')
                  .select('id')
                  .eq('preventista_id', userId)
                  .gte('created_at', monday.toUtc().toIso8601String())
                  .neq('estado', 'anulado')
                  .count(CountOption.exact);
              return r.count;
            }),
      at: now,
    );
  }
  try {
    final prefs = await SharedPreferences.getInstance();
    if (summary.isEmpty) {
      final raw = prefs.getString(_cacheKey);
      if (raw != null) {
        return HomeSummary.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map), cached: true);
      }
    } else {
      await prefs.setString(_cacheKey, jsonEncode(summary.toJson()));
    }
  } catch (_) {}
  return summary;
}
