import 'package:flutter/material.dart';

class CommissionReportPage extends StatelessWidget {
  final String preventista;
  final DateTime desde;
  final DateTime hasta;

  final double ventaPedida;
  final double ventaEntregada;
  final double ventaNoEntregada;
  final double comisionTotal;

  final List<Map<String, dynamic>> detalles;

  const CommissionReportPage({
    super.key,
    required this.preventista,
    required this.desde,
    required this.hasta,
    required this.ventaPedida,
    required this.ventaEntregada,
    required this.ventaNoEntregada,
    required this.comisionTotal,
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

  String _formatearFecha(DateTime fecha) {
    final dia = fecha.day.toString().padLeft(2, '0');
    final mes = fecha.month.toString().padLeft(2, '0');
    final anio = fecha.year.toString();

    return '$dia/$mes/$anio';
  }

  Map<String, List<Map<String, dynamic>>> get _detallesPorPedido {
    final grupos = <String, List<Map<String, dynamic>>>{};

    for (final detalle in detalles) {
      final pedido =
          detalle['pedidos'] as Map<String, dynamic>?;

      final pedidoId =
          pedido?['id']?.toString() ?? 'sin-pedido';

      grupos.putIfAbsent(
        pedidoId,
        () => <Map<String, dynamic>>[],
      );

      grupos[pedidoId]!.add(detalle);
    }

    return grupos;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Liquidación'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'DISTRIBUIDORA ALBERDI',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Liquidación de comisiones',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 24),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Preventista',
                    style: TextStyle(
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    preventista,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Período: ${_formatearFecha(desde)} al ${_formatearFecha(hasta)}',
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          _ResumenItem(
            titulo: 'Venta pedida',
            valor: _formatearPrecio(ventaPedida),
          ),
          _ResumenItem(
            titulo: 'Venta entregada',
            valor: _formatearPrecio(ventaEntregada),
          ),
          _ResumenItem(
            titulo: 'No entregado',
            valor: _formatearPrecio(ventaNoEntregada),
          ),
          _ResumenItem(
            titulo: 'COMISIÓN A PAGAR',
            valor: _formatearPrecio(comisionTotal),
            destacado: true,
          ),

          const SizedBox(height: 24),

          const Text(
            'Detalle por cliente y pedido',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 12),

          ..._detallesPorPedido.entries.map((entrada) {
            final detallesPedido = entrada.value;

            if (detallesPedido.isEmpty) {
              return const SizedBox.shrink();
            }

            final primerDetalle =
                detallesPedido.first;

            final pedido =
                primerDetalle['pedidos']
                    as Map<String, dynamic>?;

            final cliente =
                pedido?['clientes']
                    as Map<String, dynamic>?;

            final clienteNombre =
                cliente?['nombre_comercio']
                        ?.toString() ??
                    'Cliente';

            final pedidoId =
                pedido?['id']?.toString() ?? '';

            final numeroPedido =
                pedidoId.length >= 8
                    ? pedidoId
                        .substring(0, 8)
                        .toUpperCase()
                    : pedidoId.toUpperCase();

            double pedidoTotal = 0;
            double entregadoTotal = 0;
            double noEntregadoTotal = 0;
            double comisionPedido = 0;

            for (final detalle in detallesPedido) {
              final cantidad =
                  _numero(detalle['cantidad']);

              final entregada =
                  _numero(
                    detalle['cantidad_entregada'],
                  );

              final noEntregada =
                  _numero(
                    detalle['cantidad_no_entregada'],
                  );

              final precio =
                  _numero(
                    detalle['precio_unitario'],
                  );

              pedidoTotal += cantidad * precio;
              entregadoTotal += entregada * precio;
              noEntregadoTotal +=
                  noEntregada * precio;

              comisionPedido +=
                  _numero(
                    detalle['importe_comision'],
                  );
            }

            return Card(
              margin:
                  const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      clienteNombre,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Pedido #$numeroPedido',
                      style: const TextStyle(
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Pedido: ${_formatearPrecio(pedidoTotal)}',
                    ),
                    Text(
                      'Entregado: ${_formatearPrecio(entregadoTotal)}',
                    ),
                    Text(
                      'No entregado: ${_formatearPrecio(noEntregadoTotal)}',
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Comisión: ${_formatearPrecio(comisionPedido)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),

          const SizedBox(height: 24),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'TOTAL A PAGAR',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _formatearPrecio(comisionTotal),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          FilledButton.icon(
            onPressed: () {
              // Próximo paso:
              // generar PDF o compartir la liquidación.
            },
            icon: const Icon(
              Icons.picture_as_pdf_outlined,
            ),
            label: const Text(
              'GENERAR REPORTE',
            ),
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _ResumenItem extends StatelessWidget {
  final String titulo;
  final String valor;
  final bool destacado;

  const _ResumenItem({
    required this.titulo,
    required this.valor,
    this.destacado = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(
          titulo,
          style: TextStyle(
            fontWeight:
                destacado
                    ? FontWeight.bold
                    : FontWeight.normal,
          ),
        ),
        trailing: Text(
          valor,
          style: TextStyle(
            fontSize: destacado ? 20 : 17,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}