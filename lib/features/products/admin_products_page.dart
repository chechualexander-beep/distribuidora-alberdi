import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

    final productosFiltrados = _productos.where((producto) {
  final texto = _busqueda.toLowerCase().trim();

  if (texto.isEmpty) {
    return true;
  }

  final nombre = producto['nombre']?.toString().toLowerCase() ?? '';
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