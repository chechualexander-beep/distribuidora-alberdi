import 'package:flutter/material.dart';

class CommissionOrderDetail extends StatelessWidget {
  final List<Map<String, dynamic>> detalles;

  const CommissionOrderDetail({
    super.key,
    required this.detalles,
  });

  double _numero(dynamic valor) {
    return double.tryParse(
          valor?.toString() ?? '0',
        ) ??
        0;
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
    final entregados = detalles.where((detalle) {
      return _numero(detalle['cantidad_entregada']) > 0;
    }).toList();

    final noEntregados = detalles.where((detalle) {
      return _numero(detalle['cantidad_no_entregada']) > 0;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (entregados.isNotEmpty) ...[
          const Text(
            'ENTREGADOS',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          ...entregados.map(
            (detalle) => _productoEntregado(detalle),
          ),
        ],

        if (noEntregados.isNotEmpty) ...[
          if (entregados.isNotEmpty)
            const Divider(height: 24),

          const Text(
            'NO ENTREGADOS',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          ...noEntregados.map(
            (detalle) => _productoNoEntregado(detalle),
          ),
        ],
      ],
    );
  }

  Widget _productoEntregado(
    Map<String, dynamic> detalle,
  ) {
    final producto =
        detalle['productos'] as Map<String, dynamic>?;

    final nombre =
        producto?['nombre']?.toString() ?? 'Producto';

    final entregada =
        _numero(detalle['cantidad_entregada']);

    final precio =
        _numero(detalle['precio_unitario']);

    final porcentaje =
        _numero(detalle['porcentaje_comision']);

    final comision =
        _numero(detalle['importe_comision']);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            nombre,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Entregado: ${entregada.toStringAsFixed(0)} × ${_formatearPrecio(precio)}',
          ),
          const SizedBox(height: 2),
          Text(
            'Comisión: ${porcentaje.toStringAsFixed(0)}%',
          ),
          const SizedBox(height: 2),
          Text(
            'Generada: ${_formatearPrecio(comision)}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _productoNoEntregado(
    Map<String, dynamic> detalle,
  ) {
    final producto =
        detalle['productos'] as Map<String, dynamic>?;

    final nombre =
        producto?['nombre']?.toString() ?? 'Producto';

    final noEntregada =
        _numero(detalle['cantidad_no_entregada']);

    final precio =
        _numero(detalle['precio_unitario']);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            nombre,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'No entregado: ${noEntregada.toStringAsFixed(0)} × ${_formatearPrecio(precio)}',
          ),
          const SizedBox(height: 2),
          const Text(
            'Comisión generada: \$0',
          ),
        ],
      ),
    );
  }
}