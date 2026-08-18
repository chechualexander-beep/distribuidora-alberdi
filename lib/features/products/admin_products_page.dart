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
          .eq('activo', true)
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
  Future<void> _editarProducto(Map<String, dynamic> producto) async {
  final nombreController = TextEditingController(
    text: producto['nombre']?.toString() ?? '',
  );

  final codigoController = TextEditingController(
    text: producto['codigo_original']?.toString() ?? '',
  );

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

  final codigo = int.tryParse(
        producto['codigo_original']?.toString() ?? '',
      ) ??
      0;

  if (codigo >= 800) {
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

  await showDialog<void>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(
          producto['nombre']?.toString() ?? 'Editar producto',
        ),
        content: SizedBox(
  width: 420,
  child: TextField(
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
),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      );
    },
  );

  nombreController.dispose();
  codigoController.dispose();
  costoController.dispose();
  precioNormalController.dispose();
  precioPromoController.dispose();
  precioInteriorController.dispose();
  comisionNormalController.dispose();
  comisionPromoController.dispose();
  comisionInteriorController.dispose();
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

    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: _productos.length,
      itemBuilder: (context, index) {
        final producto = _productos[index];

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
  trailing: IconButton(
  icon: const Icon(Icons.edit_outlined),
  tooltip: 'Editar producto',
  onPressed: () {
  _editarProducto(producto);
},
),
);
      },
    );
  }
}