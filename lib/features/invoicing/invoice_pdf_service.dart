import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class InvoicePdfService {
  static Future<Uint8List> generarBoleta({
    required Map<String, dynamic> pedido,
    required List<Map<String, dynamic>> detalles,
  }) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.fromLTRB(18, 18, 18, 16),
        build: (context) {
            final cliente =
    pedido['clientes'] as Map<String, dynamic>? ?? {};

final usuario =
    pedido['usuarios'] as Map<String, dynamic>? ?? {};

final nombreCliente =
    cliente['nombre_comercio']?.toString() ?? 'Cliente';

final direccion =
    cliente['direccion']?.toString() ?? '';

final vendedorNombre =
    usuario['nombre']?.toString() ?? '';

final vendedorApellido =
    usuario['apellido']?.toString() ?? '';

final vendedor = [
  vendedorNombre,
  vendedorApellido,
].where((texto) => texto.isNotEmpty).join(' ');

final comprobante =
    pedido['numero_comprobante']?.toString() ?? '';

final fecha =
    _formatearFecha(pedido['fecha_facturacion']);
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // ENCABEZADO
              pw.Row(
  crossAxisAlignment: pw.CrossAxisAlignment.start,
  children: [
    pw.Expanded(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Distribuidora Alberdi',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            'Circunvalación km 1280, Tucumán',
            style: const pw.TextStyle(fontSize: 9),
          ),
        ],
      ),
    ),
    pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Text(
          'Fecha: $fecha',
          style: const pw.TextStyle(fontSize: 9),
        ),
        if (comprobante.isNotEmpty)
          pw.Text(
            'Comp.: $comprobante',
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
      ],
    ),
  ],
),

pw.SizedBox(height: 10),
              pw.Row(
  crossAxisAlignment: pw.CrossAxisAlignment.start,
  children: [
    pw.Expanded(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
  'Cliente: $nombreCliente',
  style: pw.TextStyle(
    fontSize: 9,
    fontWeight: pw.FontWeight.bold,
  ),
),
          if (direccion.isNotEmpty)
            pw.Text(
              'Dirección: $direccion',
              style: const pw.TextStyle(fontSize: 9),
            ),
        ],
      ),
    ),
    pw.SizedBox(width: 12),
    pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        
        if (vendedor.isNotEmpty)
          pw.Text(
            'Vendedor: $vendedor',
            style: const pw.TextStyle(fontSize: 8),
          ),
      ],
    ),
  ],
),

pw.SizedBox(height: 12),

              // CABECERA DE PRODUCTOS
              pw.Row(
                children: [
                  pw.SizedBox(
                    width: 28,
                    child: pw.Text(
                      'Cant.',
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Text(
                      'Descripción',
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.SizedBox(
                    width: 60,
                    child: pw.Text(
                      'P. Unit.',
                      textAlign: pw.TextAlign.right,
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.SizedBox(
                    width: 65,
                    child: pw.Text(
                      'Importe',
                      textAlign: pw.TextAlign.right,
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),

              pw.Divider(thickness: 0.5),

              // PRODUCTOS
              ...detalles.map((detalle) {
                final producto =
                    detalle['productos'] as Map<String, dynamic>? ?? {};

                final nombre =
                    producto['nombre']?.toString() ?? 'Producto';

                final cantidadNumero = double.tryParse(
      detalle['cantidad_facturada']?.toString() ?? '',
    ) ??
    double.tryParse(
      detalle['cantidad']?.toString() ?? '0',
    ) ??
    0;
    if (cantidadNumero <= 0) {
  return pw.SizedBox();
}

final cantidad = cantidadNumero % 1 == 0
    ? cantidadNumero.toInt().toString()
    : cantidadNumero.toString();
                final precio = detalle['precio_unitario'] ?? 0;
                final precioNumero =
    double.tryParse(precio?.toString() ?? '') ?? 0;

final subtotal = cantidadNumero * precioNumero;

                return pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 2),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.SizedBox(
                        width: 28,
                        child: pw.Text(
                          '$cantidad',
                          style: const pw.TextStyle(fontSize: 9),
                        ),
                      ),
                      pw.Expanded(
                        child: pw.Text(
                          nombre,
                          style: const pw.TextStyle(fontSize: 9),
                        ),
                      ),
                      pw.SizedBox(
                        width: 60,
                        child: pw.Text(
                          _formatearPrecio(precio),
                          textAlign: pw.TextAlign.right,
                          style: const pw.TextStyle(fontSize: 9),
                        ),
                      ),
                      pw.SizedBox(
                        width: 65,
                        child: pw.Text(
                          _formatearPrecio(subtotal),
                          textAlign: pw.TextAlign.right,
                          style: const pw.TextStyle(fontSize: 9),
                        ),
                      ),
                    ],
                  ),
                );
              }),

              pw.SizedBox(height: 14),


              // TOTAL
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Text(
                    'TOTAL    ',
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    _formatearPrecio(
  detalles.fold<double>(0, (suma, detalle) {
    final cantidad = double.tryParse(
          detalle['cantidad_facturada']?.toString() ?? '',
        ) ??
        double.tryParse(
          detalle['cantidad']?.toString() ?? '0',
        ) ??
        0;

    final precio = double.tryParse(
          detalle['precio_unitario']?.toString() ?? '',
        ) ??
        0;

    return suma + (cantidad * precio);
  }),
),
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }
  static String _formatearFecha(dynamic valor) {
  if (valor == null) return '-';

  final fecha = DateTime.tryParse(valor.toString());
  if (fecha == null) return '-';

  final local = fecha.toLocal();

  final dia = local.day.toString().padLeft(2, '0');
  final mes = local.month.toString().padLeft(2, '0');
  final anio = local.year.toString();

  return '$dia/$mes/$anio';
}

  static String _formatearPrecio(dynamic valor) {
    final numero =
        double.tryParse(valor?.toString() ?? '') ?? 0;

    final entero = numero.round().toString();
    final buffer = StringBuffer();

    for (int i = 0; i < entero.length; i++) {
      final posicionDesdeDerecha = entero.length - i;

      buffer.write(entero[i]);

      if (posicionDesdeDerecha > 1 &&
          posicionDesdeDerecha % 3 == 1) {
        buffer.write('.');
      }
    }

    return '\$ ${buffer.toString()}';
  }
}