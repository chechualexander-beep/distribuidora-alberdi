import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:csv/csv.dart';


class AdminProductsPage extends StatefulWidget {
  const AdminProductsPage({super.key});

  @override
  State<AdminProductsPage> createState() => _AdminProductsPageState();
}

class _AdminProductsPageState extends State<AdminProductsPage> {
  bool _cargando = true;
  String? _error;

  List<Map<String, dynamic>> _productos = [];
  String _busqueda = '';

bool _eliminandoProducto = false;
  @override
  void initState() {
    super.initState();
    _cargarProductos();
  }

  Future<void> _cargarProductos() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final respuesta = await Supabase.instance.client
          .from('productos')
          .select()
          
          .order('nombre');

      if (!mounted) return;

      setState(() {
        _productos = List<Map<String, dynamic>>.from(respuesta);
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _error = 'No se pudieron cargar los productos.';
        _cargando = false;
      });
    }
  }
  Future<void> _exportarProductos() async {
  if (_productos.isEmpty) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No hay productos para exportar.'),
      ),
    );
    return;
  }

  String escaparCsv(dynamic valor) {
    final texto = valor?.toString() ?? '';
    return '"${texto.replaceAll('"', '""')}"';
  }

  const columnas = [
    'id',
    'codigo_original',
    'nombre',
    'costo',
    'precio_normal',
    'precio_promo',
    'precio_interior',
    'comision_normal',
    'comision_promo',
    'comision_interior',
    'activo',
    'visible_preventista',
    'tipo_margen',
  ];

  final buffer = StringBuffer();

  buffer.writeln(columnas.join(';'));

  for (final producto in _productos) {
    final fila = columnas.map((columna) {
  if (columna == 'visible_preventista') {
    return escaparCsv(producto['visible_preventistas']);
  }

  return escaparCsv(producto[columna]);
}).join(';');

    buffer.writeln(fila);
  }

  final contenido = utf8.encode(
  '\uFEFF${buffer.toString()}',
);

final ruta = await FilePicker.saveFile(
  dialogTitle: 'Guardar productos',
  fileName: 'productos_exportados.csv',
  bytes: Uint8List.fromList(contenido),
  mimeType: 'text/csv',
  type: FileType.custom,
  allowedExtensions: ['csv'],
);

if (ruta == null) return;

  if (!mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('Productos exportados correctamente en:\n$ruta'),
    ),
  );
}
Future<void> _seleccionarArchivoImportacion() async {
  final archivo = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: ['csv'],
  );

  if (archivo == null) {
    return;
  }

  final bytes = await archivo.readAsBytes();

  String contenido;

try {
  contenido = utf8.decode(bytes);
} on FormatException {
  contenido = latin1.decode(bytes);
}
  final filasCsv = Csv(
  fieldDelimiter: ';',
  dynamicTyping: false,
).decode(contenido);

  final lineas = const LineSplitter()
      .convert(contenido)
      .where((linea) => linea.trim().isNotEmpty)
      .toList();

  if (lineas.isEmpty) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('El archivo CSV está vacío.'),
      ),
    );
    return;
  }
  final encabezados = lineas.first
    .replaceFirst('\uFEFF', '')
    .split(';')
    .map((e) => e.trim())
    .toList();

const encabezadosEsperados = [
  'id',
  'codigo_original',
  'nombre',
  'costo',
  'precio_normal',
  'precio_promo',
  'precio_interior',
  'comision_normal',
  'comision_promo',
  'comision_interior',
  'activo',
  'visible_preventista',
  'tipo_margen',
];

final encabezadosValidos =
    encabezados.length == encabezadosEsperados.length &&
    List.generate(
      encabezadosEsperados.length,
      (i) => encabezados[i] == encabezadosEsperados[i],
    ).every((e) => e);

if (!encabezadosValidos) {
  if (!mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text(
        'El archivo no tiene el formato esperado para importar productos.',
      ),
    ),
  );
  return;
}

  final cantidadProductos = filasCsv.length - 1;
  int modificados = 0;
int sinCambios = 0;
int errores = 0;
final productosModificados = <Map<String, dynamic>>[];

String texto(dynamic valor) {
  return valor?.toString().trim() ?? '';
}

double numero(dynamic valor) {
  return double.tryParse(
        texto(valor).replaceAll(',', '.'),
      ) ??
      0;
}

bool booleano(dynamic valor) {
  final valorTexto = texto(valor).toLowerCase();

  return valorTexto == 'true' ||
      valorTexto == '1' ||
      valorTexto == 'si' ||
      valorTexto == 'sí';
}

final productosPorId = <String, Map<String, dynamic>>{
  for (final producto in _productos)
    producto['id'].toString(): producto,
};

for (final fila in filasCsv.skip(1)) {
  if (fila.length != encabezadosEsperados.length) {
    errores++;
    continue;
  }

  final id = texto(fila[0]);

  if (id.isEmpty) {
    errores++;
    continue;
  }

  final productoActual = productosPorId[id];

  if (productoActual == null) {
    errores++;
    continue;
  }

  final cambioTexto =
      texto(fila[1]) != texto(productoActual['codigo_original']) ||
      texto(fila[2]) != texto(productoActual['nombre']) ||
      texto(fila[12]) != texto(productoActual['tipo_margen']);

  final cambioNumerico =
      numero(fila[3]) != numero(productoActual['costo']) ||
      numero(fila[4]) != numero(productoActual['precio_normal']) ||
      numero(fila[5]) != numero(productoActual['precio_promo']) ||
      numero(fila[6]) != numero(productoActual['precio_interior']) ||
      numero(fila[7]) != numero(productoActual['comision_normal']) ||
      numero(fila[8]) != numero(productoActual['comision_promo']) ||
      numero(fila[9]) != numero(productoActual['comision_interior']);

  final cambioBooleano =
      booleano(fila[10]) !=
          (productoActual['activo'] == true) ||
      booleano(fila[11]) !=
          (productoActual['visible_preventistas'] == true);

  if (cambioTexto || cambioNumerico || cambioBooleano) {
  modificados++;

  productosModificados.add({
    'id': id,
    'codigo_original': texto(fila[1]),
    'nombre': texto(fila[2]),
    'costo': numero(fila[3]),
    'precio_normal': numero(fila[4]),
    'precio_promo': numero(fila[5]),
    'precio_interior': numero(fila[6]),
    'comision_normal': numero(fila[7]),
    'comision_promo': numero(fila[8]),
    'comision_interior': numero(fila[9]),
    'activo': booleano(fila[10]),
    'visible_preventistas': booleano(fila[11]),
    'tipo_margen': texto(fila[12]),
  });
} else {
  sinCambios++;
}
}

  if (!mounted) return;

  await showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (context) {
    return AlertDialog(
      title: const Text('Vista previa de importación'),
      content: Text(
        'Productos encontrados: $cantidadProductos\n\n'
        'Modificados: $modificados\n'
        'Sin cambios: $sinCambios\n'
        'Errores: $errores',
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text('Cancelar'),
        ),
        FilledButton(
  onPressed: modificados > 0 && errores == 0
      ? () async {
          Navigator.of(context).pop();

          try {
            for (final producto in productosModificados) {
              final id = producto['id'].toString();

              final datos = Map<String, dynamic>.from(producto);
              datos.remove('id');
              if (datos['codigo_original']?.toString().trim().isEmpty ?? true) {
  datos['codigo_original'] = null;
}

              await Supabase.instance.client
                  .from('productos')
                  .update(datos)
                  .eq('id', id);
            }

            await _cargarProductos();

            if (!mounted) return;

            ScaffoldMessenger.of(this.context).showSnackBar(
              SnackBar(
                content: Text(
                  '${productosModificados.length} producto(s) actualizado(s) correctamente.',
                ),
              ),
            );
          } catch (e) {
            if (!mounted) return;

            ScaffoldMessenger.of(this.context).showSnackBar(
              SnackBar(
                content: Text(
                  'Error al actualizar productos: $e',
                ),
              ),
            );
          }
        }
      : null,
  child: const Text('Aplicar cambios'),
),
      ],
    );
  },
);
}
  Future<void> _nuevoProducto() async {
  final nombreController = TextEditingController();
  
  final costoController = TextEditingController();

  final precioNormalController = TextEditingController(text: '0');
final precioPromoController = TextEditingController(text: '0');
final precioInteriorController = TextEditingController(text: '0');

String tipoMargen = 'normal';
final comisionNormalController = TextEditingController(text: '10');
final comisionPromoController = TextEditingController(text: '5');
final comisionInteriorController = TextEditingController(text: '10');

bool guardando = false;
double redondearHaciaArriba100(double valor) {
  return (valor / 100).ceil() * 100;
}

void recalcularPrecios() {
  final costo = double.tryParse(
        costoController.text.replaceAll(',', '.'),
      ) ??
      0;

  final precioNormal = redondearHaciaArriba100(
  costo * (tipoMargen == 'competitivo' ? 1.30 : 1.50),
);

  final precioPromo = redondearHaciaArriba100(
    costo * 1.21,
  );

  final precioInterior = redondearHaciaArriba100(
    precioNormal * 1.07,
  );

  precioNormalController.text = precioNormal.toStringAsFixed(0);
  precioPromoController.text = precioPromo.toStringAsFixed(0);
  precioInteriorController.text = precioInterior.toStringAsFixed(0);
  if (tipoMargen == 'competitivo') {
  comisionNormalController.text = '6';
  comisionPromoController.text = '5';
  comisionInteriorController.text = '6';
} else {
  comisionNormalController.text = '10';
  comisionPromoController.text = '5';
  comisionInteriorController.text = '10';
}
}

costoController.addListener(recalcularPrecios);


  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return AlertDialog(
        title: const Text('Nuevo producto'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
  child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nombreController,
                decoration: const InputDecoration(
                  labelText: 'Nombre',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              
              TextField(
                controller: costoController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Costo',
                  prefixText: '\$ ',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

DropdownButtonFormField<String>(
  initialValue: tipoMargen,
  decoration: const InputDecoration(
    labelText: 'Tipo de margen',
    border: OutlineInputBorder(),
  ),
  items: const [
    DropdownMenuItem(
      value: 'normal',
      child: Text('Normal'),
    ),
    DropdownMenuItem(
      value: 'competitivo',
      child: Text('Competitivo'),
    ),
  ],
  onChanged: (valor) {
    if (valor == null) return;

    tipoMargen = valor;
    recalcularPrecios();
  },
),

const SizedBox(height: 12),

TextField(
  controller: precioNormalController,
  readOnly: true,
  decoration: const InputDecoration(
    labelText: 'Precio normal',
    prefixText: '\$ ',
    border: OutlineInputBorder(),
  ),
),

const SizedBox(height: 12),

TextField(
  controller: precioPromoController,
  readOnly: true,
  decoration: const InputDecoration(
    labelText: 'Precio promo',
    prefixText: '\$ ',
    border: OutlineInputBorder(),
  ),
),

const SizedBox(height: 12),

TextField(
  controller: precioInteriorController,
  readOnly: true,
  decoration: const InputDecoration(
    labelText: 'Precio interior',
    prefixText: '\$ ',
    border: OutlineInputBorder(),
  ),
),
const SizedBox(height: 16),

TextField(
  controller: comisionNormalController,
  readOnly: true,
  decoration: const InputDecoration(
    labelText: 'Comisión normal (%)',
    suffixText: ' %',
    border: OutlineInputBorder(),
  ),
),

const SizedBox(height: 12),

TextField(
  controller: comisionPromoController,
  readOnly: true,
  decoration: const InputDecoration(
    labelText: 'Comisión promo (%)',
    suffixText: ' %',
    border: OutlineInputBorder(),
  ),
),

const SizedBox(height: 12),

TextField(
  controller: comisionInteriorController,
  readOnly: true,
  decoration: const InputDecoration(
    labelText: 'Comisión interior (%)',
    suffixText: ' %',
    border: OutlineInputBorder(),
  ),
),
            ],
          ),
        ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
  final nombre = nombreController.text.trim();

  if (nombre.isEmpty) {
    return;
  }
  if (guardando) return;

guardando = true;

  final costo = double.tryParse(
        costoController.text.replaceAll(',', '.'),
      ) ??
      0;

  final precioNormal = double.tryParse(
        precioNormalController.text.replaceAll(',', '.'),
      ) ??
      0;

  final precioPromo = double.tryParse(
        precioPromoController.text.replaceAll(',', '.'),
      ) ??
      0;

  final precioInterior = double.tryParse(
        precioInteriorController.text.replaceAll(',', '.'),
      ) ??
      0;

  final comisionNormal = double.tryParse(
        comisionNormalController.text.replaceAll(',', '.'),
      ) ??
      0;

  final comisionPromo = double.tryParse(
        comisionPromoController.text.replaceAll(',', '.'),
      ) ??
      0;

  final comisionInterior = double.tryParse(
        comisionInteriorController.text.replaceAll(',', '.'),
      ) ??
      0;

  try {
  await Supabase.instance.client.from('productos').insert({
    'nombre': nombre,
    'costo': costo,
    'precio_normal': precioNormal,
    'precio_promo': precioPromo,
    'precio_interior': precioInterior,
    'comision_normal': comisionNormal,
    'comision_promo': comisionPromo,
    'comision_interior': comisionInterior,
    'tipo_margen': tipoMargen,
    'activo': true,
    'visible_preventistas': true,
    'codigo_original': null,
  });

  if (!context.mounted) return;

  Navigator.of(context).pop();

  await _cargarProductos();
} catch (e) {
  if (!context.mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('No se pudo guardar el producto: $e'),
    ),
  );
} finally {
  guardando = false;
}
},
child: const Text('Guardar'),
          ),
        ],
      );
    },
  );
}

  Future<void> _editarProducto(Map<String, dynamic> producto) async {
  

  final costoController = TextEditingController(
    text: producto['costo']?.toString() ?? '0',
  );
  
  final precioNormalController = TextEditingController(
    text: producto['precio_normal']?.toString() ?? '0',
  );

  final precioPromoController = TextEditingController(
    text: producto['precio_promo']?.toString() ?? '0',
  );

  final precioInteriorController = TextEditingController(
    text: producto['precio_interior']?.toString() ?? '0',
  );
  double precioNormalCalculado = 0;
double precioPromoCalculado = 0;
double precioInteriorCalculado = 0;
double redondearHaciaArriba100(double valor) {
  return (valor / 100).ceil() * 100;
}
costoController.addListener(() {
  final costo = double.tryParse(
        costoController.text.replaceAll(',', '.'),
      ) ??
      0;

  final esCompetitivo =
    producto['tipo_margen'] == 'competitivo';

if (esCompetitivo) {
  precioNormalCalculado = redondearHaciaArriba100(
    costo * 1.30,
  );
} else {
  precioNormalCalculado = redondearHaciaArriba100(
    costo * 1.50,
  );
}

precioPromoCalculado = redondearHaciaArriba100(
  costo * 1.21,
);

precioInteriorCalculado = redondearHaciaArriba100(
  precioNormalCalculado * 1.07,
);
precioNormalController.text =
    precioNormalCalculado.toStringAsFixed(0);

precioPromoController.text =
    precioPromoCalculado.toStringAsFixed(0);

precioInteriorController.text =
    precioInteriorCalculado.toStringAsFixed(0);
});


  final comisionNormalController = TextEditingController(
    text: producto['comision_normal']?.toString() ?? '0',
  );

  final comisionPromoController = TextEditingController(
    text: producto['comision_promo']?.toString() ?? '0',
  );

  final comisionInteriorController = TextEditingController(
    text: producto['comision_interior']?.toString() ?? '0',
  );
  bool activo = producto['activo'] == true;
bool visiblePreventistas = producto['visible_preventistas'] == true;
bool guardando = false;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
  return StatefulBuilder(
    builder: (context, setDialogState) {
      return AlertDialog(
        title: Text(
          producto['nombre']?.toString() ?? 'Editar producto',
        ),
        content: SizedBox(
  child: SingleChildScrollView(
  child: Column(
  mainAxisSize: MainAxisSize.min,
  children: [
    TextField(
      controller: costoController,
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
      ),
      decoration: const InputDecoration(
        labelText: 'Costo',
        prefixText: '\$ ',
        border: OutlineInputBorder(),
      ),
    ),
    const SizedBox(height: 12),
    TextField(
      controller: precioNormalController,
      readOnly: true,
      decoration: const InputDecoration(
        labelText: 'Precio normal',
        prefixText: '\$ ',
        border: OutlineInputBorder(),
      ),
    ),
    const SizedBox(height: 12),
    TextField(
      controller: precioPromoController,
      readOnly: true,
      decoration: const InputDecoration(
        labelText: 'Precio promo',
        prefixText: '\$ ',
        border: OutlineInputBorder(),
      ),
    ),
    const SizedBox(height: 12),
    TextField(
      controller: precioInteriorController,
      readOnly: true,
      decoration: const InputDecoration(
        labelText: 'Precio interior',
        prefixText: '\$ ',
        border: OutlineInputBorder(),
      ),
    ),
    const SizedBox(height: 16),

TextField(
  controller: comisionNormalController,
  keyboardType: const TextInputType.numberWithOptions(decimal: true),
  decoration: const InputDecoration(
    labelText: 'Comisión normal (%)',
    suffixText: ' %',
    border: OutlineInputBorder(),
  ),
),

const SizedBox(height: 12),

TextField(
  controller: comisionPromoController,
  keyboardType: const TextInputType.numberWithOptions(decimal: true),
  decoration: const InputDecoration(
    labelText: 'Comisión promo (%)',
    suffixText: ' %',
    border: OutlineInputBorder(),
  ),
),

const SizedBox(height: 12),

TextField(
  controller: comisionInteriorController,
  keyboardType: const TextInputType.numberWithOptions(decimal: true),
  decoration: const InputDecoration(
    labelText: 'Comisión interior (%)',
    suffixText: ' %',
    border: OutlineInputBorder(),
  ),
),
const SizedBox(height: 16),

SwitchListTile(
  contentPadding: EdgeInsets.zero,
  title: const Text('Producto activo'),
  value: activo,
  onChanged: (valor) {
    setDialogState(() {
      activo = valor;

      if (!activo) {
        visiblePreventistas = false;
      }
    });
  },
),

SwitchListTile(
  contentPadding: EdgeInsets.zero,
  title: const Text('Mostrar a preventistas'),
  value: visiblePreventistas,
  onChanged: activo
      ? (valor) {
          setDialogState(() {
            visiblePreventistas = valor;
          });
        }
      : null,
),
  ],
),
),
        ),
        actions: [
  TextButton(
    onPressed: () => Navigator.of(context).pop(),
    child: const Text('Cancelar'),
  ),
  FilledButton(
    onPressed: () async {
      if (guardando) return;
guardando = true;
  final costo = double.tryParse(
        costoController.text.replaceAll(',', '.'),
      ) ??
      0;

  final precioNormal = double.tryParse(
        precioNormalController.text.replaceAll(',', '.'),
      ) ??
      0;

  final precioPromo = double.tryParse(
        precioPromoController.text.replaceAll(',', '.'),
      ) ??
      0;

  final precioInterior = double.tryParse(
        precioInteriorController.text.replaceAll(',', '.'),
      ) ??
      0;
final comisionNormal = double.tryParse(
      comisionNormalController.text.replaceAll(',', '.'),
    ) ??
    0;

final comisionPromo = double.tryParse(
      comisionPromoController.text.replaceAll(',', '.'),
    ) ??
    0;

final comisionInterior = double.tryParse(
      comisionInteriorController.text.replaceAll(',', '.'),
    ) ??
    0;

  try {
  await Supabase.instance.client
      .from('productos')
      .update({
        'costo': costo,
        'precio_normal': precioNormal,
        'precio_promo': precioPromo,
        'precio_interior': precioInterior,
        'comision_normal': comisionNormal,
        'comision_promo': comisionPromo,
        'comision_interior': comisionInterior,
        'activo': activo,
        'visible_preventistas': activo ? visiblePreventistas : false,
      })
      .eq('id', producto['id']);

  if (!context.mounted) return;

  Navigator.of(context).pop();

  await _cargarProductos();
} catch (e) {
  if (!context.mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        'No se pudo guardar el producto: $e',
      ),
    ),
  );
} finally {
  guardando = false;
}
},
    child: const Text('Guardar'),
  ),
],
            );
    },
  );
    },
  );

}
Future<void> _eliminarProducto(
  Map<String, dynamic> producto,
) async {
  final nombre = producto['nombre']?.toString() ?? 'este producto';

  final confirmar = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Eliminar producto'),
        content: Text(
          '¿Seguro que querés eliminar "$nombre"?\n\n'
          'Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      );
    },
  );

  if (confirmar != true) return;
  if (_eliminandoProducto) return;

_eliminandoProducto = true;

  try {
    await Supabase.instance.client
        .from('productos')
        .delete()
        .eq('id', producto['id']);

    await _cargarProductos();
  } catch (e) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'No se pudo eliminar el producto: $e',
        ),
      ),
    );
  } finally {
  _eliminandoProducto = false;
}
}

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return Center(
        child: Text(_error!),
      );
    }

String normalizarTexto(String texto) {
  return texto
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ü', 'u')
      .replaceAll('ñ', 'n');
}
    final productosFiltrados = _productos.where((producto) {
  final texto = normalizarTexto(_busqueda.trim());

  if (texto.isEmpty) {
    return true;
  }

  final nombre = normalizarTexto(
    producto['nombre']?.toString() ?? '',
  );

  final codigo = producto['codigo_original']?.toString().toLowerCase() ?? '';

  return nombre.contains(texto) || codigo.contains(texto);
}).toList();

return Column(
  children: [
    Padding(
  padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
  child: Row(
    children: [
      Expanded(
        child: TextField(
          decoration: const InputDecoration(
            labelText: 'Buscar producto',
            hintText: 'Nombre o código',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
          ),
          onChanged: (valor) {
            setState(() {
              _busqueda = valor;
            });
          },
        ),
      ),
      const SizedBox(width: 12),
      FilledButton.icon(
        onPressed: () {
  _nuevoProducto();
},
        icon: const Icon(Icons.add),
        label: const Text('Nuevo producto'),
      ),
      const SizedBox(width: 12),
OutlinedButton.icon(
  onPressed: _exportarProductos,
  icon: const Icon(Icons.download_outlined),
  label: const Text('Exportar productos'),
),
const SizedBox(width: 12),
OutlinedButton.icon(
  onPressed: _seleccionarArchivoImportacion,
  icon: const Icon(Icons.upload_file_outlined),
  label: const Text('Importar productos'),
),
    ],
  ),
),
    Expanded(
      child: ListView.builder(
        padding: const EdgeInsets.all(24),
      itemCount: productosFiltrados.length,
      itemBuilder: (context, index) {
        final producto = productosFiltrados[index];

        return ListTile(
  title: Text(
    producto['nombre']?.toString() ?? 'Sin nombre',
    style: const TextStyle(
      fontWeight: FontWeight.bold,
    ),
  ),
  subtitle: Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Código: ${producto['codigo_original'] ?? '-'}'),
        Text(
  producto['activo'] != true
      ? 'Estado: Inactivo'
      : producto['visible_preventistas'] == true
          ? 'Estado: Activo · Visible preventistas'
          : 'Estado: Activo · Oculto preventistas',
  style: const TextStyle(
    fontWeight: FontWeight.w600,
  ),
),
        const SizedBox(height: 4),
        Text('Costo: \$${producto['costo'] ?? 0}'),
        Text('Precio normal: \$${producto['precio_normal'] ?? 0}'),
        Text('Precio promo: \$${producto['precio_promo'] ?? 0}'),
        Text('Precio interior: \$${producto['precio_interior'] ?? 0}'),
        const SizedBox(height: 4),
        Text('Comisión normal: ${producto['comision_normal'] ?? 0}%'),
        Text('Comisión promo: ${producto['comision_promo'] ?? 0}%'),
        Text('Comisión interior: ${producto['comision_interior'] ?? 0}%'),
      ],
    ),
  ),
  trailing: Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    IconButton(
      icon: const Icon(Icons.edit_outlined),
      tooltip: 'Editar producto',
      onPressed: () {
        _editarProducto(producto);
      },
    ),
    IconButton(
      icon: const Icon(Icons.delete_outline),
      tooltip: 'Eliminar producto',
      onPressed: () {
        _eliminarProducto(producto);
      },
    ),
  ],
),
        );
      },
    ),
  ),
],
);
  }
}