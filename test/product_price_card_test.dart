import 'dart:async';
import 'dart:ui' as ui;

import 'package:distribuidora_alberdi/features/products/product_price_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  const tutuca = PriceCardData(
    nombre: 'Tutuca F.N Super Dulce x 1kg',
    detalle: 'Marca: Flor Del Norte.',
    precio: 5700,
    lista: 'promo',
  );

  test('datos de la imagen: detalle, fecha y nombre de archivo', () {
    expect(tutuca.detalleLimpio, 'Marca: Flor Del Norte');
    expect(
      tutuca.textoFecha(DateTime(2026, 11, 20)),
      'Precio al 20/11/2026 · sujeto a cambios',
    );
    expect(tutuca.nombreArchivo, 'Alberdi - Tutuca F.N Super Dulce x 1kg.jpg');
    expect(
      const PriceCardData(nombre: 'Gaseosa 1/2 "litro"', precio: 1).nombreArchivo,
      'Alberdi - Gaseosa 1 2 litro.jpg',
    );
  });

  test('la foto cubre la imagen solo si se recorta poco', () {
    expect(fotoCubreTarjeta(960, 960), isTrue);
    expect(fotoCubreTarjeta(768, 960), isTrue);
    expect(fotoCubreTarjeta(600, 960), isTrue);
    expect(fotoCubreTarjeta(960, 640), isFalse);
    expect(fotoCubreTarjeta(400, 960), isFalse);
    expect(fotoCubreTarjeta(0, 960), isFalse);
  });

  testWidgets('arma un JPG de 1080 x 1350 con foto y sin foto', (tester) async {
    await tester.runAsync(() async {
      final logo = await decodeCardImage(
        img.encodePng(img.Image(width: 64, height: 32, numChannels: 4)),
      );
      final fotoAncha = await decodeCardImage(
        img.encodeJpg(img.Image(width: 960, height: 640)),
      );
      for (final foto in [fotoAncha, null]) {
        final jpg = await renderPriceCard(
          data: tutuca,
          logo: logo,
          foto: foto,
          hoy: DateTime(2026, 11, 20),
        );
        final decodificada = img.decodeJpg(jpg)!;
        expect(decodificada.width, priceCardWidth);
        expect(decodificada.height, priceCardHeight);
      }
    });
  });

  testWidgets('pantalla: muestra la lista solo al preventista y los dos botones', (
    tester,
  ) async {
    final logo = Completer<ui.Image>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProductPriceCardViewer(
            data: tutuca,
            cargarFoto: () async => null,
            cargarLogo: () => logo.future,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Armando la imagen...'), findsOneWidget);
    expect(find.textContaining('Lista Promo'), findsOneWidget);
    expect(find.text('COMPARTIR'), findsOneWidget);
    expect(find.textContaining('GUARDAR'), findsOneWidget);
    final compartir = tester.widget<FilledButton>(
      find.byKey(const Key('tarjeta-compartir')),
    );
    expect(compartir.onPressed, isNull);
  });
}
