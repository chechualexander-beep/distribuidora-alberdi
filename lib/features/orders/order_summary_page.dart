import 'package:flutter/material.dart';

class OrderSummaryPage extends StatelessWidget {
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

  List<Map<String, dynamic>> get _productosSeleccionados {
    return productos.where((producto) {
      final id = producto['id'].toString();
      return (cantidades[id] ?? 0) > 0;
    }).toList();
  }

  double _precioProducto(Map<String, dynamic> producto) {
    final id = producto['id'].toString();

    if (preciosFijados.containsKey(id)) {
      return preciosFijados[id]!;
    }

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

  String _nombreListaProducto(Map<String, dynamic> producto) {
    final id = producto['id'].toString();
    final tipo = tiposPrecioFijados[id] ?? tipoPrecio;

    switch (tipo) {
      case 'promo':
        return 'Promo';
      case 'interior':
        return 'Interior';
      default:
        return 'Normal';
    }
  }

  int get _totalUnidades {
    return cantidades.values.fold(
      0,
      (total, cantidad) => total + cantidad,
    );
  }

  double get _totalPedido {
    double total = 0;

    for (final producto in _productosSeleccionados) {
      final id = producto['id'].toString();
      final cantidad = cantidades[id] ?? 0;
      final precio = _precioProducto(producto);

      total += precio * cantidad;
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
                      cliente['nombre_comercio']?.toString() ??
                          'Sin nombre',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Los precios de cada producto quedaron fijados '
                      'al momento de agregarlos.',
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
                final cantidad = cantidades[id] ?? 0;
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
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('VOLVER A PRODUCTOS'),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: () {
                      // En el siguiente paso se guarda en Supabase.
                    },
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('CONFIRMAR PEDIDO'),
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