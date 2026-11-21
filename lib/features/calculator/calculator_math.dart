/// Las cinco casillas de la pestaña Margen.
enum CampoMargen { costo, margen, recargo, venta, ganancia }

/// Costo y venta definen todo: ganancia, margen (sobre la venta) y recargo (sobre el costo).
class EstadoMargen {
  const EstadoMargen(this.costo, this.venta);

  final double costo;
  final double venta;

  double get ganancia => venta - costo;

  /// Porcentaje de lo que se cobra que es ganancia.
  double get margen => venta > 0 ? ganancia / venta * 100 : 0;

  /// Porcentaje que se suma sobre el costo.
  double get recargo => costo > 0 ? ganancia / costo * 100 : 0;

  double valor(CampoMargen campo) => switch (campo) {
    CampoMargen.costo => costo,
    CampoMargen.margen => margen,
    CampoMargen.recargo => recargo,
    CampoMargen.venta => venta,
    CampoMargen.ganancia => ganancia,
  };
}

/// Recalcula al escribir [valor] en [editado]. Queda fija la casilla con candado; sin
/// candado, al cambiar el costo se mantiene el margen y al cambiar cualquier otra, el costo.
/// Devuelve null si la combinación no tiene sentido (por ejemplo, margen de 100% o más).
EstadoMargen? resolverMargen(
  EstadoMargen actual,
  CampoMargen editado,
  double valor, {
  CampoMargen? candado,
}) {
  final fija = candado != null && candado != editado
      ? candado
      : editado == CampoMargen.costo
      ? CampoMargen.margen
      : CampoMargen.costo;
  final datos = {editado: valor, fija: actual.valor(fija)};
  double? c = datos[CampoMargen.costo];
  double? v = datos[CampoMargen.venta];
  final g = datos[CampoMargen.ganancia];
  final m = datos[CampoMargen.margen] == null ? null : datos[CampoMargen.margen]! / 100;
  final r = datos[CampoMargen.recargo] == null ? null : datos[CampoMargen.recargo]! / 100;

  if (c != null && v == null) {
    if (g != null) {
      v = c + g;
    } else if (m != null) {
      if (m >= 1) return null;
      v = c / (1 - m);
    } else if (r != null) {
      v = c * (1 + r);
    }
  } else if (v != null && c == null) {
    if (g != null) {
      c = v - g;
    } else if (m != null) {
      c = v * (1 - m);
    } else if (r != null) {
      if (r <= -1) return null;
      c = v / (1 + r);
    }
  } else if (c == null && v == null) {
    if (g != null && m != null) {
      if (m <= 0) return null;
      v = g / m;
      c = v - g;
    } else if (g != null && r != null) {
      if (r <= 0) return null;
      c = g / r;
      v = c + g;
    } else if (m != null) {
      // Margen y recargo dicen lo mismo: se mantiene el costo.
      if (m >= 1) return null;
      c = actual.costo;
      v = c / (1 - m);
    } else if (r != null) {
      c = actual.costo;
      v = c * (1 + r);
    }
  }
  if (c == null || v == null || c < 0 || v <= 0 || !c.isFinite || !v.isFinite) {
    return null;
  }
  return EstadoMargen(c, v);
}

/// Sube al múltiplo de [paso] (10, 50, 100). Paso 0: sin redondeo.
double redondearArriba(double valor, double paso) =>
    paso <= 0 ? valor : (valor / paso).ceil() * paso;

/// Pestaña Descuento.
class ResultadoDescuento {
  const ResultadoDescuento({
    required this.precio,
    required this.descuento,
    this.costo,
  });

  final double precio;

  /// Porcentaje de descuento.
  final double descuento;
  final double? costo;

  double get precioFinal => precio * (1 - descuento / 100);
  double get ahorro => precio - precioFinal;
  double? get ganancia => costo == null ? null : precioFinal - costo!;
  double? get margen =>
      ganancia == null || precioFinal <= 0 ? null : ganancia! / precioFinal * 100;

  /// Descuento que lleva de [precio] a [precioFinal].
  static double descuentoPara(double precio, double precioFinal) =>
      precio <= 0 ? 0 : (1 - precioFinal / precio) * 100;
}

/// Pestaña Por bulto: precio de 100 g o 1 kg a partir del precio de la bolsa.
class ResultadoBulto {
  const ResultadoBulto({
    required this.precioBulto,
    required this.kgBulto,
    required this.kgPedido,
    required this.recargo,
    required this.redondeo,
    this.costoBulto,
  });

  final double precioBulto;
  final double kgBulto;
  final double kgPedido;
  final double recargo;
  final double redondeo;
  final double? costoBulto;

  bool get valido => precioBulto > 0 && kgBulto > 0 && kgPedido > 0;
  double get precioKilo => valido ? precioBulto / kgBulto : 0;
  double get sinRecargo => precioKilo * kgPedido;
  double get precioVenta =>
      valido ? redondearArriba(sinRecargo * (1 + recargo / 100), redondeo) : 0;
  double? get costoPedido =>
      costoBulto == null || kgBulto <= 0 ? null : costoBulto! / kgBulto * kgPedido;
  double? get ganancia => costoPedido == null ? null : precioVenta - costoPedido!;
  double? get margen =>
      ganancia == null || precioVenta <= 0 ? null : ganancia! / precioVenta * 100;
}

final _peso = RegExp(
  r'(\d+(?:[.,]\d+)?)\s*(kgs?|kilos?|grs?|gramos|g)(?![a-z])',
  caseSensitive: false,
);

/// Peso en kilos leído del nombre o la descripción: "x 4kg" → 4, "x 800g" → 0,8,
/// "2,5 kg" → 2,5. Null si no dice.
double? kilosDelTexto(String? texto) {
  final coincidencias = _peso.allMatches(texto ?? '').toList();
  if (coincidencias.isEmpty) return null;
  final m = coincidencias.last;
  final numero = double.tryParse(m.group(1)!.replaceAll(',', '.'));
  if (numero == null || numero <= 0) return null;
  final unidad = m.group(2)!.toLowerCase();
  return unidad.startsWith('k') ? numero : numero / 1000;
}

/// "0,8" → "800 g"; "2.5" → "2,5 kg".
String textoPeso(double kg) {
  if (kg < 1) return '${(kg * 1000).round()} g';
  final redondo = (kg * 100).round() / 100;
  final texto = redondo == redondo.roundToDouble()
      ? redondo.toInt().toString()
      : redondo.toString().replaceAll('.', ',');
  return '$texto kg';
}

/// "25" → "25"; 16.666 → "16,7".
String textoPorcentaje(double valor) {
  final redondo = (valor * 10).round() / 10;
  if (redondo == redondo.roundToDouble()) return redondo.toInt().toString();
  return redondo.toStringAsFixed(1).replaceAll('.', ',');
}

/// Para que no se acumulen errores de coma flotante al mostrar.
double dosDecimales(double v) => (v * 100).round() / 100;
