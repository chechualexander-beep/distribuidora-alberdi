import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:distribuidora_alberdi/features/products/product_photo.dart';

void main() {
  test(
    'Reduce dimensiones, conserva proporción y convierte transparencia a blanco',
    () {
      final input = img.Image(width: 1600, height: 800, numChannels: 4);
      final result = prepareProductPhoto(img.encodePng(input));
      final decoded = img.decodeJpg(result)!;
      expect(decoded.width, 960);
      expect(decoded.height, 480);
      expect(decoded.getPixel(0, 0).r, greaterThan(245));
      expect(result.length, lessThanOrEqualTo(300 * 1024));
    },
  );
  test('Rechaza archivos inválidos y demasiado pesados', () {
    expect(
      () => prepareProductPhoto(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
    expect(
      () => prepareProductPhoto(Uint8List(20 * 1024 * 1024 + 1)),
      throwsFormatException,
    );
  });
}
