import 'package:flutter_test/flutter_test.dart';
import 'package:distribuidora_alberdi/core/text_search.dart';

void main() {
  test('sinAcentos: minúsculas, sin acentos ni espacios de más', () {
    expect(sinAcentos('  Azúcar   LEDESMA  '), 'azucar ledesma');
    expect(sinAcentos('Ñandú Pingüino'), 'nandu pinguino');
    expect(sinAcentos(null), '');
  });

  test('coincideBusqueda: sin acentos y palabras en cualquier orden', () {
    const producto = ['Tutuca F.N Super Dulce x 1kg', 'Marca: Flor Del Norte.'];
    expect(coincideBusqueda('', producto), isTrue);
    expect(coincideBusqueda('tutuca 1kg', producto), isTrue);
    expect(coincideBusqueda('1kg tutuca', producto), isTrue);
    expect(coincideBusqueda('flor dulce', producto), isTrue);
    expect(coincideBusqueda('fn', producto), isTrue);
    expect(coincideBusqueda('1 kg', producto), isTrue);
    expect(coincideBusqueda('tutuca stevia', producto), isFalse);
    expect(coincideBusqueda('azucar', ['Azúcar Ledesma x 1kg']), isTrue);
    expect(coincideBusqueda('AZÚCAR', ['azucar ledesma']), isTrue);
    expect(coincideBusqueda('yerba', [null, 'Yerba Playadito']), isTrue);
  });
}
