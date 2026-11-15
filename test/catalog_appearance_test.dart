import 'package:distribuidora_alberdi/features/catalog/catalog_appearance_page.dart';
import 'package:flutter/material.dart';
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

  testWidgets('novelty dialog searches, returns the choice and closes cleanly', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    ({String id, int days})? result;
    var closed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDialog<({String id, int days})>(
                context: context,
                builder: (_) => const NoveltyDialog(
                  products: [
                    {'id': 'p1', 'nombre': 'Tutuca', 'categoria': 'Snacks'},
                    {'id': 'p2', 'nombre': 'Coca Cola', 'categoria': 'Bebidas'},
                  ],
                ),
              );
              closed = true;
            },
            child: const Text('abrir'),
          ),
        ),
      ),
    );
    for (final action in ['agregar', 'cancelar']) {
      closed = false;
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'coca');
      await tester.pump();
      expect(find.text('Tutuca'), findsNothing);
      await tester.tap(find.text('Coca Cola'));
      await tester.pump();
      await tester.tap(find.text(action == 'agregar' ? 'Agregar' : 'Cancelar'));
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      expect(tester.takeException(), isNull);
      if (action == 'agregar') {
        expect(result, (id: 'p2', days: 15));
      } else {
        expect(result, isNull);
      }
    }
  });
}
