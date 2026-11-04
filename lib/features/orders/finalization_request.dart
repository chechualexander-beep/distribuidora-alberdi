import 'dart:convert';
import 'dart:math';

import '../../core/app_config.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One immutable operational request, scoped by project and authenticated actor.
/// No names, credentials, tokens or calculated commercial results are stored.
class FinalizationRequestStore {
  FinalizationRequestStore(this.preferences, this.projectUrl, this.actorId);

  final SharedPreferences preferences;
  final String projectUrl;
  final String actorId;
  String get _prefix =>
      'preventa_v1:${Uri.encodeComponent(projectUrl)}:$actorId:';
  String _key(String orderId) => '$_prefix$orderId';

  Map<String, dynamic>? read(String orderId) {
    final raw = preferences.getString(_key(orderId));
    if (raw == null) return null;
    // Corrupt persistence must block a new request instead of silently duplicating.
    final payload = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    if (payload['p_pedido_id'] != orderId ||
        payload['p_solicitud_id'] is! String ||
        DateTime.tryParse(payload['p_fecha_fisica']?.toString() ?? '') ==
            null) {
      throw const FormatException('Solicitud pendiente inválida');
    }
    return payload;
  }

  List<String> get pendingOrderIds => preferences
      .getKeys()
      .where((key) => key.startsWith(_prefix))
      .map((key) => key.substring(_prefix.length))
      .toList();

  Future<Map<String, dynamic>> prepare(
    String orderId,
    Map<String, dynamic> input, {
    DateTime? physicalDate,
  }) async {
    final existing = read(orderId);
    if (existing != null) return existing;
    const allowed = {
      'p_estado',
      'p_originales',
      'p_agregados',
      'p_tipo_pago',
      'p_motivo_no_entrega',
      'p_importe_pago',
      'p_medio_pago',
    };
    if (input.keys.any((key) => !allowed.contains(key))) {
      throw ArgumentError('La solicitud contiene campos no operativos');
    }
    final payload = <String, dynamic>{
      ...input,
      'p_pedido_id': orderId,
      'p_solicitud_id': _uuid(),
      'p_fecha_fisica': (physicalDate ?? DateTime.now())
          .toUtc()
          .toIso8601String(),
    };
    // Serialize before returning: callers cannot mutate the durable retry payload.
    if (!await preferences.setString(_key(orderId), jsonEncode(payload))) {
      throw StateError('No se pudo conservar la solicitud');
    }
    return read(orderId)!;
  }

  Future<void> clear(String orderId) async {
    if (!await preferences.remove(_key(orderId))) {
      throw StateError('No se pudo cerrar la solicitud local');
    }
  }

  static String _uuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}

Future<FinalizationRequestStore> finalizationStore(
  SupabaseClient client,
) async {
  appConfig.requireV2Client(client.rest.url);
  final actor = client.auth.currentUser?.id;
  if (actor == null) throw StateError('Sesión requerida');
  return FinalizationRequestStore(
    await SharedPreferences.getInstance(),
    client.rest.url,
    actor,
  );
}

/// A missing committed row does not prove that an in-flight transaction aborted.
/// Retry always submits the same durable parameters.
Future<Map<String, dynamic>> reconcileFinalization(
  SupabaseClient client,
  Map<String, dynamic> payload, {
  bool retry = false,
  AppConfig? config,
}) async {
  (config ?? appConfig).requireV2Client(client.rest.url);
  final status = Map<String, dynamic>.from(
    await client.rpc(
          'consultar_finalizacion_solicitud',
          params: {'p_solicitud_id': payload['p_solicitud_id']},
        )
        as Map,
  );
  if (status['estado'] == 'confirmada') {
    return Map<String, dynamic>.from(status['resultado'] as Map);
  }
  if (!retry) return status;
  if (status['estado'] != 'inexistente') {
    throw StateError('Respuesta de recuperación no reconocida.');
  }
  return Map<String, dynamic>.from(
    await client.rpc('finalizar_gestion_pedido_v2', params: payload) as Map,
  );
}

String finalizationErrorMessage(PostgrestException error) {
  final detail = '${error.details ?? ''} ${error.message}'.toLowerCase();
  if (detail.contains('stock_insuficiente') ||
      detail.contains('stock insuficiente')) {
    return 'Stock insuficiente. Revisá las cantidades antes de entregar.';
  }
  if (detail.contains('no inicializado') ||
      detail.contains('stock_no_inicializado')) {
    return 'El producto todavía no tiene stock inicial. Consultá al administrador.';
  }
  if (detail.contains('solicitud_incompatible')) {
    return 'Esta solicitud ya tiene otro contenido. Revisá su resultado; no crees otra.';
  }
  if (detail.contains('actualizacion_requerida')) {
    return 'Actualizá la aplicación para continuar con esta operación.';
  }
  if (detail.contains('operacion_ya_finalizada')) {
    return 'El pedido ya fue finalizado. Revisá la operación guardada.';
  }
  if (error.code == 'PT422') {
    return 'Revisá cantidades, facturación, motivo y pago. La gestión no se guardó.';
  }
  return 'No se pudo confirmar la gestión. La solicitud se conserva para revisar o reintentar.';
}
