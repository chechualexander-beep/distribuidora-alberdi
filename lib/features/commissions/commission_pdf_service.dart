import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class CommissionPdfService {
  static Future<Uint8List> generarPdf({
    required String preventista,
    required DateTime desde,
    required DateTime hasta,
    required double ventaPedida,
    required double ventaEntregada,
    required double ventaNoEntregada,
    required double comisionTotal,
    required List<Map<String, dynamic>> detalles,
  }) async {
    final pdf = pw.Document();

    final detallesPorPedido =
        _agruparPorPedido(detalles);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'DISTRIBUIDORA ALBERDI',
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                'Liquidacion de comisiones',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Divider(),
            ],
          );
        },
        footer: (context) {
          return pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'Pagina ${context.pageNumber} de ${context.pagesCount}',
              style: const pw.TextStyle(
                fontSize: 9,
              ),
            ),
          );
        },
        build: (context) {
          return [
            pw.SizedBox(height: 8),

            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(
                  color: PdfColors.grey400,
                ),
                borderRadius:
                    pw.BorderRadius.circular(6),
              ),
              child: pw.Column(
                crossAxisAlignment:
                    pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Preventista',
                    style: const pw.TextStyle(
                      fontSize: 10,
                      color: PdfColors.grey700,
                    ),
                  ),
                  pw.SizedBox(height: 3),
                  pw.Text(
                    preventista,
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text(
                    'Periodo: ${_formatearFecha(desde)} al ${_formatearFecha(hasta)}',
                  ),
                ],
              ),
            ),

            pw.SizedBox(height: 18),

            pw.Text(
              'Resumen',
              style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
              ),
            ),

            pw.SizedBox(height: 8),

            _filaResumen(
              'Venta pedida',
              _formatearPrecio(ventaPedida),
            ),
            _filaResumen(
              'Venta entregada',
              _formatearPrecio(ventaEntregada),
            ),
            _filaResumen(
              'No entregado',
              _formatearPrecio(ventaNoEntregada),
            ),
            _filaResumen(
              'COMISION A PAGAR',
              _formatearPrecio(comisionTotal),
              destacado: true,
            ),

            pw.SizedBox(height: 22),

            pw.Text(
              'Detalle por cliente y pedido',
              style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
              ),
            ),

            pw.SizedBox(height: 10),

            ...detallesPorPedido.entries.map(
              (entrada) {
                final detallesPedido = entrada.value;

                if (detallesPedido.isEmpty) {
                  return pw.SizedBox();
                }

                return _pedidoWidget(
                  detallesPedido,
                );
              },
            ),

            pw.SizedBox(height: 20),

            pw.Container(
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(
                  width: 1.5,
                  color: PdfColors.grey800,
                ),
                borderRadius:
                    pw.BorderRadius.circular(6),
              ),
              child: pw.Row(
                mainAxisAlignment:
                    pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'TOTAL A PAGAR',
                    style: pw.TextStyle(
                      fontSize: 15,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    _formatearPrecio(comisionTotal),
                    style: pw.TextStyle(
                      fontSize: 22,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _pedidoWidget(
    List<Map<String, dynamic>> detallesPedido,
  ) {
    final primerDetalle = detallesPedido.first;

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
            ? pedidoId.substring(0, 8).toUpperCase()
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

    final entregados = detallesPedido.where(
      (detalle) {
        return _numero(
              detalle['cantidad_entregada'],
            ) >
            0;
      },
    ).toList();

    final noEntregados = detallesPedido.where(
      (detalle) {
        return _numero(
              detalle['cantidad_no_entregada'],
            ) >
            0;
      },
    ).toList();

    return pw.Container(
      margin: const pw.EdgeInsets.only(
        bottom: 14,
      ),
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(
          color: PdfColors.grey400,
        ),
        borderRadius:
            pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment:
            pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            clienteNombre,
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            'Pedido #$numeroPedido',
            style: const pw.TextStyle(
              fontSize: 9,
              color: PdfColors.grey700,
            ),
          ),

          pw.SizedBox(height: 8),

          pw.Text(
            'Pedido: ${_formatearPrecio(pedidoTotal)}',
          ),
          pw.Text(
            'Entregado: ${_formatearPrecio(entregadoTotal)}',
          ),
          pw.Text(
            'No entregado: ${_formatearPrecio(noEntregadoTotal)}',
          ),
          pw.Text(
            'Comision: ${_formatearPrecio(comisionPedido)}',
            style: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
            ),
          ),

          if (entregados.isNotEmpty) ...[
            pw.SizedBox(height: 10),
            pw.Divider(),
            pw.Text(
              'ENTREGADOS',
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 6),

            ...entregados.map(
              (detalle) =>
                  _productoEntregado(detalle),
            ),
          ],

          if (noEntregados.isNotEmpty) ...[
            pw.SizedBox(height: 6),
            pw.Divider(),
            pw.Text(
              'NO ENTREGADOS',
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 6),

            ...noEntregados.map(
              (detalle) =>
                  _productoNoEntregado(detalle),
            ),
          ],
        ],
      ),
    );
  }

  static pw.Widget _productoEntregado(
    Map<String, dynamic> detalle,
  ) {
    final producto =
        detalle['productos']
            as Map<String, dynamic>?;

    final nombre =
        producto?['nombre']?.toString() ??
            'Producto';

    final entregada =
        _numero(
          detalle['cantidad_entregada'],
        );

    final precio =
        _numero(
          detalle['precio_unitario'],
        );

    final porcentaje =
        _numero(
          detalle['porcentaje_comision'],
        );

    final comision =
        _numero(
          detalle['importe_comision'],
        );

    return pw.Padding(
      padding:
          const pw.EdgeInsets.only(bottom: 5),
      child: pw.Column(
        crossAxisAlignment:
            pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            nombre,
            style: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.Text(
            '${_cantidad(entregada)} x ${_formatearPrecio(precio)} - ${_porcentaje(porcentaje)} - Comision ${_formatearPrecio(comision)}',
            style: const pw.TextStyle(
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _productoNoEntregado(
    Map<String, dynamic> detalle,
  ) {
    final producto =
        detalle['productos']
            as Map<String, dynamic>?;

    final nombre =
        producto?['nombre']?.toString() ??
            'Producto';

    final cantidad =
        _numero(
          detalle['cantidad_no_entregada'],
        );

    final precio =
        _numero(
          detalle['precio_unitario'],
        );

    return pw.Padding(
      padding:
          const pw.EdgeInsets.only(bottom: 5),
      child: pw.Column(
        crossAxisAlignment:
            pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            nombre,
            style: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.Text(
            '${_cantidad(cantidad)} x ${_formatearPrecio(precio)} - Comision \$0',
            style: const pw.TextStyle(
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _filaResumen(
    String titulo,
    String valor, {
    bool destacado = false,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(
        vertical: 7,
        horizontal: 10,
      ),
      margin:
          const pw.EdgeInsets.only(bottom: 4),
      decoration: pw.BoxDecoration(
        color: destacado
            ? PdfColors.grey300
            : PdfColors.grey100,
        borderRadius:
            pw.BorderRadius.circular(4),
      ),
      child: pw.Row(
        mainAxisAlignment:
            pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            titulo,
            style: pw.TextStyle(
              fontWeight: destacado
                  ? pw.FontWeight.bold
                  : pw.FontWeight.normal,
            ),
          ),
          pw.Text(
            valor,
            style: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: destacado ? 14 : 11,
            ),
          ),
        ],
      ),
    );
  }

  static Map<String, List<Map<String, dynamic>>>
      _agruparPorPedido(
    List<Map<String, dynamic>> detalles,
  ) {
    final grupos =
        <String, List<Map<String, dynamic>>>{};

    for (final detalle in detalles) {
      final pedido =
          detalle['pedidos']
              as Map<String, dynamic>?;

      final pedidoId =
          pedido?['id']?.toString() ??
              'sin-pedido';

      grupos.putIfAbsent(
        pedidoId,
        () => <Map<String, dynamic>>[],
      );

      grupos[pedidoId]!.add(detalle);
    }

    return grupos;
  }

  static double _numero(dynamic valor) {
    return double.tryParse(
          valor?.toString() ?? '0',
        ) ??
        0;
  }

  static String _cantidad(double valor) {
    if (valor == valor.roundToDouble()) {
      return valor.toInt().toString();
    }

    return valor.toStringAsFixed(2);
  }

  static String _porcentaje(double valor) {
    if (valor == valor.roundToDouble()) {
      return '${valor.toInt()}%';
    }

    return '${valor.toStringAsFixed(2)}%';
  }

  static String _formatearFecha(DateTime fecha) {
    final dia =
        fecha.day.toString().padLeft(2, '0');

    final mes =
        fecha.month.toString().padLeft(2, '0');

    return '$dia/$mes/${fecha.year}';
  }

  static String _formatearPrecio(
    double valor,
  ) {
    final entero = valor.round().toString();

    final buffer = StringBuffer();
    int contador = 0;

    for (
      int i = entero.length - 1;
      i >= 0;
      i--
    ) {
      buffer.write(entero[i]);
      contador++;

      if (contador == 3 && i != 0) {
        buffer.write('.');
        contador = 0;
      }
    }

    return '\$${buffer.toString().split('').reversed.join()}';
  }
}