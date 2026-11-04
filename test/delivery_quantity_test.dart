import 'package:distribuidora_alberdi/features/orders/delivery_quantity.dart';
import 'package:distribuidora_alberdi/features/orders/finalization_request.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'unchanged, decreased and rejected quantities keep the original line',
    () {
      for (final sample in [('1', 100), ('0,75', 75), ('0', 0)]) {
        expect(splitDeliveryQuantity(sample.$1, 100, allowsAdditional: true), (
          original: sample.$2,
          additional: 0,
        ));
      }
    },
  );

  test('direct sale increases and recomputes excess on subsequent edits', () {
    for (final sample in [
      ('2', 100, 100),
      ('1.25', 100, 25),
      ('1', 100, 0),
      ('0', 0, 0),
    ]) {
      expect(splitDeliveryQuantity(sample.$1, 100, allowsAdditional: true), (
        original: sample.$2,
        additional: sample.$3,
      ));
    }
  });

  test('preorders retain their original cap and reject invalid quantities', () {
    expect(splitDeliveryQuantity('2', 100, allowsAdditional: false), isNull);
    expect(splitDeliveryQuantity('0,50', 100, allowsAdditional: false), (
      original: 50,
      additional: 0,
    ));
    for (final input in ['', '-1', '1.001', 'NaN', '1e2']) {
      expect(deliveryHundredths(input), isNull);
    }
  });

  test(
    'contextual payload keeps original and both added products distinct',
    () {
      final result = contextualDeliveryLines([
        {
          'id': 'original',
          'producto_id': 'qa',
          'cantidad_entregada': 1,
          'precio_unitario': 100,
        },
        {
          'producto_id': 'qa',
          'cantidad_entregada': 0.25,
          'tipo_precio': 'normal',
          'precio_unitario': 120,
          'agregado_en_entrega': true,
        },
        {
          'producto_id': 'otro',
          'cantidad_entregada': 1,
          'tipo_precio': 'promo',
          'precio_unitario': 80,
          'agregado_en_entrega': true,
        },
      ]);
      expect(result, {
        'p_originales': [
          {'detalle_id': 'original', 'cantidad_entregada': 1},
        ],
        'p_agregados': [
          {
            'producto_id': 'qa',
            'cantidad_entregada': 0.25,
            'tipo_precio': 'normal',
          },
          {
            'producto_id': 'otro',
            'cantidad_entregada': 1,
            'tipo_precio': 'promo',
          },
        ],
      });
    },
  );
}
