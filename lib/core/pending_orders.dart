import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';
import 'network_status.dart';

/// Pedido o venta directa confirmado sin señal: queda guardado en el teléfono y se envía solo.
class PendingOrder {
  PendingOrder({
    required this.params,
    required this.clientName,
    required this.total,
    required this.createdAt,
    this.rejected,
  });

  /// Parámetros exactos de `crear_pedido_sin_conexion` (incluye p_id: reenviar no duplica).
  final Map<String, dynamic> params;
  final String clientName;
  final double total;
  final DateTime createdAt;

  /// Motivo si el servidor lo rechazó (por ejemplo, cambió un precio hace más de 3 días).
  String? rejected;

  String get id => params['p_id'].toString();
  bool get isDirectSale => params['p_tipo_operacion'] == 'venta_directa';

  Map<String, dynamic> toJson() => {
    'params': params,
    'cliente': clientName,
    'total': total,
    'creado': createdAt.toUtc().toIso8601String(),
    if (rejected != null) 'rechazado': rejected,
  };

  static PendingOrder fromJson(Map<String, dynamic> json) => PendingOrder(
    params: Map<String, dynamic>.from(json['params'] as Map),
    clientName: json['cliente']?.toString() ?? 'Cliente',
    total: (json['total'] as num?)?.toDouble() ?? 0,
    createdAt: DateTime.tryParse(json['creado']?.toString() ?? '') ?? DateTime.now(),
    rejected: json['rechazado']?.toString(),
  );
}

typedef SendOrder = Future<void> Function(Map<String, dynamic> params);

/// Cola de pedidos sin enviar, por usuario. Se envía sola: al iniciar, cuando vuelve la
/// conexión y cada 2 minutos mientras haya pendientes.
class PendingOrders {
  PendingOrders._();
  static final instance = PendingOrders._();

  final items = ValueNotifier<List<PendingOrder>>(const []);
  final sending = ValueNotifier<bool>(false);
  String? _uid;
  SendOrder? _send;
  Timer? _timer;
  bool _listening = false;
  // Si se pide enviar mientras ya se está enviando (por ejemplo, volvió la señal justo en ese
  // momento), se repite apenas termine en vez de esperar al próximo intento.
  bool _again = false;

  String _key(String uid) => appConfig.localPreferenceKey('pedidos_sin_enviar:$uid');

  /// Arranca para el usuario de la sesión. [send] se puede reemplazar en pruebas.
  Future<void> start(SupabaseClient client, {SendOrder? send}) async {
    final uid = client.auth.currentUser?.id;
    if (uid == null) return;
    _uid = uid;
    _send =
        send ??
        (params) => client
            .rpc('crear_pedido_sin_conexion', params: params)
            .timeout(const Duration(seconds: 25));
    await _load();
    if (!_listening) {
      _listening = true;
      connectionProblem.addListener(_onConnection);
    }
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 2), (_) => sendAll());
    unawaited(sendAll());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    if (_listening) connectionProblem.removeListener(_onConnection);
    _listening = false;
    _again = false;
    _uid = null;
    items.value = const [];
  }

  void _onConnection() {
    if (!connectionProblem.value) unawaited(sendAll());
  }

  Future<void> _load() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(uid));
      final list = raw == null ? const [] : jsonDecode(raw) as List;
      items.value = [
        for (final e in list) PendingOrder.fromJson(Map<String, dynamic>.from(e as Map)),
      ];
    } catch (_) {
      items.value = const [];
    }
  }

  Future<void> _save() async {
    final uid = _uid;
    if (uid == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key(uid),
      jsonEncode([for (final o in items.value) o.toJson()]),
    );
  }

  Future<void> add(PendingOrder order, {String? uid}) async {
    _uid ??= uid;
    items.value = [
      ...items.value.where((o) => o.id != order.id),
      order,
    ];
    await _save();
  }

  Future<void> discard(String id) async {
    items.value = items.value.where((o) => o.id != id).toList();
    await _save();
  }

  /// Envía los pendientes (no los rechazados). Devuelve cuántos se enviaron.
  Future<int> sendAll() async {
    final send = _send;
    if (send == null) return 0;
    if (sending.value) {
      _again = true;
      return 0;
    }
    final queue = items.value.where((o) => o.rejected == null).toList();
    if (queue.isEmpty) return 0;
    sending.value = true;
    var sent = 0;
    try {
      for (final order in queue) {
        try {
          await send(order.params);
          items.value = items.value.where((o) => o.id != order.id).toList();
          sent++;
        } catch (error) {
          if (isUncertainRequestError(error)) break; // sin señal: se reintenta más tarde
          order.rejected = error is PostgrestException ? error.message : error.toString();
          items.value = [...items.value];
        }
        await _save();
      }
    } finally {
      sending.value = false;
    }
    if (_again) {
      _again = false;
      sent += await sendAll();
    }
    return sent;
  }
}
