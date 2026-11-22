import 'package:distribuidora_alberdi/features/finance/finance_dashboard_page.dart';
import 'package:distribuidora_alberdi/features/finance/finance_data.dart';
import 'package:distribuidora_alberdi/features/finance/finance_home_page.dart';
import 'package:distribuidora_alberdi/features/stock/stock_data.dart';
import 'package:distribuidora_alberdi/features/stock/stock_form_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

FinState estado({bool started = true}) => FinState.fromJson({
  'inicio': started ? '2026-11-19T12:00:00Z' : null,
  'cuentas': [
    {'codigo': 'efectivo', 'nombre': 'Efectivo', 'saldo': 850000},
    {'codigo': 'billetera', 'nombre': 'Billetera virtual', 'saldo': 520000},
  ],
  'plata': 1370000,
  'gastos_fijos': [
    {
      'id': 'g1', 'nombre': 'Cuota del vehículo', 'importe': 280000, 'dia_pago': 1, 'ambito': 'negocio',
      'activo': true, 'vence': '2026-12-01', 'vencido': false, 'reservado': 160000, 'por_semana': 65000,
      'pagado_mes': true,
    },
    {
      'id': 'g2', 'nombre': 'Tarjeta', 'importe': 220000, 'dia_pago': 5, 'ambito': 'mixto',
      'activo': true, 'vence': '2026-12-05', 'vencido': false, 'reservado': 110000, 'por_semana': 51000,
      'pagado_mes': true,
    },
    {
      'id': 'g3', 'nombre': 'Viejo', 'importe': 1000, 'dia_pago': 9, 'ambito': 'hogar',
      'activo': false, 'vence': '2026-12-09', 'vencido': false, 'reservado': 0, 'por_semana': 230,
      'pagado_mes': false,
    },
  ],
  'sobre': 270000,
  'deudas': [
    {'id': 'd1', 'proveedor': 'Distribuidora Norte', 'importe': 300000, 'resta': 300000, 'vence': '2026-11-26', 'vencida': false},
  ],
  'deben': 300000,
  'disponible': 800000,
  'mes': {'cobros': 2500000, 'compras': 1200000, 'gastos_negocio': 90000, 'comisiones': 60000, 'hogar': 400000},
  'ultimos': [
    {'id': 'm1', 'fecha': '2026-11-19T15:00:00Z', 'tipo': 'gasto', 'cuenta': 'efectivo', 'importe': -3000,
      'parte_hogar': 0, 'categoria': 'Combustible', 'anulable': true},
    {'id': 'c1', 'fecha': '2026-11-19T14:00:00Z', 'tipo': 'cobro', 'cuenta': 'billetera', 'importe': 15000,
      'parte_hogar': 0, 'categoria': 'Cobro', 'descripcion': 'Kiosco Pepe', 'anulable': false},
  ],
});

void main() {
  test('importes: se escriben como en Argentina y se muestran con puntos', () {
    expect(parseMoney('15000'), 15000);
    expect(parseMoney('15.000'), 15000);
    expect(parseMoney('15.000,50'), 15000.5);
    expect(parseMoney('1500,5'), 1500.5);
    expect(parseMoney('\$2.300.000'), 2300000);
    expect(parseMoney(''), isNull);
    expect(parseMoney('abc'), isNull);
    expect(parseMoney('-5'), isNull);
    expect(pesos(15000), '\$15.000');
    expect(pesos(1500.5), '\$1.500,50');
    expect(pesos(-200), '-\$200');
    expect(pesos(0), '\$0');
  });

  test('estado: sobre, por semana y disponible', () {
    final s = estado();
    expect(s.started, isTrue);
    expect(s.saldo('billetera'), 520000);
    expect(s.activos.length, 2, reason: 'el apagado no cuenta');
    expect(s.gastosFijosMes, 500000);
    expect(s.apartarPorSemana, 116000);
    expect(s.deudas.single.proveedor, 'Distribuidora Norte');
    expect(s.mes['hogar'], 400000);
    expect(s.ultimos.first.titulo, 'Gasto · Combustible');
    expect(s.ultimos.last.titulo, 'Cobro · Kiosco Pepe');
  });

  testWidgets('Plata del negocio: anotar un gasto', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    String? rpc;
    Map<String, dynamic>? args;
    await tester.pumpWidget(
      MaterialApp(
        home: FinanceHomePage(
          initial: estado(),
          runner: (fn, a) async {
            rpc = fn;
            args = a;
            return const StockOpOutcome({'id': 'x'});
          },
        ),
      ),
    );
    expect(find.text('Disponible para mercadería'), findsOneWidget);
    expect(find.text('\$800.000'), findsOneWidget);
    expect(find.text('Apartá \$116.000 por semana'), findsOneWidget);
    await tester.tap(find.text('Anotar gasto'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await tester.pump();
    expect(find.text('Escribí el importe (mayor que 0).'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Importe'), '3.000');
    await tester.tap(find.text('Guardar'));
    await tester.pump();
    expect(find.text('Elegí en qué fue el gasto.'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Combustible'));
    await tester.pump();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(rpc, 'fin_movimiento');
    expect(args!['p_tipo'], 'gasto');
    expect(args!['p_importe'], 3000);
    expect(args!['p_cuenta'], 'efectivo');
    expect(args!['p_categoria'], 'Combustible');
  });

  testWidgets('Plata del negocio: sin foto inicial pide cuánta plata hay', (tester) async {
    String? rpc;
    Map<String, dynamic>? args;
    await tester.pumpWidget(
      MaterialApp(
        home: FinanceHomePage(
          initial: estado(started: false),
          runner: (fn, a) async {
            rpc = fn;
            args = a;
            return const StockOpOutcome({'id': 'x'});
          },
        ),
      ),
    );
    expect(find.text('Foto inicial'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Efectivo que hay hoy'), '850.000');
    await tester.enterText(find.widgetWithText(TextField, 'Lo que hay en la billetera virtual'), '0');
    await tester.tap(find.text('GUARDAR FOTO INICIAL'));
    await tester.pumpAndSettle();
    expect(rpc, 'fin_foto_inicial');
    expect(args, {'p_efectivo': 850000, 'p_billetera': 0});
  });

  testWidgets('Anotar compra: el pago queda en Plata del negocio', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final rpcs = <String>[];
    Map<String, dynamic>? pago;
    await tester.pumpWidget(
      MaterialApp(
        home: StockFormPage(
          kind: StockFormKind.purchase,
          items: [
            StockItem(id: 'a', name: 'Yerba', code: 'Y', category: 'x', photo: null, controlled: true,
                deposit: 5, vehicle: 0, cost: 1500),
          ],
          runner: (fn, a) async {
            rpcs.add(fn);
            if (fn == 'fin_movimiento') pago = a;
            return const StockOpOutcome({'total': 4500, 'nuevos_con_stock': 0});
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Depósito'));
    await tester.pump();
    await tester.tap(find.text('Billetera'));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'Cantidad'), '3');
    await tester.pump();
    await tester.tap(find.text('CONFIRMAR (1 producto)'));
    await tester.pumpAndSettle();
    expect(rpcs, ['stock_registrar_compra', 'fin_movimiento']);
    expect(pago!['p_tipo'], 'compra');
    expect(pago!['p_cuenta'], 'billetera');
    expect(pago!['p_importe'], 4500);
    expect(find.textContaining('Pago anotado: \$4.500 en billetera virtual'), findsOneWidget);
  });

  testWidgets('Anotar compra: con el teclado abierto se esconden las opciones', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: StockFormPage(
          kind: StockFormKind.purchase,
          items: [
            StockItem(id: 'a', name: 'Yerba', code: 'Y', category: 'x', photo: null, controlled: true,
                deposit: 5, vehicle: 0, cost: 1500),
          ],
          runner: (fn, a) async => const StockOpOutcome({}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Depósito'));
    await tester.pump();
    expect(find.text('¿Cómo pagaste?'), findsOneWidget);
    tester.view.viewInsets = FakeViewPadding(bottom: 600 * tester.view.devicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(find.text('¿Cómo pagaste?'), findsNothing);
    expect(find.text('Depósito · Efectivo · cerrá el teclado para ver las opciones'), findsOneWidget);
    expect(find.text('Yerba'), findsOneWidget);
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    expect(find.text('¿Cómo pagaste?'), findsOneWidget);
  });

  testWidgets('Anotar compra: el buscador no pierde el teclado al esconderse las opciones', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: StockFormPage(
          kind: StockFormKind.purchase,
          items: [
            StockItem(id: 'a', name: 'Yerba', code: 'Y', category: 'x', photo: null, controlled: true,
                deposit: 5, vehicle: 0, cost: 1500),
          ],
          runner: (fn, a) async => const StockOpOutcome({}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final buscador = find.byKey(const ValueKey('buscar-producto'));
    await tester.tap(buscador);
    await tester.pump();
    bool conFoco() => tester
        .widget<EditableText>(find.descendant(of: buscador, matching: find.byType(EditableText)))
        .focusNode
        .hasFocus;
    expect(conFoco(), isTrue);
    tester.view.viewInsets = FakeViewPadding(bottom: 600 * tester.view.devicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(find.text('¿Cómo pagaste?'), findsNothing);
    expect(conFoco(), isTrue, reason: 'el teclado no se cierra solo');
    await tester.enterText(buscador, 'yer');
    await tester.pump();
    expect(find.text('Yerba'), findsOneWidget);
  });

  testWidgets('Tablero: ganancia, lo de la casa, cuánto vender y capital', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final d = Dashboard.fromJson({
      'mes': '2026-11-01', 'actual': true, 'dia': 15, 'dias': 30,
      'ventas': 12000000, 'costo': 9000000, 'comisiones': 350000, 'notas_credito': 0,
      'ganancia_comercial': 2650000, 'margen': 0.22,
      'gastos_negocio': 900000, 'ganancia_negocio': 1750000, 'hogar': 2110000, 'quedo': -360000,
      'plata_desde': '2026-11-01T03:00:00Z', 'plata_parcial': false,
      'ventas_necesarias': 13636363.64, 'ventas_12_meses': 27849600,
      'capital': {'fecha': '2026-11-15', 'plata': 1200000, 'mercaderia': 6500000, 'clientes': 2300000,
        'a_favor': 0, 'proveedores': 1100000, 'total': 8900000, 'productos_con_stock': 80,
        'productos_sin_costo': 0, 'plata_iniciada': true},
      'capital_inicio': {'fecha': '2026-10-31', 'plata': 0, 'mercaderia': 0, 'clientes': 0, 'a_favor': 0,
        'proveedores': 0, 'total': 9260000},
      'capital_cierre': null,
    });
    expect(d.capitalCierre, isNull);
    expect(d.capital!.total, 8900000);
    await tester.pumpWidget(MaterialApp(home: FinanceDashboardPage(initial: d)));
    expect(find.text('Resultado · al día 15 de 30'), findsOneWidget);
    expect(find.text('-\$360.000'), findsOneWidget);
    expect(find.textContaining('Salió del capital'), findsOneWidget);
    expect(find.textContaining('hay que vender \$13.636.363,64'), findsOneWidget);
    expect(find.text('El negocio se achicó \$360.000.'), findsOneWidget);
    expect(find.text('\$27.849.600'), findsOneWidget);
  });
}
