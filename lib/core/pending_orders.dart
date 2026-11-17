import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';
import 'network_status.dart';

/// Pedido, venta directa o cliente nuevo hecho sin señal: queda guardado en el teléfono y
/// se envía solo.
class PendingOrder {
  PendingOrder({
    required this.params,
    required this.clientName,
    required this.total,
    required this.createdAt,
    this.rejected,
    this.kind = orderKind,
  });

  static const orderKind = 'pedido';
  static const clientKind = 'cliente';
  static const stockKind = 'stock';

  /// Operación de stock (compra, carga o bajada del vehículo, conteo, cierre de viaje):
  /// [rpc] y sus parámetros exactos, con `p_id` y la hora real (`p_fecha`).
  factory PendingOrder.stock({
    required String rpc,
    required Map<String, dynamic> args,
    required String description,
    double total = 0,
    DateTime? createdAt,
  }) => PendingOrder(
    params: {'rpc': rpc, 'args': args},
    clientName: description,
    total: total,
    createdAt: createdAt ?? DateTime.now(),
    kind: stockKind,
  );

  /// Cliente nuevo: [params] es la fila completa de `clientes` con su `id` ya elegido en el
  /// teléfono, así los pedidos sin señal lo pueden usar antes de que llegue al servidor.
  factory PendingOrder.client(Map<String, dynamic> row, {DateTime? createdAt}) => PendingOrder(
    params: row,
    clientName: row['nombre_comercio']?.toString() ?? 'Cliente nuevo',
    total: 0,
    createdAt: createdAt ?? DateTime.now(),
    kind: clientKind,
  );

  /// Pedido: parámetros exactos de `crear_pedido_sin_conexion` (incluye p_id: reenviar no
  /// duplica). Cliente: la fila a insertar.
  final Map<String, dynamic> params;
  final String kind;
  final String clientName;
  final double total;
  final DateTime createdAt;

  /// Motivo si el servidor lo rechazó (por ejemplo, cambió un precio hace más de 3 días).
  String? rejected;

  bool get isClient => kind == clientKind;
  bool get isStock => kind == stockKind;
  String get id => (isClient
          ? params['id']
          : isStock
          ? (params['args'] as Map)['p_id']
          : params['p_id'])
      .toString();

  /// Cliente del pedido (o el propio cliente nuevo).
  String? get clientId =>
      isStock ? null : (isClient ? params['id'] : params['p_cliente_id'])?.toString();
  bool get isDirectSale => params['p_tipo_operacion'] == 'venta_directa';

  Map<String, dynamic> toJson() => {
    'params': params,
    'cliente': clientName,
    'total': total,
    'creado': createdAt.toUtc().toIso8601String(),
    if (rejected != null) 'rechazado': rejected,
    if (kind != orderKind) 'tipo': kind,
  };

  static PendingOrder fromJson(Map<String, dynamic> json) => PendingOrder(
    params: Map<String, dynamic>.from(json['params'] as Map),
    clientName: json['cliente']?.toString() ?? 'Cliente',
    total: (json['total'] as num?)?.toDouble() ?? 0,
    createdAt: DateTime.tryParse(json['creado']?.toString() ?? '') ?? DateTime.now(),
    rejected: json['rechazado']?.toString(),
    kind: json['tipo']?.toString() ?? orderKind,
  );
}

typedef SendOrder = Future<void> Function(Map<String, dynamic> params);

/// Alta de un cliente nuevo con su id elegido en el teléfono. Si un intento anterior llegó
/// pero no la respuesta, el servidor contesta "ya existe" (23505): eso cuenta como enviado.
Future<void> insertPendingClient(SupabaseClient client, Map<String, dynamic> row) async {
  try {
    await client.from('clientes').insert(row).timeout(const Duration(seconds: 25));
  } on PostgrestException catch (error) {
    if (error.code == '23505') return;
    rethrow;
  }
}

/// Cola de pedidos sin enviar, por usuario. Se envía sola: al iniciar, al volver a la app,
/// cuando otra pantalla detecta que volvió la conexión y cada 30 segundos mientras haya
/// pendientes (sin señal el intento falla al instante: casi no gasta batería ni datos).
class PendingOrders {
  PendingOrders._();
  static final instance = PendingOrders._();

  final items = ValueNotifier<List<PendingOrder>>(const []);
  final sending = ValueNotifier<bool>(false);
  String? _uid;
  SendOrder? _send;
  SendOrder? _sendClient;
  SendOrder? _sendStock;
  Timer? _timer;
  AppLifecycleListener? _lifecycle;
  bool _listening = false;
  static const retryEvery = Duration(seconds: 30);
  // Si se pide enviar mientras ya se está enviando (por ejemplo, volvió la señal justo en ese
  // momento), se repite apenas termine en vez de esperar al próximo intento.
  bool _again = false;

  String _key(String uid) => appConfig.localPreferenceKey('pedidos_sin_enviar:$uid');

  /// Arranca para el usuario de la sesión. [send] se puede reemplazar en pruebas.
  Future<void> start(
    SupabaseClient client, {
    SendOrder? send,
    SendOrder? sendClient,
    SendOrder? sendStock,
  }) async {
    final uid = client.auth.currentUser?.id;
    if (uid == null) return;
    _uid = uid;
    _send =
        send ??
        (params) => client
            .rpc('crear_pedido_sin_conexion', params: params)
            .timeout(const Duration(seconds: 25));
    _sendClient = sendClient ?? (row) => insertPendingClient(client, row);
    _sendStock =
        sendStock ??
        (p) => client
            .rpc(p['rpc'] as String, params: Map<String, dynamic>.from(p['args'] as Map))
            .timeout(const Duration(seconds: 25));
    await _load();
    if (!_listening) {
      _listening = true;
      connectionProblem.addListener(_onConnection);
    }
    _timer?.cancel();
    _timer = Timer.periodic(retryEvery, (_) {
      if (items.value.any((o) => o.rejected == null)) unawaited(sendAll());
    });
    _lifecycle ??= AppLifecycleListener(onResume: () => unawaited(sendAll()));
    unawaited(sendAll());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _lifecycle?.dispose();
    _lifecycle = null;
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

  /// Descarta un pendiente. Si es un cliente nuevo, también sus pedidos (sin el cliente no
  /// se pueden cargar).
  Future<void> discard(String id) async {
    final client = items.value.where((o) => o.isClient && o.id == id).isNotEmpty;
    items.value = items.value
        .where((o) => o.id != id && !(client && !o.isClient && o.clientId == id))
        .toList();
    await _save();
  }

  /// Clientes nuevos guardados en el teléfono que todavía no llegaron al servidor.
  List<Map<String, dynamic>> get pendingClients => [
    for (final o in items.value)
      if (o.isClient) {...o.params, sinEnviarKey: true},
  ];

  bool isPendingClient(String? id) =>
      id != null && items.value.any((o) => o.isClient && o.id == id);

  Map<String, dynamic>? pendingClient(String? id) {
    for (final c in pendingClients) {
      if (c['id']?.toString() == id) return c;
    }
    return null;
  }

  /// Pedidos guardados de un cliente nuevo.
  int ordersOf(String id) =>
      items.value.where((o) => !o.isClient && o.clientId == id).length;

  /// Marca que se agrega a la fila de un cliente sin enviar (nunca se manda al servidor).
  static const sinEnviarKey = '_sin_enviar';

  /// Envía los pendientes (no los rechazados): primero los clientes nuevos y después los
  /// pedidos; un pedido de un cliente que todavía no llegó espera. Devuelve cuántos se enviaron.
  Future<int> sendAll() async {
    final send = _send;
    if (send == null) return 0;
    if (sending.value) {
      _again = true;
      return 0;
    }
    final waiting = items.value.where((o) => o.rejected == null);
    final queue = [...waiting.where((o) => o.isClient), ...waiting.where((o) => !o.isClient)];
    if (queue.isEmpty) return 0;
    sending.value = true;
    var sent = 0;
    try {
      for (final order in queue) {
        if (!order.isClient && isPendingClient(order.clientId)) continue;
        try {
          if (order.isClient) {
            await (_sendClient ?? send)(order.params);
          } else if (order.isStock) {
            final sendStock = _sendStock;
            if (sendStock == null) break;
            await sendStock(order.params);
          } else {
            await send(order.params);
          }
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
