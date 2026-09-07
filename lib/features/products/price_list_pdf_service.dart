import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class PriceListPdfService {
  static Future<Uint8List> generarPdf({
    required String tipoPrecio,
    required List<Map<String, dynamic>> productos,
  }) async {
    final pdf = pw.Document();

    final productosFiltrados = productos.where((producto) {
      final activo = producto['activo'] == true;
      final visible = producto['visible_preventistas'] == true;
      final categoria =
          producto['categoria']?.toString().trim() ?? '';

      return activo && visible && categoria.isNotEmpty;
    }).toList();

    productosFiltrados.sort((a, b) {
      final categoriaA =
          a['categoria']?.toString() ?? '';
      final categoriaB =
          b['categoria']?.toString() ?? '';

      final comparacionCategoria =
          categoriaA.compareTo(categoriaB);

      if (comparacionCategoria != 0) {
        return comparacionCategoria;
      }

      final nombreA =
          a['nombre']?.toString() ?? '';
      final nombreB =
          b['nombre']?.toString() ?? '';

      return nombreA.compareTo(nombreB);
    });

    final productosPorCategoria =
        <String, List<Map<String, dynamic>>>{};

    for (final producto in productosFiltrados) {
      final categoria =
          producto['categoria']?.toString() ?? 'Otros';

      productosPorCategoria.putIfAbsent(
        categoria,
        () => <Map<String, dynamic>>[],
      );

      productosPorCategoria[categoria]!.add(producto);
    }
    final colorCategoria = switch (tipoPrecio) {
  'promo' => PdfColors.red300,
  'interior' => PdfColors.green300,
  _ => PdfColors.lightBlue300,
};

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        
        footer: (context) {
          return pw.Row(
            mainAxisAlignment:
                pw.MainAxisAlignment.spaceBetween,
            children: [
              
              pw.Text(
                'Página ${context.pageNumber} de ${context.pagesCount}',
                style: const pw.TextStyle(
                  fontSize: 8,
                  color: PdfColors.grey700,
                ),
              ),
            ],
          );
        },
        build: (context) {
  final widgets = <pw.Widget>[
    pw.Text(
      'DISTRIBUIDORA ALBERDI',
      style: pw.TextStyle(
        fontSize: 20,
        fontWeight: pw.FontWeight.bold,
      ),
    ),
    pw.Text(
      'Lista de precios',
      style: pw.TextStyle(
        fontSize: 14,
        fontWeight: pw.FontWeight.bold,
      ),
    ),
    pw.SizedBox(height: 4),
    pw.Text(
      'Actualizada: ${_formatearFecha(DateTime.now())}',
      style: const pw.TextStyle(
        fontSize: 9,
        color: PdfColors.grey700,
      ),
    ),
    pw.SizedBox(height: 2),
pw.Text(
  'Precios sujetos a modificación.',
  style: const pw.TextStyle(
    fontSize: 8,
    color: PdfColors.grey700,
  ),
),
    pw.SizedBox(height: 5),
    pw.Container(
  width: 270,
  height: 1,
  color: PdfColors.black,
),
    pw.SizedBox(height: 4),
  ];

  for (final entrada in productosPorCategoria.entries) {
            widgets.add(
              pw.Container(
                width: 270,
                padding: const pw.EdgeInsets.symmetric(
                  vertical: 6,
                  horizontal: 8,
                ),
                margin: const pw.EdgeInsets.only(
                  top: 8,
                  bottom: 5,
                ),
                decoration: pw.BoxDecoration(
  color: colorCategoria,
),
                child: pw.Text(
                  entrada.key.toUpperCase(),
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            );

            for (final producto in entrada.value) {
              final nombre =
                  producto['nombre']?.toString() ??
                      'Producto';

              final precio =
                  _obtenerPrecio(
                    producto,
                    tipoPrecio,
                  );

              widgets.add(
  pw.Container(
    width: 250,
    padding: const pw.EdgeInsets.symmetric(
      vertical: 2,
      horizontal: 4,
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Text(
            nombre,
            style: const pw.TextStyle(
              fontSize: 9.5,
            ),
          ),
        ),
        pw.SizedBox(width: 8),
        pw.SizedBox(
          width: 58,
          child: pw.Text(
            _formatearPrecio(precio),
            textAlign: pw.TextAlign.right,
            style: pw.TextStyle(
              fontSize: 9.5,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
      ],
    ),
  ),
);
            }
          }

          return widgets;
        },
      ),
    );

    return pdf.save();
  }

  static double _obtenerPrecio(
    Map<String, dynamic> producto,
    String tipoPrecio,
  ) {
    String campo;

    switch (tipoPrecio) {
      case 'promo':
        campo = 'precio_promo';
        break;
      case 'interior':
        campo = 'precio_interior';
        break;
      case 'normal':
      default:
        campo = 'precio_normal';
    }

    return double.tryParse(
          producto[campo]?.toString() ?? '0',
        ) ??
        0;
  }

  static String _formatearFecha(DateTime fecha) {
    final dia =
        fecha.day.toString().padLeft(2, '0');
    final mes =
        fecha.month.toString().padLeft(2, '0');

    return '$dia/$mes/${fecha.year}';
  }

  static String _formatearPrecio(double valor) {
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
}