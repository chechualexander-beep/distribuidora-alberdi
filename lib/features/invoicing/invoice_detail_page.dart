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

  List<Map<String, dynamic>> _detalles = [];
  final TextEditingController _comprobanteController =
    TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargarDetalles();
  }

  Future<void> _cargarDetalles() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final respuesta = await Supabase.instance.client
          .from('pedido_detalles')
          .select('''
            id,
            pedido_id,
            producto_id,
            cantidad,
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
    await Supabase.instance.client
        .from('pedidos')
        .update({
          'facturado': true,
          'fecha_facturacion': DateTime.now().toIso8601String(),
          'numero_comprobante': numeroComprobante,
        })
        .eq('id', widget.pedido['id']);

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

    final total = widget.pedido['total'];

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
        const Text(
          'Productos',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),

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

          final subtotal =
              detalle['subtotal'];

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
                  Text('Cantidad: ${cantidad.toStringAsFixed(0)}'),
                  Text(
                    'Precio unitario: ${_formatearPrecio(precio)}',
                  ),
                  Text(
                    'Subtotal: ${_formatearPrecio(subtotal)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
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