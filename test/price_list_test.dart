import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:distribuidora_alberdi/features/products/price_list_config.dart';
import 'package:distribuidora_alberdi/features/products/price_list_page.dart';
import 'package:distribuidora_alberdi/features/products/price_list_pdf_service.dart';

Map<String, dynamic> product(String name, String category) => {
  'nombre': name,
  'categoria': category,
  'activo': true,
  'visible_preventistas': true,
  'precio_normal': 12000,
  'precio_promo': 10500,
  'precio_interior': 13000,
};
void main() {
  test('Combinación por categoría y base sin modificar productos', () {
    final p = product('Bolsa', ' BALANCEADOS ');
    final copy = Map.of(p);
    final config = PriceListConfig(
      base: 'normal',
      excepciones: {'Balanceados': 'promo'},
    );
    expect(config.precioPara(p), 10500);
    expect(config.precioPara(product('Galletas', 'Almacen')), 12000);
    expect(p, copy);
    expect(
      PriceListConfig.fromJson(config.toJson()).tipoPara('balanceados'),
      'promo',
    );
    expect(
      () => config.precioPara({...p, 'precio_promo': null}),
      throwsFormatException,
    );
    expect(
      () => config.precioPara({...p, 'precio_promo': double.nan}),
      throwsFormatException,
    );
    expect(() => PriceListConfig(base: 'invalido'), throwsFormatException);
  });
  test('PDF combinado y tradicionales con varias páginas', () async {
    final products = [
      product('Balanceado Perro 20 kg', 'Balanceados'),
      {...product('Galletas 500 g', 'Almacen'), 'precio_normal': 1250.50},
      {...product('OCULTO', 'Balanceados'), 'visible_preventistas': false},
      {...product('INACTIVO', 'Balanceados'), 'activo': false},
      product('SIN CATEGORIA', ''),
      for (var i = 0; i < 100; i++)
        product(
          'Producto de ejemplo ${i.toString().padLeft(3, '0')} con descripcion y presentacion 500 g',
          'Almacen',
        ),
    ];
    final dir = Directory('.dart_tool/price_list_test')
      ..createSync(recursive: true);
    for (final tipo in ['personalizada', 'normal', 'promo', 'interior']) {
      final pdf = await PriceListPdfService.generarPdf(
        tipoPrecio: tipo == 'personalizada' ? 'normal' : tipo,
        productos: products,
        configuracion: tipo == 'personalizada'
            ? PriceListConfig(excepciones: {'Balanceados': 'promo'})
            : null,
      );
      File('${dir.path}/$tipo.pdf').writeAsBytesSync(pdf);
      expect(pdf.length, greaterThan(1000));
    }
  });
  testWidgets('Combinación se guarda y recarga para el mismo usuario', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(
        home: PriceListPage(
          productos: [product('Bolsa', 'Balanceados')],
          usuarioId: 'admin',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Personalizada'));
    await tester.pumpAndSettle();
    final dropdowns = find.byType(DropdownButtonFormField<String>);
    await tester.tap(dropdowns.last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Promo').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Guardar combinación'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar combinación'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).last,
      'Balanceados especial',
    );
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    final saved = jsonDecode(prefs.getString('listas_precios_v1_admin')!);
    expect(
      saved['Balanceados especial']['excepciones']['balanceados'],
      'promo',
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      MaterialApp(
        home: PriceListPage(
          productos: [product('Bolsa', 'Balanceados')],
          usuarioId: 'admin',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Personalizada'));
    await tester.pumpAndSettle();
    expect(find.text('Plantilla guardada en este dispositivo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Precio faltante bloquea generación', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(
        home: PriceListPage(
          productos: [
            {...product('Bolsa', 'Balanceados'), 'precio_normal': null},
          ],
          usuarioId: 'admin',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Corregí los precios'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Generar y revisar PDF'),
          )
          .onPressed,
      isNull,
    );
  });
}
