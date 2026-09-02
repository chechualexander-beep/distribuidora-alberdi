import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:share_plus/share_plus.dart';

class OrderDetailPage extends StatefulWidget {
  final Map<String, dynamic> pedido;

  const OrderDetailPage({
    super.key,
    required this.pedido,
  });

  @override
  State<OrderDetailPage> createState() => _OrderDetailPageState();
}

class _OrderDetailPageState extends State<OrderDetailPage> {
  bool _cargando = true;
  String? _error;

  List<Map<String, dynamic>> _detalles = [];
  String? _observacion;
  List<Map<String, dynamic>> _pagos = [];

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
      final pedidoRespuesta = await Supabase.instance.client
    .from('pedidos')
    .select('observacion')
    .eq('id', widget.pedido['id'])
    .single();

      final respuesta = await Supabase.instance.client
          .from('pedido_detalles')
          .select(
            '''
            id,
cantidad,
cantidad_entregada,
cantidad_no_entregada,
precio_unitario,
subtotal,
tipo_precio,
porcentaje_comision,
importe_comision,
productos (
              nombre,
              codigo
            )
            ''',
          )
          .eq('pedido_id', widget.pedido['id']);
          final pagosRespuesta = await Supabase.instance.client
    .from('pedido_pagos')
    .select(
      '''
      importe,
      medio_pago,
      fecha_pago,
      observacion
      ''',
    )
    .eq('pedido_id', widget.pedido['id']);

      if (!mounted) return;

      setState(() {
  _detalles = List<Map<String, dynamic>>.from(respuesta);
_pagos = List<Map<String, dynamic>>.from(pagosRespuesta);
_observacion = pedidoRespuesta['observacion']?.toString();
_cargando = false;
});
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _error = 'No se pudo cargar el detalle del pedido.';
        _cargando = false;
      });
    }
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

  String _nombreLista(dynamic valor) {
    switch (valor?.toString()) {
      case 'promo':
        return 'Promo';
      case 'interior':
        return 'Interior';
      default:
        return 'Normal';
    }
  }

  String _formatearFecha(dynamic valor) {
    if (valor == null) return '';

    final fecha = DateTime.tryParse(valor.toString());
    if (fecha == null) return valor.toString();

    final local = fecha.toLocal();

    final dia = local.day.toString().padLeft(2, '0');
    final mes = local.month.toString().padLeft(2, '0');
    final anio = local.year.toString();

    final hora = local.hour.toString().padLeft(2, '0');
    final minuto = local.minute.toString().padLeft(2, '0');

    return '$dia/$mes/$anio $hora:$minuto';
  }
  Future<void> _compartirPedidoConfirmado() async {
  final cliente =
      widget.pedido['clientes'] as Map<String, dynamic>?;

  final nombreCliente =
      cliente?['nombre_comercio']?.toString() ??
      'Cliente sin nombre';

  final buffer = StringBuffer();

  buffer.writeln('DISTRIBUIDORA ALBERDI');
  buffer.writeln();
  buffer.writeln('Cliente: $nombreCliente');
  buffer.writeln();
  final tipoOperacion =
    widget.pedido['tipo_operacion']?.toString() ?? 'pedido';

buffer.writeln(
  tipoOperacion == 'venta_directa'
      ? 'VENTA DIRECTA'
      : 'PEDIDO',
);
  buffer.writeln();

  for (final detalle in _detalles) {
    final producto =
        detalle['productos'] as Map<String, dynamic>?;

    final nombre =
        producto?['nombre']?.toString() ?? 'Producto';

    final cantidad =
        double.tryParse(
          detalle['cantidad']?.toString() ?? '0',
        ) ??
        0;

    final subtotal =
        double.tryParse(
          detalle['subtotal']?.toString() ?? '0',
        ) ??
        0;

    final cantidadTexto = cantidad % 1 == 0
        ? cantidad.toInt().toString()
        : cantidad.toString();

    buffer.writeln(
      '$cantidadTexto x $nombre - ${_formatearPrecio(subtotal)}',
    );
  }

  final total =
      double.tryParse(
        widget.pedido['total']?.toString() ?? '0',
      ) ??
      0;

  buffer.writeln();
  buffer.writeln('TOTAL: ${_formatearPrecio(total)}');

  final observacion = _observacion?.trim() ?? '';

if (observacion.isNotEmpty) {
  buffer.writeln();
  buffer.writeln('Observación: $observacion');
}

  buffer.writeln();
  buffer.writeln('Gracias por su compra.');

  await SharePlus.instance.share(
    ShareParams(
      text: buffer.toString(),
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    final cliente =
        widget.pedido['clientes'] as Map<String, dynamic>?;

    final nombreCliente =
        cliente?['nombre_comercio']?.toString() ?? 'Cliente sin nombre';

    final direccion =
        cliente?['direccion']?.toString() ?? '';

    
        final tipoOperacion =
    widget.pedido['tipo_operacion']?.toString() ?? 'pedido';

final resultadoEntrega =
    widget.pedido['resultado_entrega']?.toString() ?? 'pendiente';

final facturado =
    widget.pedido['facturado'] == true;
        final totalEntregado = _detalles.fold<double>(
  0,
  (total, detalle) {
    final cantidadEntregada = double.tryParse(
          detalle['cantidad_entregada']?.toString() ?? '0',
        ) ??
        0;

    final precioUnitario = double.tryParse(
          detalle['precio_unitario']?.toString() ?? '0',
        ) ??
        0;

    return total + (cantidadEntregada * precioUnitario);
  },
  );
  final totalPagado = _pagos.fold<double>(
  0,
  (total, pago) {
    final importe = double.tryParse(
          pago['importe']?.toString() ?? '0',
        ) ??
        0;

    return total + importe;
  },
);

    return Scaffold(
      appBar: AppBar(
  title: const Text('Detalle del pedido'),
  actions: [
    if (!facturado && resultadoEntrega == 'pendiente')
  IconButton(
    onPressed: () async {
  final confirmar = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Eliminar pedido'),
      content: const Text(
        '¿Seguro que querés eliminar este pedido? Esta acción no se puede deshacer.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('CANCELAR'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('ELIMINAR'),
        ),
      ],
    ),
  );

  if (confirmar != true) return;
  try {
  await Supabase.instance.client.rpc(
    'eliminar_pedido_pendiente',
    params: {
      'p_pedido_id': widget.pedido['id'],
    },
  );

  if (!context.mounted) return;

  Navigator.of(context).pop(true);
} catch (e) {
  if (!context.mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        'No se pudo eliminar el pedido: $e',
      ),
    ),
  );
}
},
    icon: const Icon(Icons.delete_outline),
    tooltip: 'Eliminar pedido',
  ),
    IconButton(
      onPressed: _detalles.isEmpty
          ? null
          : _compartirPedidoConfirmado,
      icon: const Icon(Icons.share_outlined),
      tooltip: 'Compartir pedido',
    ),
  ],
),
      body: _cargando
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 60,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
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
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        16,
                        16,
                        16,
                        8,
                      ),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                nombreCliente,
                                style: const TextStyle(
                                  fontSize: 21,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (direccion.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(direccion),
                              ],
                              const SizedBox(height: 12),
                              Text(
                                _formatearFecha(
                                  widget.pedido['created_at'],
                                ),
                              ),
                              const SizedBox(height: 4),
                              if (tipoOperacion == 'venta_directa') ...[
  const Text(
    'VENTA DIRECTA',
    style: TextStyle(
      fontWeight: FontWeight.bold,
    ),
  ),
  const SizedBox(height: 4),
  Text(
    'Entrega: ${resultadoEntrega.toUpperCase()}',
  ),
] else ...[
  Text(
    facturado
        ? 'Facturación: FACTURADO'
        : 'Facturación: NO FACTURADO',
  ),
  const SizedBox(height: 4),
  Text(
    'Entrega: ${resultadoEntrega.toUpperCase()}',
  ),
],
                              if (_observacion != null && _observacion!.trim().isNotEmpty) ...[
  const SizedBox(height: 12),
  const Divider(),
  const SizedBox(height: 8),
  const Text(
    'OBSERVACIONES',
    style: TextStyle(
      fontWeight: FontWeight.bold,
    ),
  ),
  const SizedBox(height: 4),
  Text(
    _observacion!,
  ),
],
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: _detalles.isEmpty
                          ? const Center(
                              child: Text(
                                'El pedido no tiene productos.',
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: _detalles.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final detalle = _detalles[index];

                                final producto =
                                    detalle['productos']
                                        as Map<String, dynamic>?;

                                final nombreProducto =
                                    producto?['nombre']?.toString() ??
                                        'Producto sin nombre';

                                final codigo =
                                    producto?['codigo']?.toString() ?? '';

                                final cantidad =
    detalle['cantidad']?.toString() ?? '0';

final cantidadEntregada =
    detalle['cantidad_entregada']?.toString() ?? '0';

final cantidadNoEntregada =
    detalle['cantidad_no_entregada']?.toString() ?? '0';

final precio = _formatearPrecio(
  detalle['precio_unitario'],
);

final subtotal = _formatearPrecio(
  detalle['subtotal'],
);

                                final lista = _nombreLista(
                                  detalle['tipo_precio'],
                                );

                                return Card(
                                  child: Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          nombreProducto,
                                          style: const TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        if (codigo.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            'Código: $codigo',
                                            style: const TextStyle(
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Text(
                                              '$cantidad × $precio',
                                            ),
                                            
                                            const Spacer(),
                                            Text(
                                              subtotal,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (cantidadEntregada != '0' || cantidadNoEntregada != '0') ...[
  const SizedBox(height: 4),
  Text('Entregado: $cantidadEntregada'),
  const SizedBox(height: 2),
  Text('No entregado: $cantidadNoEntregada'),
],
                                        const SizedBox(height: 6),
                                        Text(
                                          'Lista usada: $lista',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          16,
                          8,
                          16,
                          16,
                        ),
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
  children: [
    Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'TOTAL DEL PEDIDO',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          _formatearPrecio(
            widget.pedido['total'],
          ),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    ),
    const SizedBox(height: 12),
    Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'TOTAL ENTREGADO',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          _formatearPrecio(totalEntregado),
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    ),
    const SizedBox(height: 12),
Row(
  mainAxisAlignment: MainAxisAlignment.spaceBetween,
  children: [
    const Text(
      'PAGADO',
      style: TextStyle(
        fontWeight: FontWeight.bold,
      ),
    ),
    Text(
      _formatearPrecio(totalPagado),
      style: const TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.bold,
      ),
    ),
  ],
),
const SizedBox(height: 12),
Row(
  mainAxisAlignment: MainAxisAlignment.spaceBetween,
  children: [
    const Text(
      'SALDO',
      style: TextStyle(
        fontWeight: FontWeight.bold,
      ),
    ),
    Text(
      _formatearPrecio(
        (totalEntregado - totalPagado) > 0
            ? totalEntregado - totalPagado
            : 0,
      ),
      style: const TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.bold,
      ),
    ),
  ],
),
  ],
),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}