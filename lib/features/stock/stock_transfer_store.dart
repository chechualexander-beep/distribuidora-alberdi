import 'package:supabase_flutter/supabase_flutter.dart';

import 'stock_data.dart';

/// Un renglón de la lista compartida de carga (o bajada): lo que se va a pasar, lo que pedían
/// los pedidos y si ya está marcado en flúor (y quién lo marcó).
class TransferLine {
  const TransferLine({
    required this.productId,
    this.quantity,
    this.wanted,
    this.marked = false,
    this.markedBy,
    this.markedAt,
  });

  final String productId;
  final double? quantity;
  final double? wanted;
  final bool marked;
  final String? markedBy;
  final DateTime? markedAt;

  bool get isEmpty => quantity == null && wanted == null && !marked;

  /// Mismo contenido (sin mirar quién marcó).
  bool sameAs(TransferLine? other) {
    if (other == null) return isEmpty;
    bool near(double? a, double? b) => a == null || b == null ? a == b : (a - b).abs() < 0.0001;
    return near(quantity, other.quantity) && near(wanted, other.wanted) && marked == other.marked;
  }

  factory TransferLine.fromJson(Map<String, dynamic> json) => TransferLine(
    productId: json['producto_id'].toString(),
    quantity: json['cantidad'] == null ? null : stockNum(json['cantidad']),
    wanted: json['pedido'] == null ? null : stockNum(json['pedido']),
    marked: json['marcada'] == true,
    markedBy: json['marcada_por']?.toString(),
    markedAt: DateTime.tryParse(json['marcada_at']?.toString() ?? '')?.toLocal(),
  );

  Map<String, dynamic> toJson() => {
    'producto_id': productId,
    'cantidad': quantity,
    'pedido': wanted,
    'marcada': marked,
  };
}

/// La lista como está en la base, con quiénes más la están usando.
class TransferList {
  const TransferList({this.version = '', this.lines = const {}, this.others = const []});

  final String version;
  final Map<String, TransferLine> lines;
  final List<String> others;

  factory TransferList.fromJson(Object? raw) {
    final json = Map<String, dynamic>.from(raw as Map);
    return TransferList(
      version: json['version']?.toString() ?? '',
      lines: {
        for (final l in (json['lineas'] as List? ?? const []))
          (l as Map)['producto_id'].toString(): TransferLine.fromJson(Map<String, dynamic>.from(l)),
      },
      others: [for (final o in (json['otros'] as List? ?? const [])) o.toString()],
    );
  }
}

/// Dónde vive la lista compartida. [direction]: 'cargar' o 'bajar'.
abstract class TransferStore {
  Future<TransferList> fetch(String direction);
  Future<TransferList> put(String direction, List<TransferLine> lines);
  Future<TransferList> clear(String direction);
}

/// La lista en la base (todos los teléfonos y la PC ven la misma).
class RpcTransferStore implements TransferStore {
  const RpcTransferStore(this.client);
  final SupabaseClient client;

  @override
  Future<TransferList> fetch(String direction) async => TransferList.fromJson(
    await client.rpc('stock_traspaso_lista', params: {'p_direccion': direction}),
  );

  @override
  Future<TransferList> put(String direction, List<TransferLine> lines) async => TransferList.fromJson(
    await client.rpc(
      'stock_traspaso_poner',
      params: {'p_direccion': direction, 'p_lineas': [for (final l in lines) l.toJson()]},
    ),
  );

  @override
  Future<TransferList> clear(String direction) async => TransferList.fromJson(
    await client.rpc('stock_traspaso_vaciar', params: {'p_direccion': direction}),
  );
}
