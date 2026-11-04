import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'invoice_request.dart';

/// Pure rendering: no Supabase, preferences, product catalogue or emission RPC.
class InvoiceSnapshotPdf {
  static Future<Uint8List> generate(InvoiceDocument document) async {
    final c = document.snapshot;
    final date = DateTime.parse(
      c['fecha_emision'] as String,
    ).toUtc().subtract(const Duration(hours: 3));
    final day =
        '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    final regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/roboto-regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/roboto-bold.ttf'),
    );
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );
    String money(dynamic v) => (v as num).toStringAsFixed(2);
    // Reserve only the width required by the printed quantities, not a wide
    // fixed gutter for single-digit orders. Large figures retain their space.
    var quantityWidth = 28.0;
    for (final line in c['lineas'] as List) {
      final width = (line['cantidad_documentada'].toString().length * 5.2 + 8)
          .clamp(28, 70)
          .toDouble();
      if (width > quantityWidth) quantityWidth = width;
    }
    final seller = c['preventista'] is Map ? c['preventista'] as Map : const {};
    final sellerName = [
      seller['nombre'],
      seller['apellido'],
    ].where((v) => v != null && v.toString().trim().isNotEmpty).join(' ');
    pw.Widget numberCell(
      String text, {
      bool header = false,
      bool left = false,
    }) => pw.Container(
      padding: pw.EdgeInsets.fromLTRB(left ? 0 : 4, 3, 4, header ? 6 : 3),
      alignment: left ? pw.Alignment.topLeft : pw.Alignment.topRight,
      child: pw.FittedBox(
        fit: pw.BoxFit.scaleDown,
        alignment: left ? pw.Alignment.centerLeft : pw.Alignment.centerRight,
        child: pw.Text(
          text,
          softWrap: false,
          maxLines: 1,
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      ),
    );
    pw.Widget productCell(String text, {bool header = false}) => pw.Padding(
      padding: pw.EdgeInsets.fromLTRB(4, 3, 4, header ? 6 : 3),
      child: pw.Text(
        text,
        softWrap: true,
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.fromLTRB(18, 18, 18, 16),
        theme: pw.ThemeData.withFont(
          base: regular,
          bold: bold,
        ).copyWith(defaultTextStyle: const pw.TextStyle(fontSize: 10)),
        build: (_) => [
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
                    pw.Text(
                      'Circunvalación km 1280, Tucumán',
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                    pw.Text(
                      'BOLETA INTERNA - NO FISCAL',
                      style: const pw.TextStyle(fontSize: 7),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(
                width: 125,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'Fecha: $day',
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                    pw.Text(
                      'Comp.: ${c['numero']}',
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
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
                      'Cliente: ${c['cliente']['nombre']}',
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'Dirección: ${c['cliente']['direccion'] ?? ''}',
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(width: 8),
              pw.SizedBox(
                width: 125,
                child: pw.Text(
                  'Vendedor: ${sellerName.isEmpty ? '-' : sellerName}',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Table(
            defaultVerticalAlignment: pw.TableCellVerticalAlignment.top,
            columnWidths: {
              0: pw.FixedColumnWidth(quantityWidth),
              1: const pw.FlexColumnWidth(),
              2: const pw.FixedColumnWidth(70),
              3: const pw.FixedColumnWidth(78),
            },
            children: [
              pw.TableRow(
                repeat: true,
                children: [
                  numberCell('Cant.', header: true, left: true),
                  productCell('Descripción', header: true),
                  numberCell('P. Unit.', header: true),
                  numberCell('Importe', header: true),
                ],
              ),
              for (final line in c['lineas'] as List)
                pw.TableRow(
                  children: [
                    numberCell(
                      line['cantidad_documentada'].toString(),
                      left: true,
                    ),
                    productCell(line['nombre'] as String),
                    numberCell('\$ ${money(line['precio_unitario'])}'),
                    numberCell('\$ ${money(line['subtotal'])}'),
                  ],
                ),
            ],
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(4, 5, 4, 0),
            child: pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                'TOTAL \$ ${money(c['total'])}',
                softWrap: false,
                maxLines: 1,
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
    return pdf.save();
  }
}
