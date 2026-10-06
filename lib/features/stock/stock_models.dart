const enableStock = bool.fromEnvironment('ENABLE_STOCK', defaultValue: false);

/// Cantidades exactas para formularios y diferencias, sin redondear entradas.
class StockQuantity {
  const StockQuantity(this.millis);
  final int millis;
  static const maxMillis = 99999999999999;

  static StockQuantity? input(String text) {
    final value = text.trim();
    if (value.isEmpty) return null;
    final result = _parse(value);
    if (result.millis > maxMillis) {
      throw const FormatException('Cantidad fuera de rango.');
    }
    return result;
  }

  static StockQuantity fromRpc(Object? value) => _parse(value.toString());

  static StockQuantity _parse(String value) {
    if (!RegExp(r'^\d+(?:[.,]\d{1,3})?$').hasMatch(value)) {
      throw const FormatException(
        'Usá una cantidad no negativa con hasta 3 decimales.',
      );
    }
    final parts = value.replaceAll(',', '.').split('.');
    final whole = int.tryParse(parts.first);
    if (whole == null || whole > 9000000000000000) {
      throw const FormatException('Cantidad fuera de rango.');
    }
    final fraction = parts.length == 1
        ? 0
        : int.parse(parts.last.padRight(3, '0'));
    return StockQuantity(whole * 1000 + fraction);
  }

  String format({bool signed = false}) {
    final absolute = millis.abs();
    final fraction = (absolute % 1000)
        .toString()
        .padLeft(3, '0')
        .replaceFirst(RegExp(r'0+$'), '');
    final sign = millis < 0 ? '-' : (signed && millis > 0 ? '+' : '');
    return '$sign${absolute ~/ 1000}${fraction.isEmpty ? '' : '.$fraction'}';
  }

  num toJsonNumber() => num.parse(format());
  StockQuantity difference(StockQuantity previous) =>
      StockQuantity(millis - previous.millis);
}

String? quantityError(String text) {
  try {
    StockQuantity.input(text);
    return null;
  } on FormatException catch (error) {
    return error.message;
  }
}

enum StockFilter { all, active, inactive }

enum InitialStockFilter { all, pending, initialized }

class StockProduct {
  const StockProduct({
    required this.id,
    required this.name,
    required this.code,
    required this.active,
    required this.cost,
    required this.quantity,
    required this.initialized,
    required this.value,
  });
  final String id, name, code;
  final bool active, initialized;
  final double cost, value;
  final StockQuantity quantity;
  factory StockProduct.fromJson(Map<String, dynamic> json) => StockProduct(
    id: json['producto_id'] as String,
    name: json['nombre'] as String,
    code: json['codigo']?.toString() ?? '',
    active: json['activo'] == true,
    cost: double.parse(json['costo_actual'].toString()),
    quantity: StockQuantity.fromRpc(json['cantidad']),
    initialized: json['inicializado'] as bool,
    value: double.parse(json['valor_stock'].toString()),
  );
  bool matches(String query) =>
      '$name $code'.toLowerCase().contains(query.trim().toLowerCase());
}

List<StockProduct> filterStock(
  List<StockProduct> products,
  String query,
  StockFilter filter,
) => products
    .where(
      (p) =>
          p.matches(query) &&
          switch (filter) {
            StockFilter.all => true,
            StockFilter.active => p.active,
            StockFilter.inactive => !p.active,
          },
    )
    .toList();

List<StockProduct> filterInitialStock(
  List<StockProduct> products,
  String query,
  InitialStockFilter filter,
) => products
    .where(
      (p) =>
          p.matches(query) &&
          switch (filter) {
            InitialStockFilter.all => true,
            InitialStockFilter.pending => !p.initialized,
            InitialStockFilter.initialized => p.initialized,
          },
    )
    .toList();

List<Map<String, dynamic>> initialStockItems(
  List<StockProduct> products,
  Map<String, String> inputs,
) {
  final items = <Map<String, dynamic>>[];
  for (final product in products) {
    if (product.initialized) continue;
    final quantity = StockQuantity.input(inputs[product.id] ?? '');
    if (quantity != null) {
      items.add({
        'producto_id': product.id,
        'cantidad': quantity.toJsonNumber(),
      });
    }
  }
  return items;
}

class StockLocation {
  const StockLocation(this.id, this.name, this.active);
  final String id, name;
  final bool active;
}

class StockSummary {
  const StockSummary(this.products, this.units, this.value);
  final int products;
  final StockQuantity units;
  final double value;
  factory StockSummary.fromJson(Map<String, dynamic> json) => StockSummary(
    int.parse(json['productos_distintos'].toString()),
    StockQuantity.fromRpc(json['unidades_totales']),
    double.parse(json['valor_estimado_total'].toString()),
  );
}

class StockSnapshot {
  const StockSnapshot(this.location, this.products, this.summary);
  final StockLocation location;
  final List<StockProduct> products;
  final StockSummary summary;
}

String movementLabel(String type) => switch (type) {
  'stock_inicial' => 'Stock inicial',
  'ajuste_entrada' => 'Ajuste entrada',
  'ajuste_salida' => 'Ajuste salida',
  _ => 'Movimiento',
};

class StockMovement {
  StockMovement.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      date = DateTime.parse(
        json['created_at'] as String,
      ).toUtc().subtract(const Duration(hours: 3)),
      name = (json['producto'] as Map?)?['nombre']?.toString() ?? 'Producto',
      code = (json['producto'] as Map?)?['codigo']?.toString() ?? '',
      user = [
        (json['usuario'] as Map?)?['nombre'],
        (json['usuario'] as Map?)?['apellido'],
      ].where((v) => v != null && v.toString().trim().isNotEmpty).join(' '),
      type = json['tipo'] as String,
      previous = StockQuantity.fromRpc(json['cantidad_anterior']),
      delta = _delta(json['cantidad_delta']),
      quantity = StockQuantity.fromRpc(json['cantidad_nueva']),
      reason = json['motivo'] as String,
      observation = json['observacion']?.toString() ?? '';
  final String id, name, code, user, type, reason, observation;
  final DateTime date;
  final StockQuantity previous, delta, quantity;
  static StockQuantity _delta(Object? value) {
    final text = value.toString();
    return text.startsWith('-')
        ? StockQuantity(-StockQuantity.fromRpc(text.substring(1)).millis)
        : StockQuantity.fromRpc(value);
  }

  String get formattedDate {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} ${two(date.hour)}:${two(date.minute)}';
  }
}
