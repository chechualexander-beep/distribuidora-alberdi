import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:distribuidora_alberdi/features/invoicing/invoice_request.dart';
import 'package:distribuidora_alberdi/features/invoicing/invoice_snapshot_pdf.dart';

Map<String, dynamic> pdfFixture(List<Map<String, dynamic>> lines) {
  final total = lines.fold<num>(0, (s, l) => s + (l['subtotal'] as num));
  return {
    'estado': 'confirmada',
    'actor_id': 'fictional-admin',
    'resultado': {
      'version': 1,
      'comprobante_id': 'fictional-document',
      'solicitud_id': 'fictional-request',
      'pedido_id': 'fictional-order',
      'numero': '900001',
      'fecha_emision': '2026-10-29T03:10:00Z',
      'total': total,
      'captura_hash': List.filled(64, 'a').join(),
    },
    'captura': {
      'version': 1,
      'pedido_id': 'fictional-order',
      'numero': '900001',
      'fecha_emision': '2026-10-29T03:10:00Z',
      'naturaleza': 'boleta_interna_no_fiscal',
      'tipo': 'boleta_preventa',
      'moneda': 'ARS',
      'cliente': {
        'nombre': 'Cliente ficticio - Laboratorio 113C',
        'direccion': 'Dirección ficticia 123, Tucumán',
      },
      'actor': {'id': 'fictional-admin'},
      'preventista': {
        'id': 'fictional-seller',
        'nombre': 'Vendedor',
        'apellido': 'Ficticio',
      },
      'lineas': lines,
      'total': total,
      'observacion':
          'LABORATORIO LOCAL. Sin pedido, cobro ni número remoto. Observación capturada.',
    },
  };
}

Map<String, dynamic> line(String name, num quantity, num price) => {
  'nombre': name,
  'cantidad_documentada': quantity,
  'precio_unitario': price,
  'subtotal': (quantity * price * 100).round() / 100,
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final cases = <String, List<Map<String, dynamic>>>{
    'base-corregida': [
      line('Alimento ficticio QA - Gato pescado', 2, 100),
      line('Producto ficticio con acentos: ñ, á, é', 1, 100),
    ],
    'cifras-y-nombres-largos': [
      line(
        'Cantidad grande - Descripción ficticia extensa de alimento para gatos y perros, presentación económica con información íntegra y acentos á, é, í, ó, ú, ñ.',
        9999999999.99,
        0.01,
      ),
      line(
        'Precio elevado - Producto ficticio de laboratorio con nombre largo para verificar alineación y subtotal completo.',
        1,
        9876543210.12,
      ),
      line(
        'Fracciones - Producto ficticio con precio y cantidad decimales; sin modificar cálculos ni contenido.',
        12.34,
        567.89,
      ),
    ],
    'multiples-productos': [
      for (var i = 1; i <= 36; i++)
        line(
          'Artículo ficticio ${i.toString().padLeft(2, '0')} - Descripción extensa conservada, alimento para gatos y perros con acentos: nutrición, proteínas y tamaño familiar.',
          i + 0.25,
          i * 123.45,
        ),
    ],
  };
  for (final entry in cases.entries) {
    test(
      'A5 ${entry.key}: preserves immutable document and ordered lines',
      () async {
        final source = pdfFixture(entry.value);
        final document = InvoiceDocument.validate(
          source,
          order: 'fictional-order',
        );
        final before = jsonEncode(document.receipt);
        final bytes = await InvoiceSnapshotPdf.generate(document);
        expect(ascii.decode(bytes.take(4).toList()), '%PDF');
        expect(jsonEncode(document.receipt), before);
        expect(document.snapshot['lineas'], entry.value);
        final directory = Platform.environment['ALBERDI_113D_OUTPUT'];
        if (directory != null) {
          await Directory(directory).create(recursive: true);
          await File('$directory/${entry.key}.pdf').writeAsBytes(bytes);
          await File(
            '$directory/${entry.key}.expected.json',
          ).writeAsString(jsonEncode(document.snapshot));
        }
      },
    );
  }
}
