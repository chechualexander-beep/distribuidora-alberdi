/// Búsqueda de texto común a toda la app.
///
/// - No distingue mayúsculas ni acentos ("azucar" encuentra "Azúcar").
/// - Busca por palabras en cualquier orden ("tutuca 1kg" encuentra
///   "Tutuca S. Cay. x 1kg").
/// - Ignora puntos y espacios dentro de una palabra ("fn" encuentra "F.N",
///   "1 kg" encuentra "1kg").
library;

const _reemplazos = {
  'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a', 'ã': 'a',
  'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
  'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
  'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o', 'õ': 'o',
  'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
  'ñ': 'n', 'ç': 'c',
};

final _espacios = RegExp(r'\s+');
final _noAlfanumerico = RegExp(r'[^a-z0-9]');

/// Texto en minúsculas, sin acentos y con un solo espacio entre palabras.
String sinAcentos(Object? valor) {
  final texto = (valor?.toString() ?? '').toLowerCase();
  final buffer = StringBuffer();
  for (final rune in texto.runes) {
    final letra = String.fromCharCode(rune);
    buffer.write(_reemplazos[letra] ?? letra);
  }
  return buffer.toString().trim().replaceAll(_espacios, ' ');
}

/// Palabras de una búsqueda, ya normalizadas.
List<String> palabrasBusqueda(String busqueda) =>
    sinAcentos(busqueda).split(' ').where((p) => p.isNotEmpty).toList();

/// ¿El texto de [campos] contiene todas las palabras de [busqueda]?
/// Una búsqueda vacía coincide con todo.
bool coincideBusqueda(String busqueda, Iterable<Object?> campos) {
  final palabras = palabrasBusqueda(busqueda);
  if (palabras.isEmpty) return true;
  final texto = sinAcentos(campos.where((c) => c != null).join(' '));
  final compacto = texto.replaceAll(_noAlfanumerico, '');
  for (final palabra in palabras) {
    if (texto.contains(palabra)) continue;
    final palabraCompacta = palabra.replaceAll(_noAlfanumerico, '');
    if (palabraCompacta.isNotEmpty && compacto.contains(palabraCompacta)) {
      continue;
    }
    return false;
  }
  return true;
}
