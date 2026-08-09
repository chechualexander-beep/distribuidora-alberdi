import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
          .select(
            '''
            id,
            cantidad,
            precio_unitario,
            subtotal,
            tipo_precio,
            productos (
              nombre,
              codigo
            )
            ''',
          )
          .eq('pedido_id', widget.pedido['id']);

      if (!mounted) return;

      setState(() {
        _detalles = List<Map<String, dynamic>>.from(respuesta);
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

  @override
  Widget build(BuildContext context) {
    final cliente =
        widget.pedido['clientes'] as Map<String, dynamic>?;

    final nombreCliente =
        cliente?['nombre_comercio']?.toString() ?? 'Cliente sin nombre';

    final direccion =
        cliente?['direccion']?.toString() ?? '';

    final estado =
        widget.pedido['estado']?.toString() ?? 'pendiente';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle del pedido'),
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
                              Text(
                                'Estado: ${estado.toUpperCase()}',
                              ),
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
                            child: Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'TOTAL',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  _formatearPrecio(
                                    widget.pedido['total'],
                                  ),
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                  ),
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