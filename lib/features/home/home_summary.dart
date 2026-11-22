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
    'at': at.toIso8601String(),
  };

  factory HomeSummary.fromJson(Map<String, dynamic> json, {bool cached = false}) => HomeSummary(
    toInvoice: json['facturar'] as int?,
    toDeliver: json['entregar'] as int?,
    tripOpen: json['viaje'] as bool?,
    tripSince: DateTime.tryParse(json['viaje_desde']?.toString() ?? ''),
    negatives: json['negativos'] as int?,
    weekOrders: json['semana'] as int?,
    at: DateTime.tryParse(json['at']?.toString() ?? '') ?? DateTime.now(),
    cached: cached,
  );

  /// Sin ningún dato (todo falló).
  bool get isEmpty =>
      toInvoice == null && toDeliver == null && tripOpen == null && negatives == null && weekOrders == null;
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
      negatives: results[3] as int?,
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
