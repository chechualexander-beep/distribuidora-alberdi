import 'package:distribuidora_alberdi/features/finance/business_health.dart';
import 'package:distribuidora_alberdi/features/finance/finance_dashboard_page.dart';
import 'package:distribuidora_alberdi/features/finance/finance_data.dart';
import 'package:distribuidora_alberdi/features/finance/finance_home_page.dart';
import 'package:distribuidora_alberdi/features/stock/stock_data.dart';
import 'package:distribuidora_alberdi/features/stock/stock_form_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

FinState estado({bool started = true, Map<String, dynamic>? sueldo}) => FinState.fromJson({
  'sueldo': sueldo,
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

  Future<(String?, Map<String, dynamic>?) Function()> abrirPlata(WidgetTester tester, FinState s) async {
    String? rpc;
    Map<String, dynamic>? args;
    await tester.pumpWidget(
      MaterialApp(
        home: FinanceHomePage(
          initial: s,
          runner: (fn, a) async {
            rpc = fn;
            args = a;
            return const StockOpOutcome({'id': 'x'});
          },
        ),
      ),
    );
    return () => (rpc, args);
  }

  testWidgets('Anotar gasto: si es de la casa va como retiro y no pide categoría', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final last = await abrirPlata(tester, estado());
    await tester.pump();
    await tester.tap(find.text('Anotar gasto'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('de-quien')), findsOneWidget);
    await tester.tap(find.text('Casa'));
    await tester.pump();
    expect(find.widgetWithText(ChoiceChip, 'Combustible'), findsNothing);
    expect(find.textContaining('no baja la ganancia'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Importe'), '12.000');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    final (rpc, args) = last();
    expect(rpc, 'fin_movimiento');
    expect(args!['p_tipo'], 'hogar');
    expect(args['p_categoria'], 'Casa');
    expect(args['p_importe'], 12000);
  });

  testWidgets('Ingreso o aporte: la plata de afuera queda como aporte del dueño', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final last = await abrirPlata(tester, estado());
    await tester.pump();
    await tester.tap(find.text('Ingreso o aporte'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aporte mío'));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'Importe'), '100.000');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    final (rpc, args) = last();
    expect(rpc, 'fin_movimiento');
    expect(args!['p_tipo'], 'ingreso');
    expect(args['p_categoria'], 'Aporte del dueño');
  });

  testWidgets('Mi sueldo: sin fijar ofrece fijarlo', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final last = await abrirPlata(tester, estado(sueldo: {'semanal': null}));
    await tester.pump();
    await tester.tap(find.text('Fijar sueldo'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Sueldo por semana'), '40.000');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    final (rpc, args) = last();
    expect(rpc, 'fin_sueldo_guardar');
    expect(args, {'p_importe': 40000});
  });

  testWidgets('Mi sueldo: el del sábado pendiente se paga desde la tarjeta', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final last = await abrirPlata(
      tester,
      estado(
        sueldo: {
          'semanal': 50000, 'desde': '2026-11-20', 'semana': '2026-11-28', 'pendiente': true, 'pagado': null,
          'ultimo': null, 'por_mes': 216667,
        },
      ),
    );
    await tester.pump();
    expect(find.text('\$50.000 por semana'), findsOneWidget);
    expect(find.text('Pendiente: el del sábado 28/11'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Pagar'));
    await tester.pumpAndSettle();
    expect(find.text('Semana del sábado 28/11.'), findsOneWidget);
    await tester.tap(find.text('Pagado'));
    await tester.pumpAndSettle();
    final (rpc, args) = last();
    expect(rpc, 'fin_pagar_sueldo');
    expect(args, {'p_semana': '2026-11-28', 'p_cuenta': 'efectivo', 'p_importe': 50000});
  });

  testWidgets('Un gasto mal anotado se pasa a Personal sin anularlo', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final last = await abrirPlata(tester, estado());
    await tester.pump();
    await tester.ensureVisible(find.text('Gasto · Combustible'));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Gasto · Combustible'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cambiar de quién es'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Personal'));
    await tester.pump();
    await tester.tap(find.text('Cambiar'));
    await tester.pumpAndSettle();
    final (rpc, args) = last();
    expect(rpc, 'fin_reclasificar');
    expect(args, {'p_id': 'm1', 'p_de_quien': 'personal', 'p_categoria': null});
  });

  test('movimientos: sueldo, personal y aporte se nombran por lo que son', () {
    FinMovement mov(String tipo, String cat, [String? d]) => FinMovement.fromJson({
      'id': 'x', 'fecha': '2026-11-28T15:00:00Z', 'tipo': tipo, 'cuenta': 'efectivo', 'importe': -1,
      'parte_hogar': 1, 'categoria': cat, 'descripcion': d, 'anulable': true,
    });
    expect(mov('hogar', 'Sueldo', 'Semana del sábado 28/11').titulo, 'Mi sueldo · Semana del sábado 28/11');
    expect(mov('hogar', 'Sueldo').reclasificable, isFalse);
    expect(mov('hogar', 'Personal').titulo, 'Personal');
    expect(mov('hogar', 'Personal').deQuien, 'personal');
    expect(mov('hogar', 'Hogar').deQuien, 'casa');
    expect(mov('ingreso', 'Aporte del dueño').titulo, 'Aporte del dueño');
    expect(mov('gasto', 'Combustible').reclasificable, isTrue);
  });

  Map<String, dynamic> mes(String m, {bool actual = false, bool? completo, double? gan, double retiros = 0,
      int dias = 30, double ventas = 10000000, double margen = 0.2, double? capIni, double? capFin}) => {
    'mes': m, 'actual': actual, 'ventas': ventas, 'ganancia_comercial': ventas * margen, 'margen': margen,
    'completo': completo ?? gan != null,
    'medido': gan == null ? null : {
      'desde': '${m}T03:00:00Z', 'hasta': '${m}T03:00:00Z', 'dias': dias, 'ventas': ventas,
      'ganancia_comercial': ventas * margen, 'ganancia_negocio': gan, 'gastos_negocio': ventas * margen - gan,
      'retiros': retiros, 'sueldo': retiros, 'casa': 0, 'personal': 0, 'aportes': 0,
    },
    'capital_inicio': capIni, 'capital_inicio_fecha': capIni == null ? null : m, 'capital_fin': capFin,
  };

  test('salud: con pocos días de gastos no sugiere sueldo y avisa', () {
    final h = BusinessHealth.fromJson({
      'inicio': '2026-11-18T13:00:00Z', 'sueldo_semanal': null,
      'meses': [
        mes('2026-09-01'), mes('2026-10-01'),
        mes('2026-11-01', actual: true, completo: false, gan: 300000, dias: 6, retiros: 100000),
      ],
    });
    expect(h.cerrados, isEmpty);
    expect(h.sueldoSugerido, isNull);
    expect(h.dias, 6);
    expect(h.primerMesCompleto, DateTime(2026, 12));
    final s = h.senales;
    expect(s.length, 5);
    expect(s[0].estado, Semaforo.verde);
    expect(s[1].estado, Semaforo.verde, reason: 'el margen se compara con los meses de antes, que sí tienen ventas');
    expect(s[3].estado, Semaforo.verde, reason: 'retiró un tercio de la ganancia');
    expect(s[4].estado, Semaforo.gris, reason: 'no hay foto del capital de antes');
  });

  test('salud: con 3 meses completos el sueldo sugerido deja 25% de reserva', () {
    final h = BusinessHealth.fromJson({
      'inicio': '2026-08-01T03:00:00Z', 'sueldo_semanal': 200000,
      'meses': [
        mes('2026-08-01', gan: 1000000, retiros: 1200000, capIni: 9000000),
        mes('2026-09-01', gan: 1000000, retiros: 1200000),
        mes('2026-10-01', gan: 1000000, retiros: 1200000),
        mes('2026-11-01', actual: true, completo: true, gan: 500000, dias: 23, margen: 0.15, capFin: 8500000),
      ],
    });
    expect(h.firme, isTrue);
    expect(h.dias, 90);
    // 3.000.000 en 90 días → 1.013.333 por mes; × 0,75 ÷ 4,33 = 175.384 → 175.000.
    expect(h.sueldoSugerido, 175000);
    final s = h.senales;
    expect(s[1].estado, Semaforo.rojo, reason: 'el margen bajó 5 puntos');
    expect(s[3].estado, Semaforo.rojo, reason: 'se llevó más de lo que ganó');
    expect(s[4].estado, Semaforo.rojo, reason: 'el capital bajó 5,5%');
  });

  testWidgets('Tablero: la salud del negocio arriba', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime.now();
    final m = '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
    final d = Dashboard.fromJson({
      'mes': m, 'actual': true, 'dia': 5, 'dias': 30, 'ventas': 1000000, 'costo': 800000, 'comisiones': 0,
      'notas_credito': 0, 'ganancia_comercial': 200000, 'margen': 0.2, 'gastos_negocio': 50000,
      'ganancia_negocio': 150000, 'hogar': 80000, 'quedo': 70000, 'sueldo': 50000, 'casa': 20000,
      'personal': 10000, 'aportes': 30000, 'gastos_por_categoria': {'Combustible': 40000, 'Otros': 10000},
      'plata_parcial': false, 'ventas_12_meses': 1000000,
    });
    final h = BusinessHealth.fromJson({
      'inicio': '${m}T03:00:00Z', 'sueldo_semanal': 50000,
      'meses': [mes(m, actual: true, completo: true, gan: 150000, dias: 5, retiros: 80000)],
    });
    await tester.pumpWidget(MaterialApp(home: FinanceDashboardPage(initial: d, initialHealth: h)));
    expect(find.byKey(const Key('salud-del-negocio')), findsOneWidget);
    expect(find.text('Salud del negocio'), findsOneWidget);
    expect(find.textContaining('El sueldo sugerido se calcula cuando cierre'), findsOneWidget);
    expect(find.text('      Mi sueldo'), findsOneWidget);
    expect(find.text('Gastos del negocio por categoría'), findsOneWidget);
    expect(find.textContaining('pusiste \$30.000 de tu bolsillo'), findsOneWidget);
  });

  FinState conSobres() => FinState.fromJson({
    ...{
      'inicio': '2026-11-19T12:00:00Z',
      'cuentas': [
        {'codigo': 'efectivo', 'nombre': 'Efectivo', 'saldo': 600000},
        {'codigo': 'billetera', 'nombre': 'Billetera virtual', 'saldo': 220000},
        {'codigo': 'sobre_efectivo', 'nombre': 'Frasco (efectivo)', 'saldo': 180000},
        {'codigo': 'sobre_billetera', 'nombre': 'Reserva (billetera)', 'saldo': 140000},
      ],
      'plata': 1140000, 'libre': 820000, 'sobre': 342000, 'faltan_sobres': 32000, 'deben': 0, 'disponible': 788000,
      'sobres': [
        {'codigo': 'sobre_efectivo', 'medio': 'efectivo', 'nombre': 'Frasco (efectivo)', 'saldo': 180000,
          'deberia': 170000, 'faltan': 0, 'poner_sabado': 45000, 'sabado': '2026-11-28'},
        {'codigo': 'sobre_billetera', 'medio': 'billetera', 'nombre': 'Reserva (billetera)', 'saldo': 140000,
          'deberia': 172000, 'faltan': 32000, 'poner_sabado': 62000, 'sabado': '2026-11-28'},
      ],
      'gastos_fijos': [
        {'id': 'v', 'nombre': 'Cuota del vehículo', 'importe': 535000, 'dia_pago': 10, 'ambito': 'negocio',
          'medio': 'billetera', 'activo': true, 'vence': '2026-12-10', 'vencido': false, 'reservado': 172000,
          'por_semana': 123000, 'pagado_mes': true, 'periodo_mes': '2026-11-10'},
        {'id': 'luz', 'nombre': 'Luz', 'importe': 165000, 'dia_pago': 2, 'ambito': 'hogar', 'medio': 'billetera',
          'activo': true, 'vence': '2026-12-02', 'vencido': false, 'reservado': 115000, 'por_semana': 38000,
          'pagado_mes': false, 'periodo_mes': '2026-11-02'},
      ],
      'deudas': [], 'mes': {}, 'ultimos': [],
      'sueldo': {'semanal': 230000, 'desde': '2026-11-24', 'semana': '2026-11-28', 'pendiente': true, 'pagado': null,
        'por_mes': 996667},
    },
  });

  Future<List<(String, Map<String, dynamic>)>> abrirConSobres(WidgetTester tester) async {
    final calls = <(String, Map<String, dynamic>)>[];
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: FinanceHomePage(
          initial: conSobres(),
          runner: (fn, a) async {
            calls.add((fn, a));
            return const StockOpOutcome({'id': 'x'});
          },
        ),
      ),
    );
    return calls;
  }

  testWidgets('Sobres: plata libre aparte y lo que falta se descuenta del disponible', (tester) async {
    await abrirConSobres(tester);
    expect(find.text('Plata libre'), findsOneWidget);
    expect(find.text('Frasco (efectivo)'), findsOneWidget);
    expect(find.text('- Lo que falta en los sobres'.replaceFirst('-', '−')), findsOneWidget);
    expect(find.text('\$788.000'), findsOneWidget);
    expect(find.textContaining('faltan \$32.000'), findsOneWidget);
    expect(find.textContaining('al día'), findsOneWidget);
    expect(find.byKey(const Key('gastos-casa')), findsOneWidget);
    expect(find.text('Cuota del vehículo · \$535.000'), findsOneWidget);
  });

  testWidgets('Sobres: el sábado se llenan los dos y se paga el sueldo de una vez', (tester) async {
    final calls = await abrirConSobres(tester);
    await tester.tap(find.byKey(const Key('llenar-sobres')));
    await tester.pumpAndSettle();
    expect(find.text('Llenar sobres y sueldo'), findsOneWidget);
    await tester.tap(find.text('Listo, lo separé'));
    await tester.pumpAndSettle();
    expect(calls.length, 3);
    expect(calls[0].$1, 'fin_movimiento');
    expect(calls[0].$2['p_cuenta'], 'efectivo');
    expect(calls[0].$2['p_cuenta_destino'], 'sobre_efectivo');
    expect(calls[0].$2['p_importe'], 45000);
    expect(calls[1].$2['p_cuenta'], 'billetera');
    expect(calls[1].$2['p_cuenta_destino'], 'sobre_billetera');
    expect(calls[1].$2['p_importe'], 62000);
    expect(calls[2].$1, 'fin_pagar_sueldo');
    expect(calls[2].$2['p_importe'], 230000);
  });

  testWidgets('Sobres: poner plata muestra lo que había más lo agregado', (tester) async {
    final calls = await abrirConSobres(tester);
    await tester.tap(find.byTooltip('Poner o sacar plata').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Cuánto ponés'), '20.000');
    await tester.pump();
    expect(find.text('Había \$180.000 + \$20.000 = \$200.000'), findsOneWidget);
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(calls.single.$2['p_cuenta_destino'], 'sobre_efectivo');
    expect(calls.single.$2['p_importe'], 20000);
  });

  testWidgets('Gastos de la casa: se marcan pagados con el sueldo, sin mover plata', (tester) async {
    final calls = await abrirConSobres(tester);
    await tester.tap(find.text('Ya lo pagué'));
    await tester.pumpAndSettle();
    expect(calls.single.$1, 'fin_gasto_casa_pagado');
    expect(calls.single.$2, {'p_gasto_fijo_id': 'luz', 'p_periodo': '2026-12-02', 'p_pagado': true});
  });
}
