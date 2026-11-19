import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/network_status.dart';
import '../../core/pending_orders.dart';
import '../invoicing/atomic_invoice.dart' show newInvoiceRequestId;

// Datos y operaciones del stock nuevo (por producto, depósito + vehículo). Ver docs/STOCK.md.

typedef StockRow = Map<String, dynamic>;

const depositoCodigo = 'deposito_alberdi';
const vehiculoCodigo = 'vehiculo';

double stockNum(Object? value) =>
    value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '') ?? 0;

/// 12 → "12", 2.5 → "2,5".
String formatQty(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  var text = value.toStringAsFixed(3);
  while (text.endsWith('0')) {
    text = text.substring(0, text.length - 1);
  }
  return text.replaceAll('.', ',');
}

/// "12", "2,5" o "2.5" → número; vacío o inválido → null.
double? parseQty(String text) {
  final clean = text.trim().replaceAll(',', '.');
  if (clean.isEmpty) return null;
  final value = double.tryParse(clean);
  if (value == null || value < 0 || value.isNaN || value.isInfinite) return null;
  return (value * 1000).round() / 1000;
}

class VehicleLine {
  const VehicleLine(this.inVehicle, this.committed, [this.reparto = 0]);
  final double inVehicle;

  /// Comprometido: vendido en el viaje sin entregar + pedidos del reparto sin entregar.
  final double committed;

  /// De eso, lo de los pedidos facturados del reparto.
  final double reparto;

  /// Ventas directas del viaje sin entregar.
  double get sold => committed - reparto;
  double get available => inVehicle - committed;
}

/// Lo que lleva el vehículo (lo puede ver el preventista).
class VehicleStock {
  const VehicleStock({
    this.tripId,
    this.openedAt,
    this.sellerId,
    this.lines = const {},
  });

  final String? tripId;
  final DateTime? openedAt;
  final String? sellerId;
  final Map<String, VehicleLine> lines;

  bool get tripOpen => tripId != null;

  static VehicleStock fromJson(Map<String, dynamic> json) {
    final trip = json['viaje'] is Map ? Map<String, dynamic>.from(json['viaje'] as Map) : null;
    final lines = <String, VehicleLine>{};
    for (final raw in (json['productos'] as List? ?? const [])) {
      final row = Map<String, dynamic>.from(raw as Map);
      lines[row['producto_id'].toString()] = VehicleLine(
        stockNum(row['en_vehiculo']),
        stockNum(row['comprometido']),
        stockNum(row['reparto']),
      );
    }
    return VehicleStock(
      tripId: trip?['id']?.toString(),
      openedAt: DateTime.tryParse(trip?['abierto_at']?.toString() ?? ''),
      sellerId: trip?['preventista_id']?.toString(),
      lines: lines,
    );
  }
}

/// Por GET: queda en la copia del teléfono y se ve aunque se corte la señal.
Future<VehicleStock> fetchVehicleStock(SupabaseClient client) async {
  final result = await client.rpc('stock_vehiculo_disponible', params: const {}, get: true);
  return VehicleStock.fromJson(Map<String, dynamic>.from(result as Map));
}

/// Una fila por producto activo: con stock / a pedido, depósito y vehículo.
class StockItem {
  StockItem({
    required this.id,
    required this.name,
    required this.code,
    required this.category,
    required this.photo,
    required this.controlled,
    required this.deposit,
    required this.vehicle,
    this.parentId,
    this.unitsPerParent,
    this.cost = 0,
  });

  final String id;
  final String name;
  final String code;
  final String category;
  final String? photo;
  final bool controlled;
  final double deposit;
  final double vehicle;

  /// Fraccionado: sale de [parentId] (1 de ese → [unitsPerParent] de este).
  final String? parentId;
  final double? unitsPerParent;

  /// Costo actual del producto (para precargar la compra); 0 si no se sabe.
  final double cost;

  /// Lo que hay entre depósito y vehículo.
  double get total => deposit + vehicle;

  bool get negative => controlled && (deposit < 0 || vehicle < 0);

  /// Lo mismo con otras cantidades (para comparar contra una parte del stock).
  StockItem withStock({required double deposit, required double vehicle}) => StockItem(
    id: id,
    name: name,
    code: code,
    category: category,
    photo: photo,
    controlled: controlled,
    deposit: deposit,
    vehicle: vehicle,
    parentId: parentId,
    unitsPerParent: unitsPerParent,
    cost: cost,
  );

  /// Solo el depósito (para ver si alcanza al cargar el vehículo).
  StockItem depositOnly() => withStock(deposit: deposit, vehicle: 0);

  /// Solo lo que ya está arriba del vehículo.
  StockItem vehicleOnly() => withStock(deposit: 0, vehicle: vehicle);
}

Future<List<StockItem>> fetchStockItems(SupabaseClient client) async {
  final products = List<StockRow>.from(
    await client
        .from('productos')
        .select('id,codigo,nombre,categoria,foto_path')
        .eq('activo', true)
        .order('nombre'),
  );
  final List<dynamic> estado = await client.rpc('stock_estado', params: const {}, get: true);
  // Costos (solo administración): precargan "Anotar compra". Sin ellos sigue igual.
  final costs = <String, double>{};
  try {
    final rows = await client.from('productos_administracion').select('id,costo').eq('activo', true);
    for (final r in List<StockRow>.from(rows)) {
      costs[r['id'].toString()] = stockNum(r['costo']);
    }
  } catch (_) {}
  final state = <String, StockRow>{
    for (final raw in estado)
      (raw as Map)['producto_id'].toString(): Map<String, dynamic>.from(raw),
  };
  return [
    for (final p in products)
      StockItem(
        id: p['id'].toString(),
        name: p['nombre']?.toString() ?? 'Producto',
        code: p['codigo']?.toString() ?? '',
        category: (p['categoria']?.toString().trim().isNotEmpty ?? false)
            ? p['categoria'].toString().trim()
            : 'Sin categoría',
        photo: p['foto_path']?.toString(),
        controlled: state[p['id'].toString()]?['control_stock'] == true,
        deposit: stockNum(state[p['id'].toString()]?['deposito']),
        vehicle: stockNum(state[p['id'].toString()]?['vehiculo']),
        parentId: state[p['id'].toString()]?['fracciona_de']?.toString(),
        unitsPerParent: state[p['id'].toString()]?['unidades_por_origen'] == null
            ? null
            : stockNum(state[p['id'].toString()]?['unidades_por_origen']),
        cost: costs[p['id'].toString()] ?? 0,
      ),
  ];
}

/// Ordena para que cada suelto quede justo debajo de su cerrado. Con [addLoose] también suma
/// los sueltos de un cerrado visible que el filtro dejó afuera (por ejemplo, al contar).
List<StockItem> pairLooseWithClosed(
  List<StockItem> visible,
  List<StockItem> all, {
  bool addLoose = false,
}) {
  final ids = {for (final i in visible) i.id};
  final childrenOf = <String, List<StockItem>>{};
  for (final i in all) {
    final parent = i.parentId;
    if (parent != null && ids.contains(parent) && (addLoose || ids.contains(i.id))) {
      childrenOf.putIfAbsent(parent, () => []).add(i);
    }
  }
  final placed = <String>{};
  final out = <StockItem>[];
  for (final i in visible) {
    if (i.parentId != null && ids.contains(i.parentId)) continue; // va debajo de su cerrado
    if (!placed.add(i.id)) continue;
    out.add(i);
    for (final c in childrenOf[i.id] ?? const <StockItem>[]) {
      if (placed.add(c.id)) out.add(c);
    }
  }
  return out;
}

/// "10 cerrados + 2 sueltos = 52 × Papas Facu x 1 kg".
String looseSummary(StockItem closed, StockItem loose) {
  final units = loose.unitsPerParent ?? 0;
  return '${formatQty(closed.total)} cerrados + ${formatQty(loose.total)} sueltos = '
      '${formatQty(closed.total * units + loose.total)} × ${loose.name}';
}

/// Productos de los pedidos facturados que todavía hay que entregar (para proponer la carga).
Future<Map<String, double>> fetchPendingDeliveries(SupabaseClient client) async {
  final rows = await client
      .from('pedido_detalles')
      .select('producto_id,cantidad,cantidad_facturada,pedidos!inner(resultado_entrega,facturado,tipo_operacion,estado)')
      .eq('pedidos.resultado_entrega', 'pendiente')
      .eq('pedidos.facturado', true)
      .eq('pedidos.tipo_operacion', 'pedido')
      .neq('pedidos.estado', 'anulado');
  final totals = <String, double>{};
  for (final r in List<StockRow>.from(rows)) {
    final q = stockNum(r['cantidad_facturada'] ?? r['cantidad']);
    if (q <= 0) continue;
    final id = r['producto_id'].toString();
    totals[id] = (totals[id] ?? 0) + q;
  }
  return totals;
}

/// Lo comprometido y todavía sin entregar: pedidos facturados del reparto y ventas directas del
/// viaje. Si no se puede consultar (sin permiso o sin señal), lo que se pudo.
Future<Map<String, double>> fetchCommitted(SupabaseClient client) async {
  final totals = <String, double>{};
  try {
    totals.addAll(await fetchPendingDeliveries(client));
  } catch (_) {}
  try {
    final vehicle = await fetchVehicleStock(client);
    for (final e in vehicle.lines.entries) {
      // Solo las ventas directas: lo del reparto ya viene en los pedidos a entregar.
      if (e.value.sold > 0) totals[e.key] = (totals[e.key] ?? 0) + e.value.sold;
    }
  } catch (_) {}
  return totals;
}

/// Lo que se cargó la última vez en el vehículo.
Future<Map<String, double>> fetchLastLoad(SupabaseClient client) async {
  final last = await client
      .from('stock_operaciones')
      .select('id')
      .eq('tipo', 'carga_vehiculo')
      .order('fecha_fisica', ascending: false)
      .limit(1)
      .maybeSingle();
  if (last == null) return {};
  final rows = await client
      .from('stock_operacion_items')
      .select('producto_id,cantidad')
      .eq('operacion_id', last['id']);
  return {
    for (final r in List<StockRow>.from(rows)) r['producto_id'].toString(): stockNum(r['cantidad']),
  };
}

/// Preventistas activos (para elegir con quién sale el viaje).
Future<List<StockRow>> fetchSellers(SupabaseClient client) async => List<StockRow>.from(
  await client
      .from('usuarios')
      .select('id,nombre,apellido')
      .eq('rol', 'preventista')
      .eq('activo', true)
      .order('nombre'),
);

/// Resultado de una operación: [result] del servidor, o null si quedó guardada sin señal.
class StockOpOutcome {
  const StockOpOutcome(this.result);
  final Map<String, dynamic>? result;
  bool get savedOffline => result == null;
}

/// Para las pruebas: reemplaza el envío al servidor.
typedef StockOpRunner = Future<StockOpOutcome> Function(String rpc, Map<String, dynamic> args);

/// Hace la operación con un id elegido acá y la hora real. Sin señal queda en
/// "Pendientes de enviar" y se envía sola (reenviar no duplica).
Future<StockOpOutcome> runStockOp(
  SupabaseClient client, {
  required String rpc,
  required Map<String, dynamic> args,
  required String description,
  double total = 0,
}) async {
  final full = <String, dynamic>{
    'p_id': newInvoiceRequestId(),
    'p_fecha': DateTime.now().toUtc().toIso8601String(),
    ...args,
  };
  try {
    final result = await client.rpc(rpc, params: full).timeout(const Duration(seconds: 20));
    return StockOpOutcome(Map<String, dynamic>.from(result as Map));
  } catch (error) {
    if (!isUncertainRequestError(error)) rethrow;
    await PendingOrders.instance.add(
      PendingOrder.stock(rpc: rpc, args: full, description: description, total: total),
      uid: client.auth.currentUser?.id,
    );
    return const StockOpOutcome(null);
  }
}

/// Mensaje claro para un error del servidor.
String stockErrorText(Object error) {
  if (error is PostgrestException) return error.message;
  if (error is TimeoutException) return 'Sin respuesta del servidor. Probá de nuevo.';
  final detail = error.toString();
  return 'No se pudo completar (${detail.length > 160 ? detail.substring(0, 160) : detail}).';
}
