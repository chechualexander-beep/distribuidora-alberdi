import 'package:distribuidora_alberdi/features/catalog/catalog_appearance_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('category order keeps saved ones first and adds new ones by name', () {
    expect(
      mergeCategoryOrder(
        ['snacks', 'ya no existe', 'Bebidas', 'snacks'],
        ['Almacén', 'Bebidas', ' Snacks ', 'Galletitas', ''],
      ),
      ['snacks', 'bebidas', 'almacén', 'galletitas'],
    );
  });

  test('palettes match the web site themes', () {
    expect(catalogThemes.keys, ['alberdi', 'rojo', 'azul', 'verde', 'naranja']);
  });
}
