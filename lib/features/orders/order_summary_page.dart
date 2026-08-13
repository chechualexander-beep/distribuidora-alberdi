import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:share_plus/share_plus.dart';

class OrderSummaryPage extends StatefulWidget {
  final Map<String, dynamic> cliente;
  final List<Map<String, dynamic>> productos;
  final Map<String, int> cantidades;
  final String tipoPrecio;
  final Map<String, double> preciosFijados;
  final Map<String, String> tiposPrecioFijados;

  const OrderSummaryPage({
    super.key,
    required this.cliente,
    required this.productos,
    required this.cantidades,
    required this.tipoPrecio,
    required this.preciosFijados,
    required this.tiposPrecioFijados,
  });

  @override
  State<OrderSummaryPage> createState() => _OrderSummaryPageState();
}

class _OrderSummaryPageState extends State<OrderSummaryPage> {
  bool _guardando = false;

  List<Map<String, dynamic>> get _productosSeleccionados {
    return widget.productos.where((producto) {
      final id = producto['id'].toString();
      return (widget.cantidades[id] ?? 0) > 0;
    }).toList();
  }

  double _precioProducto(Map<String, dynamic> producto) {
    final id = producto['id'].toString();

    if (widget.preciosFijados.containsKey(id)) {
      return widget.preciosFijados[id]!;
    }

    dynamic valor;

    switch (widget.tipoPrecio) {
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

  String _tipoPrecioProducto(Map<String, dynamic> producto) {
    final id = producto['id'].toString();

    return widget.tiposPrecioFijados[id] ?? widget.tipoPrecio;
  }

  String _nombreListaProducto(Map<String, dynamic> producto) {
    switch (_tipoPrecioProducto(producto)) {
      case 'promo':
        return 'Promo';
      case 'interior':
        return 'Interior';
      default:
        return 'Normal';
    }
  }

  int get _totalUnidades {
    return widget.cantidades.values.fold(
      0,
      (total, cantidad) => total + cantidad,
    );
  }

  double get _totalPedido {
    double total = 0;

    for (final producto in _productosSeleccionados) {
      final id = producto['id'].toString();
      final cantidad = widget.cantidades[id] ?? 0;

      total += _precioProducto(producto) * cantidad;
    }

    return total;
  }

  String _formatearPrecio(double valor) {
    final entero = valor.round().toString();

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
  Future<void> _compartirPedido() async {
  final buffer = StringBuffer();

  final nombreCliente =
      widget.cliente['nombre_comercio']?.toString() ?? 'Cliente';

  buffer.writeln('DISTRIBUIDORA ALBERDI');
  buffer.writeln();
  buffer.writeln('Cliente: $nombreCliente');
  buffer.writeln();
  buffer.writeln('PEDIDO');
  buffer.writeln();

  for (final producto in _productosSeleccionados) {
    final id = producto['id'].toString();
    final cantidad = widget.cantidades[id] ?? 0;
    final precio = _precioProducto(producto);
    final subtotal = precio * cantidad;
    final nombre = producto['nombre']?.toString() ?? 'Producto';

    buffer.writeln(
      '$cantidad x $nombre - ${_formatearPrecio(subtotal)}',
    );
  }

  buffer.writeln();
  buffer.writeln('TOTAL: ${_formatearPrecio(_totalPedido)}');
  buffer.writeln();
  buffer.writeln('Gracias por su compra.');

  await SharePlus.instance.share(
    ShareParams(text: buffer.toString()),
  );
}

  Future<void> _confirmarPedido() async {
    if (_guardando) return;

    final usuario = Supabase.instance.client.auth.currentUser;

    if (usuario == null) {
      _mostrarMensaje('No hay una sesión iniciada.');
      return;
    }

    if (_productosSeleccionados.isEmpty) {
      _mostrarMensaje('El pedido no tiene productos.');
      return;
    }

    setState(() {
      _guardando = true;
    });

    try {
      final pedido = await Supabase.instance.client
          .from('pedidos')
          .insert({
            'cliente_id': widget.cliente['id'],
            'preventista_id': usuario.id,
            'tipo_precio': widget.tipoPrecio,
            'estado': 'pendiente',
            'total': _totalPedido,
          })
          .select('id')
          .single();

      final pedidoId = pedido['id'];

      final detalles = _productosSeleccionados.map((producto) {
        final productoId = producto['id'].toString();
        final cantidad = widget.cantidades[productoId] ?? 0;
        final precio = _precioProducto(producto);
        final subtotal = precio * cantidad;

        return {
          'pedido_id': pedidoId,
          'producto_id': producto['id'],
          'cantidad': cantidad,
          'precio_unitario': precio,
          'subtotal': subtotal,
          'tipo_precio': _tipoPrecioProducto(producto),
        };
      }).toList();

      await Supabase.instance.client
          .from('pedido_detalles')
          .insert(detalles);

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            icon: const Icon(
              Icons.check_circle_outline,
              size: 48,
            ),
            title: const Text('Pedido guardado'),
            content: Text(
              'El pedido fue registrado correctamente.\n\n'
              'Total: ${_formatearPrecio(_totalPedido)}',
            ),
            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text('ACEPTAR'),
              ),
            ],
          );
        },
      );

      if (!mounted) return;

      Navigator.of(context).popUntil(
        (route) => route.isFirst,
      );
    } on PostgrestException catch (error) {
      _mostrarMensaje(
        'No se pudo guardar el pedido: ${error.message}',
      );
    } catch (_) {
      _mostrarMensaje(
        'Ocurrió un error al guardar el pedido.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _guardando = false;
        });
      }
    }
  }

  void _mostrarMensaje(String mensaje) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Resumen del pedido'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Cliente',
                      style: TextStyle(
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.cliente['nombre_comercio']?.toString() ??
                          'Sin nombre',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Cada producto conserva el precio con el que fue agregado.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _productosSeleccionados.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final producto = _productosSeleccionados[index];

                final id = producto['id'].toString();
                final cantidad = widget.cantidades[id] ?? 0;
                final precio = _precioProducto(producto);
                final subtotal = precio * cantidad;
                final lista = _nombreListaProducto(producto);

                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          producto['nombre']?.toString() ??
                              'Sin nombre',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Text(
                              '$cantidad × ${_formatearPrecio(precio)}',
                            ),
                            const Spacer(),
                            Text(
                              _formatearPrecio(subtotal),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
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
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '$_totalUnidades unidades',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            _formatearPrecio(_totalPedido),
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _guardando
                        ? null
                        : () {
                            Navigator.of(context).pop();
                          },
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('VOLVER A PRODUCTOS'),
                  ),
                  const SizedBox(height: 10),

OutlinedButton.icon(
  onPressed: _guardando ? null : _compartirPedido,
  icon: const Icon(Icons.share),
  label: const Text('COMPARTIR PEDIDO'),
),

const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed:
                        _guardando ? null : _confirmarPedido,
                    icon: _guardando
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(
                            Icons.check_circle_outline,
                          ),
                    label: Text(
                      _guardando
                          ? 'GUARDANDO...'
                          : 'CONFIRMAR PEDIDO',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}