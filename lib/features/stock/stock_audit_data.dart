import 'package:supabase_flutter/supabase_flutter.dart';

import 'stock_data.dart';

/// Motivos de una diferencia en la liquidación del viaje (código → texto).
const settlementReasons = <String, String>{
  'rotura': 'Rotura',
  'regalo_muestra': 'Regalo o muestra',
  'error_carga': 'Error de carga',
  'vencido': 'Vencido',
  'faltante': 'Faltante sin explicar',
  'otro': 'Otro',
};

DateTime? _date(Object? v) => DateTime.tryParse(v?.toString() ?? '')?.toLocal();

/// Una fila de la liquidación: la cuenta de un producto en el viaje.
class SettlementRow {
  const SettlementRow({
    required this.productId,
    required this.name,
    this.had = 0,
    this.loaded = 0,
    this.fromDeposit = 0,
    this.sold = 0,
    this.returned = 0,
    this.unloaded = 0,
    this.other = 0,
    this.expected = 0,
    this.counted,
    this.difference = 0,
    this.unloadedAtClose = 0,
    this.reason,
    this.note,
  });

  final String productId;
  final String name;

  /// Tenía al salir.
  final double had;

  /// Cargas, recargas y compras que entraron al vehículo.
  final double loaded;

  /// Tomado del depósito (correcciones automáticas o "descontar del depósito").
  final double fromDeposit;
  final double sold;
  final double returned;

  /// Bajadas al depósito durante el viaje (no la del cierre).
  final double unloaded;

  /// Lo demás (conteos durante el viaje, fraccionados, correcciones).
  final double other;
  final double expected;
  final double? counted;
  final double difference;
  final double unloadedAtClose;
  final String? reason;
  final String? note;

  bool get hasDifference => difference.abs() > 0.0001;

  factory SettlementRow.fromJson(Map<String, dynamic> j) => SettlementRow(
    productId: j['producto_id'].toString(),
    name: j['nombre']?.toString() ?? 'Producto',
    had: stockNum(j['tenia']),
    loaded: stockNum(j['cargo']),
    fromDeposit: stockNum(j['deposito']),
    sold: stockNum(j['vendido']),
    returned: stockNum(j['devuelto']),
    unloaded: stockNum(j['bajado']),
    other: stockNum(j['otros']),
    expected: stockNum(j['deberia']),
    counted: j['contado'] == null ? null : stockNum(j['contado']),
    difference: stockNum(j['diferencia']),
    unloadedAtClose: stockNum(j['bajado_al_cierre']),
    reason: j['motivo']?.toString(),
    note: j['nota']?.toString(),
  );
}

/// La liquidación de un viaje.
class TripSettlement {
  const TripSettlement({
    required this.tripId,
    required this.open,
    this.openedAt,
    this.closedAt,
    this.seller,
    this.closedBy,
    this.counted = false,
    this.rows = const [],
    this.payments = const {},
    this.salesCount = 0,
    this.salesTotal = 0,
  });

  final String tripId;
  final bool open;
  final DateTime? openedAt;
  final DateTime? closedAt;
  final String? seller;
  final String? closedBy;

  /// Si al cerrar se contó lo que volvió.
  final bool counted;
  final List<SettlementRow> rows;

  /// Cobrado por medio de pago.
  final Map<String, double> payments;
  final int salesCount;
  final double salesTotal;

  List<SettlementRow> get withDifference => rows.where((r) => r.hasDifference).toList();
  List<SettlementRow> get matching => rows.where((r) => !r.hasDifference).toList();
  int get fromDepositCount => rows.where((r) => r.fromDeposit > 0).length;
  int get withoutReason => withDifference.where((r) => r.reason == null).length;
  double get collected => payments.values.fold(0, (s, v) => s + v);

  factory TripSettlement.fromJson(Map<String, dynamic> j) {
    final trip = Map<String, dynamic>.from(j['viaje'] as Map);
    final sales = Map<String, dynamic>.from((j['ventas'] as Map?) ?? const {});
    final seller = trip['preventista']?.toString().trim();
    return TripSettlement(
      tripId: trip['id'].toString(),
      open: trip['estado'] == 'abierto',
      openedAt: _date(trip['abierto_at']),
      closedAt: _date(trip['cerrado_at']),
      seller: seller == null || seller.isEmpty ? null : seller,
      closedBy: trip['cerrado_por']?.toString(),
      counted: trip['contado'] == true,
      rows: [
        for (final r in (j['filas'] as List? ?? const []))
          SettlementRow.fromJson(Map<String, dynamic>.from(r as Map)),
      ],
      payments: {
        for (final p in (j['cobros'] as List? ?? const []))
          (p as Map)['medio'].toString(): stockNum(p['importe']),
      },
      salesCount: (sales['cantidad'] as num?)?.toInt() ?? 0,
      salesTotal: stockNum(sales['total']),
    );
  }
}

Future<TripSettlement> fetchTripSettlement(SupabaseClient client, String tripId) async =>
    TripSettlement.fromJson(
      Map<String, dynamic>.from(
        await client.rpc('stock_liquidacion_viaje', params: {'p_viaje_id': tripId}, get: true) as Map,
      ),
    );

/// Guarda los motivos (motivo null = borrarlo).
Future<void> saveSettlementReasons(
  SupabaseClient client,
  String tripId,
  List<({String productId, String? reason, String? note})> items,
) => client.rpc(
  'stock_liquidacion_motivos_guardar',
  params: {
    'p_viaje_id': tripId,
    'p_items': [
      for (final i in items) {'producto_id': i.productId, 'motivo': i.reason, 'nota': i.note},
    ],
  },
);

/// Un viaje en la lista de liquidaciones.
class TripSummary {
  const TripSummary({
    required this.id,
    required this.open,
    this.openedAt,
    this.closedAt,
    this.seller,
    this.differences = 0,
    this.withoutReason = 0,
  });

  final String id;
  final bool open;
  final DateTime? openedAt;
  final DateTime? closedAt;
  final String? seller;
  final int differences;
  final int withoutReason;

  factory TripSummary.fromJson(Map<String, dynamic> j) => TripSummary(
    id: j['id'].toString(),
    open: j['estado'] == 'abierto',
    openedAt: _date(j['abierto_at']),
    closedAt: _date(j['cerrado_at']),
    seller: (j['preventista']?.toString().trim().isEmpty ?? true) ? null : j['preventista'].toString().trim(),
    differences: (j['diferencias'] as num?)?.toInt() ?? 0,
    withoutReason: (j['sin_motivo'] as num?)?.toInt() ?? 0,
  );
}

Future<List<TripSummary>> fetchRecentTrips(SupabaseClient client) async {
  final List<dynamic> rows = await client.rpc('stock_viajes_recientes', params: const {'p_limite': 40}, get: true);
  return [for (final r in rows) TripSummary.fromJson(Map<String, dynamic>.from(r as Map))];
}

/// Texto de un tipo de movimiento o de operación.
String movementLabel(String? operation, String? type) {
  switch (operation) {
    case 'conteo':
      return 'Conteo';
    case 'carga_vehiculo':
      return 'Carga del vehículo';
    case 'baja_vehiculo':
      return 'Bajada al depósito';
    case 'compra':
      return 'Compra';
    case 'cierre_viaje':
      return 'Cierre del viaje';
    case 'fraccion':
      return 'Fraccionado';
    case 'faltante_vehiculo':
      return 'Descontado del depósito';
    case 'finalizacion_pedido':
      return 'Entrega o venta';
    case 'correccion_operacion':
      return 'Corrección';
    case 'recepcion_nota_credito':
      return 'Devolución';
  }
  return switch (type) {
    'entrega' => 'Entrega',
    'venta_directa' => 'Venta directa',
    'devolucion_apta' => 'Devolución',
    'compra' => 'Compra',
    'stock_inicial' => 'Primer conteo',
    'ajuste_entrada' || 'ajuste_salida' => 'Ajuste',
    'transferencia_entrada' => 'Entró de otro lugar',
    'transferencia_salida' => 'Salió a otro lugar',
    'fraccion_entrada' || 'fraccion_salida' => 'Fraccionado',
    'correccion_entrada' || 'correccion_salida' => 'Corrección',
    _ => 'Movimiento',
  };
}

String placeLabel(String? code) => switch (code) {
  'deposito_alberdi' => 'Depósito',
  'vehiculo' => 'Vehículo',
  _ => code ?? '',
};

/// Un movimiento en el historial de un producto.
class ProductMovement {
  const ProductMovement({
    required this.at,
    required this.place,
    required this.label,
    required this.delta,
    required this.after,
    this.before = 0,
    this.user,
    this.counterpart,
    this.reason,
  });

  final DateTime at;
  final String place;
  final String label;
  final double delta;
  final double before;
  final double after;
  final String? user;
  final String? counterpart;
  final String? reason;

  /// Este movimiento dejó el lugar en negativo.
  bool get wentNegative => before >= 0 && after < 0;

  factory ProductMovement.fromJson(Map<String, dynamic> j) => ProductMovement(
    at: _date(j['fecha']) ?? DateTime.now(),
    place: j['ubicacion']?.toString() ?? '',
    label: movementLabel(j['operacion']?.toString(), j['tipo']?.toString()),
    delta: stockNum(j['delta']),
    before: stockNum(j['anterior']),
    after: stockNum(j['nueva']),
    user: j['usuario']?.toString(),
    counterpart: j['contraparte']?.toString(),
    reason: j['motivo']?.toString(),
  );
}

Future<List<ProductMovement>> fetchProductHistory(SupabaseClient client, String productId, {int days = 90}) async {
  final List<dynamic> rows = await client.rpc(
    'stock_historial_producto',
    params: {'p_producto_id': productId, 'p_dias': days},
    get: true,
  );
  return [for (final r in rows) ProductMovement.fromJson(Map<String, dynamic>.from(r as Map))];
}

/// "Stock a revisar".
class StockReview {
  const StockReview({
    this.negatives = const [],
    this.withoutReason = const [],
    this.notCountedTotal = 0,
    this.notCounted = const [],
  });

  /// (producto, lugar, cantidad, desde).
  final List<({String productId, String name, String place, double qty, DateTime? since})> negatives;

  /// Diferencias de liquidación sin motivo (solo administración).
  final List<({String tripId, DateTime? closedAt, String name, double difference})> withoutReason;
  final int notCountedTotal;
  final List<({String productId, String name, DateTime? countedAt})> notCounted;

  int get total => negatives.length + withoutReason.length + notCountedTotal;
  bool get isEmpty => total == 0;

  factory StockReview.fromJson(Map<String, dynamic> j) {
    final notCounted = Map<String, dynamic>.from((j['sin_contar'] as Map?) ?? const {});
    return StockReview(
      negatives: [
        for (final r in (j['negativos'] as List? ?? const []))
          (
            productId: (r as Map)['producto_id'].toString(),
            name: r['nombre']?.toString() ?? '',
            place: r['ubicacion']?.toString() ?? '',
            qty: stockNum(r['cantidad']),
            since: _date(r['desde']),
          ),
      ],
      withoutReason: [
        for (final r in (j['sin_motivo'] as List? ?? const []))
          (
            tripId: (r as Map)['viaje_id'].toString(),
            closedAt: _date(r['cerrado_at']),
            name: r['nombre']?.toString() ?? '',
            difference: stockNum(r['diferencia']),
          ),
      ],
      notCountedTotal: (notCounted['total'] as num?)?.toInt() ?? 0,
      notCounted: [
        for (final r in (notCounted['productos'] as List? ?? const []))
          (
            productId: (r as Map)['producto_id'].toString(),
            name: r['nombre']?.toString() ?? '',
            countedAt: _date(r['contado_at']),
          ),
      ],
    );
  }
}

Future<StockReview> fetchStockReview(SupabaseClient client) async => StockReview.fromJson(
  Map<String, dynamic>.from(await client.rpc('stock_a_revisar', params: const {}, get: true) as Map),
);

/// Lo que generó movimientos en el día (una carga, una compra, una entrega...), con sus productos.
class DayMovement {
  const DayMovement({
    required this.at,
    required this.label,
    this.user,
    this.counterpart,
    this.products = 0,
    this.lines = const [],
  });

  final DateTime at;
  final String label;
  final String? user;
  final String? counterpart;
  final int products;
  final List<({String product, String place, double delta, double after})> lines;

  Set<String> get places => {for (final l in lines) l.place};

  factory DayMovement.fromJson(Map<String, dynamic> j) => DayMovement(
    at: _date(j['hora']) ?? DateTime.now(),
    label: movementLabel(j['tipo']?.toString(), j['detalle']?.toString()),
    user: j['usuario']?.toString(),
    counterpart: j['contraparte']?.toString(),
    products: (j['productos'] as num?)?.toInt() ?? 0,
    lines: [
      for (final l in (j['lineas'] as List? ?? const []))
        (
          product: (l as Map)['producto']?.toString() ?? '',
          place: l['ubicacion']?.toString() ?? '',
          delta: stockNum(l['delta']),
          after: stockNum(l['nueva']),
        ),
    ],
  );
}

String isoDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

Future<List<DayMovement>> fetchDayMovements(SupabaseClient client, DateTime day) async {
  final List<dynamic> rows = await client.rpc('stock_movimientos_dia', params: {'p_fecha': isoDay(day)}, get: true);
  return [for (final r in rows) DayMovement.fromJson(Map<String, dynamic>.from(r as Map))];
}
