import '../../core/text_search.dart';

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

String normalizarCliente(Object? valor) => sinAcentos(valor);

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
  return coincideBusqueda(
    busqueda,
    [
      'nombre_comercio',
      'propietario',
      'direccion',
      'telefono',
      'localidad',
      'zona',
    ].map((campo) => cliente[campo]),
  );
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
