import 'package:distribuidora_alberdi/features/calculator/calculator_math.dart';
import 'package:distribuidora_alberdi/features/calculator/calculator_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

String texto(WidgetTester tester, String clave) =>
    tester.widget<TextField>(find.byKey(Key('calc-$clave'))).controller!.text;

void main() {
  test('margen: se mantiene el margen al cambiar el costo, o lo que tenga candado', () {
    const e = EstadoMargen(3800, 5700);
    expect(e.margen, closeTo(33.33, 0.01));
    expect(e.recargo, closeTo(50, 0.001));
    expect(e.ganancia, 1900);

    final costo = resolverMargen(e, CampoMargen.costo, 4000)!;
    expect(costo.venta, closeTo(6000, 0.01));

    final fijaVenta = resolverMargen(e, CampoMargen.costo, 4000, candado: CampoMargen.venta)!;
    expect(fijaVenta.venta, 5700);

    final margen = resolverMargen(e, CampoMargen.margen, 25)!;
    expect(margen.costo, 3800);
    expect(margen.venta, closeTo(5066.67, 0.01));

    final recargo = resolverMargen(e, CampoMargen.recargo, 40)!;
    expect(recargo.venta, closeTo(5320, 0.001));

    final ganancia = resolverMargen(e, CampoMargen.ganancia, 2000, candado: CampoMargen.margen)!;
    expect(ganancia.venta, closeTo(6000, 0.01));
    expect(ganancia.costo, closeTo(4000, 0.01));

    final venta = resolverMargen(e, CampoMargen.venta, 5000, candado: CampoMargen.margen)!;
    expect(venta.costo, closeTo(3333.33, 0.01));

    expect(resolverMargen(e, CampoMargen.margen, 100), isNull);
    expect(redondearArriba(5066.67, 50), 5100);
    expect(redondearArriba(5066.67, 0), 5066.67);
  });

  test('descuento y por bulto', () {
    const d = ResultadoDescuento(precio: 5700, descuento: 10, costo: 3800);
    expect(d.precioFinal, closeTo(5130, 0.001));
    expect(d.ahorro, closeTo(570, 0.001));
    expect(d.ganancia, closeTo(1330, 0.001));
    expect(ResultadoDescuento.descuentoPara(5700, 5130), closeTo(10, 0.001));

    const kilo = ResultadoBulto(
      precioBulto: 9800,
      kgBulto: 4,
      kgPedido: 1,
      recargo: 30,
      redondeo: 50,
      costoBulto: 7200,
    );
    expect(kilo.precioKilo, 2450);
    expect(kilo.precioVenta, 3200);
    expect(kilo.costoPedido, 1800);
    expect(kilo.ganancia, 1400);
    const cien = ResultadoBulto(
      precioBulto: 9800,
      kgBulto: 4,
      kgPedido: 0.1,
      recargo: 30,
      redondeo: 50,
    );
    expect(cien.precioVenta, 350);
    expect(cien.ganancia, isNull);
  });

  test('kilos leídos del nombre', () {
    expect(kilosDelTexto('Avena Fina x 4kg'), 4);
    expect(kilosDelTexto('Granola Miel x 2,5 kg'), 2.5);
    expect(kilosDelTexto('Maní pelado x 800g'), closeTo(0.8, 0.0001));
    expect(kilosDelTexto('Tutuca S. Cay. x 1kg'), 1);
    expect(kilosDelTexto('Yerba Playadito'), isNull);
    expect(kilosDelTexto('Gaseosa 2.25 L'), isNull);
    expect(textoPeso(0.8), '800 g');
    expect(textoPeso(0.1), '100 g');
    expect(textoPeso(2.5), '2,5 kg');
    expect(textoPeso(1), '1 kg');
    expect(textoPorcentaje(33.333), '33,3');
    expect(textoPorcentaje(25), '25');
  });

  testWidgets('pestaña Margen: casillas y candado', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: MarginCalculator(costo: 3800, venta: 5700)),
      ),
    );
    expect(texto(tester, 'margen'), '33,3');
    expect(texto(tester, 'recargo'), '50');
    expect(texto(tester, 'ganancia'), '1.900');

    await tester.enterText(find.byKey(const Key('calc-margen')), '25');
    await tester.pump();
    expect(texto(tester, 'venta'), '5.066,67');

    await tester.tap(find.byKey(const Key('candado-venta')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('calc-costo')), '4000');
    await tester.pump();
    expect(texto(tester, 'venta'), '5.066,67');
    expect(texto(tester, 'margen'), '21,1');
  });

  testWidgets('Por bulto: precio por kilo o 100 g y queda guardado lo de la última vez', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: BulkCalculator())));
    await tester.pumpAndSettle();
    expect(texto(tester, 'kg-bulto'), '4');
    expect(texto(tester, 'recargo-bulto'), '30');

    await tester.enterText(find.byKey(const Key('calc-precio-bulto')), '9800');
    await tester.pump();
    expect(find.text('\$3.200'), findsOneWidget);

    await tester.tap(find.text('100 g'));
    await tester.pumpAndSettle();
    expect(find.text('\$350'), findsOneWidget);
    await tester.tap(find.text('2,5 kg'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble('calc_bulto_pide'), 0.1);
    expect(prefs.getDouble('calc_bulto_trae'), 2.5);

    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: BulkCalculator())));
    await tester.pumpAndSettle();
    expect(texto(tester, 'kg-bulto'), '2,5');
  });

  testWidgets('pestañas: se cambia entre Margen, Descuento y Por bulto', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(420, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: CalculatorPage(cargar: false)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('calc-margen')), findsOneWidget);
    await tester.tap(find.text('Descuento'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('calc-descuento')), findsOneWidget);
    await tester.tap(find.text('Por bulto'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('calc-precio-bulto')), findsOneWidget);
  });
}
