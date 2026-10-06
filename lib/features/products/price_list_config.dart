class PriceListConfig {
  static const tipos = ['normal', 'promo', 'interior'];
  final String base;
  final Map<String, String> excepciones;

  PriceListConfig({
    this.base = 'normal',
    Map<String, String> excepciones = const {},
  }) : excepciones = Map.unmodifiable(
         excepciones.map((k, v) => MapEntry(claveCategoria(k), v)),
       ) {
    if (!tipos.contains(base) ||
        this.excepciones.values.any((v) => !tipos.contains(v))) {
      throw const FormatException('Tipo de precio inválido');
    }
  }

  static String claveCategoria(String categoria) =>
      categoria.trim().toLowerCase();
  static bool incluir(Map<String, dynamic> producto) =>
      producto['activo'] == true &&
      producto['visible_preventistas'] == true &&
      (producto['categoria']?.toString().trim().isNotEmpty ?? false);

  String tipoPara(String categoria) =>
      excepciones[claveCategoria(categoria)] ?? base;

  double precioPara(Map<String, dynamic> producto) {
    final tipo = tipoPara(producto['categoria']?.toString() ?? '');
    final valor = double.tryParse(producto['precio_$tipo']?.toString() ?? '');
    if (valor == null || !valor.isFinite || valor < 0) {
      throw FormatException(
        'Precio inválido en ${producto['nombre'] ?? 'un producto'} ($tipo).',
      );
    }
    return valor;
  }

  Map<String, dynamic> toJson() => {'base': base, 'excepciones': excepciones};
  factory PriceListConfig.fromJson(Map<String, dynamic> json) =>
      PriceListConfig(
        base: json['base'] as String,
        excepciones: Map<String, String>.from(json['excepciones'] as Map),
      );
}
