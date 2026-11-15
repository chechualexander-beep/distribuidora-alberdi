import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_config.dart';

/// Facturación en una sola operación del servidor (`facturar_pedido`).
///
/// Antes de enviar, la solicitud se guarda en el equipo con un identificador propio.
/// Si internet se corta y no se sabe si llegó, se reenvía la MISMA solicitud: el servidor
/// devuelve el mismo comprobante y nunca factura dos veces ni deja el pedido a medias.
class PendingInvoice {
  const PendingInvoice(this.requestId, this.originals, this.added);
  final String requestId;
  final List<Map<String, dynamic>> originals;
  final List<Map<String, dynamic>> added;

  Map<String, dynamic> toJson() => {
    'solicitud_id': requestId,
    'originales': originals,
    'agregados': added,
  };

  static PendingInvoice? fromJson(String? text) {
    if (text == null) return null;
    try {
      final json = jsonDecode(text) as Map<String, dynamic>;
      return PendingInvoice(
        json['solicitud_id'] as String,
        List<Map<String, dynamic>>.from(json['originales'] as List),
        List<Map<String, dynamic>>.from(json['agregados'] as List),
      );
    } catch (_) {
      return null;
    }
  }
}

/// UUID v4 aleatorio (identifica cada intento de facturación).
String newInvoiceRequestId([Random? random]) {
  final r = random ?? Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

class InvoiceResult {
  const InvoiceResult(this.number, this.date);
  final String number;
  final String date;
}

/// La respuesta no llegó (corte, demora o caída del servidor): puede haberse facturado o no.
/// Se conserva la solicitud para reintentarla igual.
class UncertainInvoiceException implements Exception {
  const UncertainInvoiceException();
}

/// Errores de red o de puerta de enlace, en los que el servidor pudo no haber respondido.
bool isUncertainInvoiceError(Object error) {
  if (error is TimeoutException ||
      error is SocketException ||
      error is HttpException) {
    return true;
  }
  if (error is PostgrestException) {
    final code = error.code ?? '';
    return code.isEmpty ||
        RegExp(r'^5\d\d$').hasMatch(code) ||
        code == '408' ||
        code == '429' ||
        code.startsWith('PGRST00');
  }
  // Errores del cliente HTTP (conexión cerrada, DNS, etc.).
  final name = error.runtimeType.toString();
  return name.contains('ClientException') || name.contains('Handshake');
}

class AtomicInvoiceStore {
  AtomicInvoiceStore(this._prefs);
  final SharedPreferences _prefs;

  static Future<AtomicInvoiceStore> open() async =>
      AtomicInvoiceStore(await SharedPreferences.getInstance());

  String _key(String orderId) =>
      appConfig.localPreferenceKey('facturacion_pendiente:$orderId');

  PendingInvoice? read(String orderId) =>
      PendingInvoice.fromJson(_prefs.getString(_key(orderId)));

  Future<void> save(String orderId, PendingInvoice pending) =>
      _prefs.setString(_key(orderId), jsonEncode(pending.toJson()));

  Future<void> clear(String orderId) => _prefs.remove(_key(orderId));
}

Future<InvoiceResult> sendAtomicInvoice(
  SupabaseClient client,
  String orderId,
  PendingInvoice pending, {
  Duration timeout = const Duration(seconds: 25),
}) async {
  try {
    final response = await client
        .rpc(
          'facturar_pedido',
          params: {
            'p_solicitud_id': pending.requestId,
            'p_pedido_id': orderId,
            'p_originales': pending.originals,
            'p_agregados': pending.added,
          },
        )
        .timeout(timeout);
    final result = Map<String, dynamic>.from(response as Map);
    return InvoiceResult(
      result['numero_comprobante'].toString(),
      result['fecha_facturacion'].toString(),
    );
  } catch (error) {
    if (isUncertainInvoiceError(error)) throw const UncertainInvoiceException();
    rethrow;
  }
}
