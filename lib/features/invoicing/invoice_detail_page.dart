import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:printing/printing.dart';

import 'invoice_pdf_service.dart';

class InvoiceDetailPage extends StatefulWidget {
  final Map<String, dynamic> pedido;
  final bool soloLectura;

  const InvoiceDetailPage({
    super.key,
    required this.pedido,
    this.soloLectura = false,
  });

  @override
  State<InvoiceDetailPage> createState() => _InvoiceDetailPageState();
}

class _InvoiceDetailPageState extends State<InvoiceDetailPage> {
  bool _cargando = true;
  String? _error;
  String? _observacion;

  List<Map<String, dynamic>> _detalles = [];
  List<Map<String, dynamic>> _productosDisponibles = [];
  final Set<String> _detallesQuitados = {};
  final TextEditingController _comprobanteController =
    TextEditingController();
    final Map<String, TextEditingController> _cantidadFacturadaControllers = {};

  @override
  void initState() {
    super.initState();
    _cargarDetalles();
    _cargarProductosDisponibles();
  }
  double _precioProductoParaPedido(Map<String, dynamic> producto) {
  final tipoPrecio =
      widget.pedido['tipo_precio']?.toString().toLowerCase() ?? 'normal';

  dynamic valor;

  switch (tipoPrecio) {
    case 'promo':
      valor = producto['precio_promo'];
      break;
    case 'interior':
      valor = producto['precio_interior'];
      break;
    default:
      valor = producto['precio_normal'];
  }

  return double.tryParse(valor?.toString() ?? '') ?? 0;
}
Future<void> _cargarProductosDisponibles() async {
  try {
    final respuesta = await Supabase.instance.client
        .from('productos')
        .select(
          'id, codigo, nombre, precio_normal, precio_promo, precio_interior',
        )
        .eq('activo', true)
        .order('nombre');

    if (!mounted) return;

    setState(() {
      _productosDisponibles =
          List<Map<String, dynamic>>.from(respuesta);
    });
  } catch (_) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No se pudieron cargar los productos.'),
      ),
    );
  }
}
Future<void> _mostrarSelectorProductos() async {
  String busqueda = '';

  final productoSeleccionado =
    await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setStateDialog) {
          final productosFiltrados = _productosDisponibles.where((producto) {
            final nombre =
                producto['nombre']?.toString().toLowerCase() ?? '';
            final codigo =
                producto['codigo']?.toString().toLowerCase() ?? '';

            final texto = busqueda.toLowerCase().trim();

            return nombre.contains(texto) || codigo.contains(texto);
          }).toList();

          return AlertDialog(
            title: const Text('Agregar producto'),
            content: SizedBox(
              width: 500,
              height: 550,
              child: Column(
                children: [
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Buscar producto...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (valor) {
                      setStateDialog(() {
                        busqueda = valor;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: productosFiltrados.isEmpty
                        ? const Center(
                            child: Text('No se encontraron productos'),
                          )
                        : ListView.separated(
                            itemCount: productosFiltrados.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final producto =
                                  productosFiltrados[index];

                              final nombre =
                                  producto['nombre']?.toString() ??
                                      'Producto sin nombre';

                              final codigo =
                                  producto['codigo']?.toString() ?? '';

                              final precio =
                                  _precioProductoParaPedido(producto);

                              return ListTile(
                                onTap: () => Navigator.pop(context, producto),
  title: Text(nombre),
  subtitle: Text(
    codigo.isEmpty
        ? _formatearPrecio(precio)
        : 'Código: $codigo - ${_formatearPrecio(precio)}',
  ),
  
);
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cerrar'),
              ),
            ],
          );
        },
      );
    },
  );
  if (productoSeleccionado == null) return;
  final productoId = productoSeleccionado['id'].toString();
final precio = _precioProductoParaPedido(productoSeleccionado);
final indiceExistente = _detalles.indexWhere(
  (detalle) => detalle['producto_id']?.toString() == productoId,
);

if (indiceExistente != -1) {
  final detalleExistente = _detalles[indiceExistente];
  final detalleIdExistente = detalleExistente['id'].toString();

  final controller =
      _cantidadFacturadaControllers[detalleIdExistente];

  final cantidadActual =
      double.tryParse(controller?.text ?? '') ?? 0;

  setState(() {
    controller?.text = (cantidadActual + 1).toStringAsFixed(0);
  });

  return;
}
final detalleId = 'nuevo_$productoId';
setState(() {
  _detalles.add({
    'id': detalleId,
    'pedido_id': widget.pedido['id'],
    'producto_id': productoId,
    'cantidad': 1,
    'cantidad_facturada': 1,
    'precio_unitario': precio,
    'subtotal': precio,
    'tipo_precio': widget.pedido['tipo_precio'],
    'productos': {
      'nombre': productoSeleccionado['nombre'],
      'codigo_original': productoSeleccionado['codigo'],
    },
  });

  _cantidadFacturadaControllers[detalleId] = TextEditingController(
    text: '1',
  );
});
}
  

  Future<void> _cargarDetalles() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final pedidoRespuesta = await Supabase.instance.client
    .from('pedidos')
    .select('observacion')
    .eq('id', widget.pedido['id'])
    .single();
      final respuesta = await Supabase.instance.client
          .from('pedido_detalles')
          .select('''
            id,
            pedido_id,
            producto_id,
            cantidad,
            cantidad_facturada,
            precio_unitario,
            subtotal,
            tipo_precio,
            productos (
              nombre,
              codigo_original
            )
          ''')
          .eq('pedido_id', widget.pedido['id']);

      if (!mounted) return;

      setState(() {
  _detalles = List<Map<String, dynamic>>.from(respuesta);
  _observacion = pedidoRespuesta['observacion']?.toString();

  for (final detalle in _detalles) {
    final id = detalle['id'].toString();
    final cantidad = double.tryParse(
          detalle['cantidad'].toString(),
        ) ??
        0;

    final cantidadFacturada = double.tryParse(
          detalle['cantidad_facturada']?.toString() ?? '',
        ) ??
        cantidad;

    _cantidadFacturadaControllers[id] = TextEditingController(
      text: cantidadFacturada.toStringAsFixed(0),
    );
  }

  _cargando = false;
});
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = 'No se pudo cargar el detalle del pedido.';
        _cargando = false;
      });
    }
  }
  Future<void> _facturarPedido() async {
  final numeroComprobante = _comprobanteController.text.trim();

  if (numeroComprobante.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Ingresá el número de comprobante.'),
      ),
    );
    return;
  }

  try {
    for (final detalle in _detalles) {
  final detalleId = detalle['id'].toString();

  if (detalleId.startsWith('nuevo_')) {
    continue;
  }

  final cantidadFacturada = double.tryParse(
        _cantidadFacturadaControllers[detalleId]?.text ?? '',
      ) ??
      0;

  await Supabase.instance.client
      .from('pedido_detalles')
      .update({
        'cantidad_facturada': cantidadFacturada,
      })
      .eq('id', detalleId);
}
for (final detalle in _detalles) {
  final detalleId = detalle['id'].toString();

  if (!detalleId.startsWith('nuevo_')) {
    continue;
  }

  final cantidadFacturada = double.tryParse(
        _cantidadFacturadaControllers[detalleId]?.text ?? '',
      ) ??
      0;

  if (cantidadFacturada <= 0) {
    continue;
  }

  final precio = double.tryParse(
        detalle['precio_unitario']?.toString() ?? '',
      ) ??
      0;

  await Supabase.instance.client
      .from('pedido_detalles')
      .insert({
        'pedido_id': widget.pedido['id'],
        'producto_id': detalle['producto_id'],
        'cantidad': cantidadFacturada,
        'precio_unitario': precio,
        'subtotal': cantidadFacturada * precio,
        'tipo_precio': detalle['tipo_precio'],
        'cantidad_facturada': cantidadFacturada,
      });
}
for (final detalleId in _detallesQuitados) {
  await Supabase.instance.client
      .from('pedido_detalles')
      .update({
        'cantidad_facturada': 0,
      })
      .eq('id', detalleId);
}
    await Supabase.instance.client
        .from('pedidos')
        .update({
          'facturado': true,
          'fecha_facturacion': DateTime.now().toIso8601String(),
          'numero_comprobante': numeroComprobante,
        })
        .eq('id', widget.pedido['id']);
final pedidoFacturado = Map<String, dynamic>.from(widget.pedido);
pedidoFacturado['numero_comprobante'] = numeroComprobante;

final pdfBytes = await InvoicePdfService.generarBoleta(
  pedido: pedidoFacturado,
  detalles: _detalles,
);

await Printing.layoutPdf(
  onLayout: (_) async => pdfBytes,
  name: 'Boleta $numeroComprobante',
);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Pedido facturado correctamente.'),
      ),
    );

    Navigator.of(context).pop(true);
  } catch (e) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('No se pudo facturar el pedido: $e'),
      ),
    );
  }
}
String _formatearFecha(dynamic fecha) {
  if (fecha == null) return '-';

  final date = DateTime.tryParse(fecha.toString());
  if (date == null) return '-';

  final dia = date.day.toString().padLeft(2, '0');
  final mes = date.month.toString().padLeft(2, '0');
  final anio = date.year.toString();

  return '$dia/$mes/$anio';
}

  String _formatearPrecio(dynamic valor) {
    final numero = double.tryParse(valor?.toString() ?? '') ?? 0;
    final entero = numero.round().toString();

    final buffer = StringBuffer();
    int contador = 0;

    for (int i = entero.length - 1; i >= 0; i--) {
      buffer.write(entero[i]);
      contador++;

      if (contador == 3 && i != 0) {
        buffer.write('.');
        contador = 0;
      }
    }

    return '\$${buffer.toString().split('').reversed.join()}';
  }

  @override
  Widget build(BuildContext context) {
    final cliente =
        widget.pedido['clientes'] as Map<String, dynamic>?;

    final nombreCliente =
        cliente?['nombre_comercio']?.toString() ?? 'Cliente sin nombre';

    final total = _detalles.fold<double>(0, (suma, detalle) {
  final id = detalle['id'].toString();

  final cantidad = double.tryParse(
        _cantidadFacturadaControllers[id]?.text ?? '',
      ) ??
      0;

  final precio = double.tryParse(
        detalle['precio_unitario']?.toString() ?? '',
      ) ??
      0;

  return suma + (cantidad * precio);
});

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle de facturación'),
      ),
      body: _construirContenido(nombreCliente, total),
    );
  }

  Widget _construirContenido(
    String nombreCliente,
    dynamic total,
  ) {
    if (_cargando) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _cargarDetalles,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nombreCliente,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tipo de precio: '
                  '${widget.pedido['tipo_precio']?.toString().toUpperCase() ?? ''}',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_observacion != null && _observacion!.trim().isNotEmpty) ...[
  Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'OBSERVACIONES',
            style: TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(_observacion!),
        ],
      ),
    ),
  ),
  const SizedBox(height: 12),
],
        const Text(
          'Productos',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        if (!widget.soloLectura) ...[
  SizedBox(
    width: double.infinity,
    child: OutlinedButton.icon(
      onPressed: _mostrarSelectorProductos,
      icon: const Icon(Icons.add),
      label: const Text('Agregar producto'),
    ),
  ),
  const SizedBox(height: 12),
],

        ..._detalles.map((detalle) {
          final producto =
              detalle['productos'] as Map<String, dynamic>?;

          final nombre =
              producto?['nombre']?.toString() ?? 'Producto sin nombre';

          final codigo =
              producto?['codigo_original']?.toString() ?? '';

          final cantidad =
    double.tryParse(detalle['cantidad']?.toString() ?? '') ?? 0;



final precio =
    detalle['precio_unitario'];

final cantidadFacturada = double.tryParse(
      _cantidadFacturadaControllers[detalle['id'].toString()]?.text ?? '',
    ) ??
    0;

final precioNumerico =
    double.tryParse(precio?.toString() ?? '') ?? 0;

final subtotal = cantidadFacturada * precioNumerico;

          return Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nombre,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (codigo.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text('Código: $codigo'),
                  ],
                  const SizedBox(height: 6),
                  Text('Cantidad pedida: ${cantidad.toStringAsFixed(0)}'),
const SizedBox(height: 8),
TextField(
  controller: _cantidadFacturadaControllers[detalle['id'].toString()],
  keyboardType: TextInputType.number,
  onChanged: (_) {
  setState(() {});
},
  decoration: const InputDecoration(
    labelText: 'Cantidad a facturar',
    border: OutlineInputBorder(),
    isDense: true,
  ),
),
                  Text(
                    'Precio unitario: ${_formatearPrecio(precio)}',
                  ),
                  Text(
                    'Subtotal: ${_formatearPrecio(subtotal)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
Align(
  alignment: Alignment.centerRight,
  child: TextButton.icon(
    onPressed: () {
  setState(() {
    final detalleId = detalle['id'].toString();

    if (!detalleId.startsWith('nuevo_')) {
      _detallesQuitados.add(detalleId);
    }

    _detalles.removeWhere(
      (item) => item['id'].toString() == detalleId,
    );

    _cantidadFacturadaControllers[detalleId]?.dispose();
    _cantidadFacturadaControllers.remove(detalleId);
  });
},
    icon: const Icon(Icons.delete_outline),
    label: const Text('Quitar de la boleta'),
  ),
),
                ],
              ),
            ),
          );
        }),

        const SizedBox(height: 12),

        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'TOTAL',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  _formatearPrecio(total),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

if (widget.soloLectura) ...[
  const SizedBox(height: 16),

  Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Factura realizada',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),

          Text(
            'Comprobante: ${widget.pedido['numero_comprobante'] ?? '-'}',
          ),

          const SizedBox(height: 4),

          Text(
            'Fecha: ${_formatearFecha(widget.pedido['fecha_facturacion'])}',
          ),
        ],
      ),
    ),
  ),

  const SizedBox(height: 12),

  SizedBox(
    width: double.infinity,
    child: FilledButton.icon(
      onPressed: () async {
  final pdfBytes = await InvoicePdfService.generarBoleta(
    pedido: widget.pedido,
    detalles: _detalles,
  );

  if (!mounted) return;

  await Printing.layoutPdf(
    onLayout: (_) async => pdfBytes,
    name: 'Boleta ${widget.pedido['numero_comprobante'] ?? ''}',
  );
},
      icon: const Icon(Icons.print_outlined),
      label: const Text('REIMPRIMIR'),
    ),
  ),
],
if (!widget.soloLectura) ...[
TextField(
  controller: _comprobanteController,
  decoration: const InputDecoration(
    labelText: 'Número de comprobante',
    hintText: 'Ej: 0001-00001234',
    prefixIcon: Icon(Icons.receipt_long_outlined),
    border: OutlineInputBorder(),
  ),
),

const SizedBox(height: 16),

SizedBox(
  width: double.infinity,
  child: FilledButton.icon(
    onPressed: _facturarPedido,
    icon: const Icon(Icons.check_circle_outline),
    label: const Text('FACTURAR'),
  ),
),
],
      ],
    );
  }
}