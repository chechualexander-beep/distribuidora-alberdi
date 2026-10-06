const diasVisita = <int, String>{
  1: 'Lunes',
  2: 'Martes',
  3: 'Miércoles',
  4: 'Jueves',
  5: 'Viernes',
  6: 'Sábado',
  7: 'Domingo',
};

int? diaVisitaCliente(Map<String, dynamic> cliente) =>
    int.tryParse(cliente['dia_visita']?.toString() ?? '');

String nombreDiaVisita(int? dia) => diasVisita[dia] ?? 'Sin asignar';

String normalizarCliente(Object? valor) {
  var texto = (valor?.toString() ?? '').trim().toLowerCase();
  const reemplazos = {
    'á': 'a',
    'é': 'e',
    'í': 'i',
    'ó': 'o',
    'ú': 'u',
    'ü': 'u',
  };
  for (final entry in reemplazos.entries) {
    texto = texto.replaceAll(entry.key, entry.value);
  }
  return texto.replaceAll(RegExp(r'\s+'), ' ');
}

// Conjuntos vacíos significan todos; texto vacío significa sin localidad/zona;
// día 0 significa sin día asignado.
bool coincideCliente(
  Map<String, dynamic> cliente, {
  String busqueda = '',
  Set<String> localidades = const {},
  String? zona,
  Set<int> dias = const {},
}) {
  if (localidades.isNotEmpty &&
      !localidades.contains(normalizarCliente(cliente['localidad']))) {
    return false;
  }
  if (zona != null && normalizarCliente(cliente['zona']) != zona) return false;
  if (dias.isNotEmpty && !dias.contains(diaVisitaCliente(cliente) ?? 0)) {
    return false;
  }
  final campos = [
    'nombre_comercio',
    'propietario',
    'direccion',
    'telefono',
    'localidad',
    'zona',
  ].map((campo) => normalizarCliente(cliente[campo])).join(' ');
  return normalizarCliente(busqueda).split(' ').every(campos.contains);
}

Map<String, String> opcionesClientes(
  List<Map<String, dynamic>> clientes,
  String campo,
) {
  final opciones = <String, String>{};
  for (final cliente in clientes) {
    final clave = normalizarCliente(cliente[campo]);
    if (clave.isNotEmpty) {
      opciones.putIfAbsent(clave, () => cliente[campo].toString().trim());
    }
  }
  final claves = opciones.keys.toList()..sort();
  return {for (final clave in claves) clave: opciones[clave]!};
}
