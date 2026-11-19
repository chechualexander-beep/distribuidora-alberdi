import 'dart:convert';

import 'package:distribuidora_alberdi/core/app_config.dart';
import 'package:distribuidora_alberdi/core/pending_orders.dart';
import 'package:distribuidora_alberdi/features/desktop/desktop_home.dart';
import 'package:distribuidora_alberdi/features/stock/product_summary.dart';
import 'package:distribuidora_alberdi/features/stock/stock_data.dart';
import 'package:distribuidora_alberdi/features/stock/stock_form_page.dart';
import 'package:distribuidora_alberdi/features/stock/stock_home_page.dart';
import 'package:distribuidora_alberdi/features/stock/vehicle_load_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/outbox_fixture.dart';

StockItem item(String id, {bool controlled = true, double deposit = 10, double vehicle = 4}) => StockItem(
  id: id,
  name: 'Producto $id',
  code: id.toUpperCase(),
  category: 'Almacén',
  photo: null,
  controlled: controlled,
  deposit: deposit,
  vehicle: vehicle,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    activateAppConfig(fixtureConfig());
    SharedPreferences.setMockInitialValues({});
  });

  test('cantidades: se escriben con coma o punto y se muestran sin ceros de más', () {
    expect(parseQty('12'), 12);
    expect(parseQty('2,5'), 2.5);
    expect(parseQty(' 0 '), 0);
    expect(parseQty(''), isNull);
    expect(parseQty('-1'), isNull);
    expect(parseQty('abc'), isNull);
    expect(formatQty(12), '12');
    expect(formatQty(2.5), '2,5');
    expect(formatQty(-2), '-2');
  });

  test('resumen: alcanza, falta, fraccionar, a pedido y lista de compras', () {
    StockItem p(String id, String name, double dep, {bool controlled = true, String? parent, double? units}) =>
        StockItem(
          id: id,
          name: name,
          code: '',
          category: 'x',
          photo: null,
          controlled: controlled,
          deposit: dep,
          vehicle: 0,
          parentId: parent,
          unitsPerParent: units,
        );
    final stock = {
      for (final i in [
        p('y', 'Yerba', 30),
        p('p', 'Copos 3A x 4 kg', 2),
        p('c', 'Copos x 1 kg', 3, parent: 'p', units: 4),
        p('f', 'Papas x 1 kg', 4),
        p('a', 'Aceite de coco', 0, controlled: false),
        p('q', 'Aritos x 2,5 kg', 0),
        p('k', 'Aritos x 1 kg', 0, parent: 'q', units: 2.5),
      ])
        i.id: i,
    };
    final rows = evaluateSummary(const [
      SummaryLine('y', 'Yerba', 12),
      SummaryLine('c', 'Copos x 1 kg', 6),
      SummaryLine('f', 'Papas x 1 kg', 7),
      SummaryLine('a', 'Aceite de coco', 2),
      SummaryLine('k', 'Aritos x 1 kg', 6),
      SummaryLine(null, 'Sin id', 1),
    ], stock);
    expect(rows.map((r) => r.state), [
      SummaryState.enough,
      SummaryState.open,
      SummaryState.missing,
      SummaryState.onDemand,
      SummaryState.missing,
      SummaryState.unknown,
    ]);
    expect(rows[1].openParents, 1);
    expect(rows[2].missing, 3);
    expect(rows[4].buyName, 'Aritos x 2,5 kg');
    expect(rows[4].buyQuantity, 3);
    final list = shoppingList(rows);
    expect(list, contains('3 × Papas x 1 kg'));
    expect(list, contains('2 × Aceite de coco'));
    expect(list, contains('3 × Aritos x 2,5 kg'));
    expect(list, contains('Abrir 1 × Copos 3A x 4 kg'));
    expect(evaluateSummary(const [SummaryLine('y', 'Yerba', 1)], null).single.state, SummaryState.unknown);
  });

  test('resumen: las bolsas pedidas enteras no se cuentan para fraccionar', () {
    final stock = {
      'b': StockItem(id: 'b', name: 'Facu x 5 kg', code: '', category: 'x', photo: null,
          controlled: true, deposit: 2, vehicle: 0),
      's': StockItem(id: 's', name: 'Facu x 1 kg', code: '', category: 'x', photo: null,
          controlled: false, deposit: 0, vehicle: 0, parentId: 'b', unitsPerParent: 5),
    };
    final rows = evaluateSummary(const [
      SummaryLine('b', 'Facu x 5 kg', 1),
      SummaryLine('s', 'Facu x 1 kg', 6),
    ], stock);
    expect(rows[0].state, SummaryState.enough);
    expect(rows[1].state, SummaryState.missing);
    expect(rows[1].openParents, 1);
    expect(rows[1].missing, 1);
    final list = shoppingList(rows);
    expect(list, contains('1 × Facu x 5 kg'));
    expect(list, contains('Abrir 1 × Facu x 5 kg'));
  });

  test('sueltos debajo de su cerrado y total combinado', () {
    final caja = StockItem(id: 'caja', name: 'Papas Facu caja x 5 kg', code: '', category: 'x', photo: null,
        controlled: true, deposit: 10, vehicle: 0);
    final suelta = StockItem(id: 'kg', name: 'Papas Facu x 1 kg', code: '', category: 'x', photo: null,
        controlled: false, deposit: 0, vehicle: 2, parentId: 'caja', unitsPerParent: 5);
    final otro = StockItem(id: 'y', name: 'Yerba', code: '', category: 'x', photo: null,
        controlled: true, deposit: 3, vehicle: 0);
    final todos = [suelta, caja, otro];
    expect(pairLooseWithClosed([caja, otro], todos, addLoose: true).map((i) => i.id), ['caja', 'kg', 'y']);
    expect(pairLooseWithClosed([caja, otro], todos).map((i) => i.id), ['caja', 'y']);
    expect(pairLooseWithClosed([suelta, caja, otro], todos).map((i) => i.id), ['caja', 'kg', 'y']);
    expect(looseSummary(caja, suelta), '10 cerrados + 2 sueltos = 52 × Papas Facu x 1 kg');
    final rows = evaluateSummary(const [SummaryLine('kg', 'Papas Facu x 1 kg', 3)], {
      for (final i in todos) i.id: i,
    });
    expect(rows.single.closedName, 'Papas Facu caja x 5 kg');
    expect(rows.single.closedStock, 10);
  });

  testWidgets('resumen sin stock (preventista): filas con cantidades, sin columna Hay', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProductSummaryTable(
              stock: const {},
              lines: const [SummaryLine('y', 'Yerba', 12), SummaryLine('z', 'Azúcar', 3)],
            ),
          ),
        ),
      ),
    );
    expect(find.text('Yerba'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('Lista de compras'), findsOneWidget, reason: 'con stock cargado (vacío) se ofrece');
  });

  test('pedidos nuevos: se compara con lo libre (sin lo facturado para el reparto)', () {
    final caja = StockItem(id: 'caja', name: 'Caja x 5', code: '', category: 'x', photo: null,
        controlled: true, deposit: 2, vehicle: 0);
    final suelto = StockItem(id: 's', name: 'Suelto', code: '', category: 'x', photo: null,
        controlled: true, deposit: 1, vehicle: 0, parentId: 'caja', unitsPerParent: 5);
    final libre = availableAfter({'a': item('a', deposit: 6, vehicle: 4), 'caja': caja, 's': suelto},
        {'a': 8, 's': 3});
    expect(libre['a']!.total, 2);
    expect(libre['caja']!.total, 1, reason: 'faltaban 2 sueltos: se abre 1 caja');
    expect(libre['s']!.total, 3, reason: '1 + 5 de la caja − 3 comprometidos');
  });

  test('cargar vehículo: "Pedidos a entregar" propone solo lo que falta subir', () {
    final caja = StockItem(id: 'caja', name: 'Caja x 5', code: '', category: 'x', photo: null,
        controlled: true, deposit: 5, vehicle: 1);
    final suelto = StockItem(id: 's', name: 'Suelto', code: '', category: 'x', photo: null,
        controlled: true, deposit: 0, vehicle: 0, parentId: 'caja', unitsPerParent: 5);
    final items = [item('a', vehicle: 4), item('b', vehicle: 0), item('c', controlled: false), caja, suelto];
    expect(stillToLoad({'a': 6, 'b': 2, 'c': 1}, items), {'a': 2, 'b': 2, 'c': 1});
    expect(stillToLoad({'a': 3}, items), isEmpty, reason: 'ya está arriba');
    expect(stillToLoad({'s': 3}, items), isEmpty, reason: 'se abre la caja que ya está arriba');
  });

  testWidgets('resumen de pedidos nuevos: libres y "para el reparto"', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProductSummaryTable(
              stock: {'a': item('a', deposit: 6, vehicle: 4)},
              committed: const {'a': 8},
              subtractCommitted: true,
              lines: const [SummaryLine('a', 'Producto a', 3)],
            ),
          ),
        ),
      ),
    );
    expect(find.text('Libres'), findsOneWidget);
    expect(find.text('8 para el reparto'), findsOneWidget);
    expect(find.text('Faltan 1'), findsOneWidget);
  });

  test('lo que lleva el vehículo: disponible = arriba − vendido sin entregar', () {
    final v = VehicleStock.fromJson({
      'viaje': {'id': 'v1', 'preventista_id': 'mary', 'abierto_at': '2026-11-17T12:00:00Z'},
      'productos': [
        {'producto_id': 'a', 'en_vehiculo': 8, 'comprometido': 3, 'disponible': 5},
        {'producto_id': 'b', 'en_vehiculo': '2', 'comprometido': '2', 'disponible': 0},
        {'producto_id': 'c', 'en_vehiculo': 5, 'ventas': 0, 'reparto': 3, 'comprometido': 3, 'disponible': 2},
      ],
    });
    expect(v.lines['c']!.available, 2, reason: 'lo del reparto no está libre para venta directa');
    expect(v.lines['c']!.reparto, 3);
    expect(v.lines['c']!.sold, 0);
    expect(v.tripOpen, isTrue);
    expect(v.sellerId, 'mary');
    expect(v.lines['a']!.available, 5);
    expect(v.lines['b']!.available, 0);
    expect(VehicleStock.fromJson({'viaje': null, 'productos': []}).tripOpen, isFalse);
  });

  test('consultas por GET: lo del vehículo y el estado de cada producto', () async {
    final pedidos = <String>[];
    final client = mockClient((request) async {
      pedidos.add('${request.method} ${request.url.path.split('/v1/').last}');
      return switch (request.url.path.split('/').last) {
        'stock_vehiculo_disponible' => jsonResponse(request, {
          'viaje': {'id': 'v1', 'preventista_id': null, 'abierto_at': '2026-11-17T12:00:00Z'},
          'productos': [
            {'producto_id': 'a', 'en_vehiculo': 8, 'comprometido': 0, 'disponible': 8},
          ],
        }),
        'stock_estado' => jsonResponse(request, [
          {'producto_id': 'a', 'control_stock': true, 'deposito': 12, 'vehiculo': 8},
          {'producto_id': 'b', 'control_stock': false, 'deposito': null, 'vehiculo': null},
        ]),
        _ => jsonResponse(request, [
          {'id': 'a', 'codigo': 'A', 'nombre': 'Yerba', 'categoria': 'Almacén', 'foto_path': null},
          {'id': 'b', 'codigo': null, 'nombre': 'Fécula', 'categoria': null, 'foto_path': null},
        ]),
      };
    }, autoRefreshToken: false);
    final vehiculo = await fetchVehicleStock(client);
    expect(vehiculo.lines['a']!.available, 8);
    final items = await fetchStockItems(client);
    expect(items.first.controlled, isTrue);
    expect(items.first.deposit, 12);
    expect(items.last.controlled, isFalse);
    expect(items.last.category, 'Sin categoría');
    expect(pedidos, contains('GET rpc/stock_vehiculo_disponible'));
    expect(pedidos, contains('GET rpc/stock_estado'));
  });

  test('operación de stock sin señal: queda pendiente y se envía con el mismo id', () async {
    final cola = PendingOrders.instance;
    var online = false;
    final enviados = <String>[];
    final client = mockClient((request) async => jsonResponse(request, {}), autoRefreshToken: false);
    await client.auth.setInitialSession(
      jsonEncode({
        'access_token': 'e30.eyJleHAiOjQxMDI0NDQ4MDB9.fixture',
        'refresh_token': 'r',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': {
          'id': 'admin',
          'aud': 'authenticated',
          'role': 'authenticated',
          'app_metadata': {},
          'user_metadata': {},
          'created_at': '2026-01-01T00:00:00Z',
        },
      }),
    );
    await cola.start(
      client,
      send: (_) async => throw http.ClientException('x'),
      sendStock: (p) async {
        if (!online) throw http.ClientException('sin red');
        enviados.add('${p['rpc']} ${(p['args'] as Map)['p_id']}');
      },
    );
    addTearDown(cola.stop);
    await cola.add(PendingOrder.stock(
      rpc: 'stock_registrar_compra',
      args: {'p_id': 's1', 'p_ubicacion': 'vehiculo', 'p_items': []},
      description: 'Compra · Almacén del camino',
      total: 350,
    ));
    final copia = PendingOrder.fromJson(cola.items.value.single.toJson());
    expect(copia.isStock, isTrue);
    expect(copia.id, 's1');
    expect(copia.clientId, isNull);
    online = true;
    expect(await cola.sendAll(), 1);
    expect(enviados, ['stock_registrar_compra s1']);
  });

  testWidgets('contar: manda lo escrito y muestra el resultado', (tester) async {
    String? rpc;
    Map<String, dynamic>? enviado;
    await tester.pumpWidget(
      MaterialApp(
        home: StockFormPage(
          kind: StockFormKind.count,
          items: [item('a'), item('b', controlled: false)],
          runner: (fn, args) async {
            rpc = fn;
            enviado = args;
            return const StockOpOutcome({
              'productos': 1,
              'nuevos_con_stock': 0,
              'diferencias': [
                {'producto_id': 'a', 'antes': 10, 'contado': 7},
              ],
            });
          },
        ),
      ),
    );
    expect(find.text('Producto a'), findsOneWidget);
    expect(find.text('Producto b'), findsNothing, reason: 'los "a pedido" se suman con el filtro');
    await tester.enterText(find.widgetWithText(TextField, 'Cantidad'), '7');
    await tester.pump();
    await tester.tap(find.text('CONFIRMAR (1 producto)'));
    await tester.pumpAndSettle();
    expect(rpc, 'stock_contar');
    expect(enviado!['p_ubicacion'], depositoCodigo);
    expect(enviado!['p_items'], [
      {'producto_id': 'a', 'cantidad': 7.0},
    ]);
    expect(find.textContaining('Listo: 1 producto contado.'), findsOneWidget);
    expect(find.textContaining('Producto a: había 10, contaste 7'), findsOneWidget);
  });

  testWidgets('cargar vehículo: colores, marcar en flúor y confirmar', (tester) async {
    String? rpc;
    await tester.pumpWidget(
      MaterialApp(
        home: StockFormPage(
          kind: StockFormKind.load,
          items: [item('a'), item('b')],
          runner: (fn, args) async {
            rpc = fn;
            return const StockOpOutcome({'viaje_nuevo': true, 'movidos': 1, 'a_pedido': 0});
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Escribí qué cargar'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('cantidad-a')), '3');
    await tester.pump();
    expect(find.text('0 de 1 cargados'), findsOneWidget);
    expect(find.text('Hay 10'), findsOneWidget, reason: 'verde: alcanza lo del depósito');
    await tester.enterText(find.byKey(const ValueKey('cantidad-b')), '12');
    await tester.pump();
    expect(find.text('Faltan 2 · hay 10'), findsOneWidget, reason: 'rojo: no alcanza');
    await tester.enterText(find.byKey(const ValueKey('cantidad-b')), '');
    await tester.pump();
    // Tocar la fila (no solo la casilla) la marca: queda resaltada en flúor.
    await tester.tap(find.text('Producto a'));
    await tester.pump();
    expect(find.text('1 de 1 cargados'), findsOneWidget);
    final fila = tester.widget<Material>(
      find.ancestor(of: find.text('Producto a'), matching: find.byType(Material)).first,
    );
    expect(fila.color, const Color(0xFFFFF176));
    await tester.tap(find.text('CONFIRMAR (1 producto)'));
    await tester.pumpAndSettle();
    expect(find.text('Faltan marcar'), findsNothing);
    expect(rpc, 'stock_cargar_vehiculo');
    expect(find.textContaining('Vehículo cargado'), findsOneWidget);
  });

  testWidgets('cargar vehículo: borrar la cantidad no saca la fila; 0 no se carga', (tester) async {
    Map<String, dynamic>? enviado;
    await tester.pumpWidget(
      MaterialApp(
        home: StockFormPage(
          kind: StockFormKind.load,
          items: [item('a'), item('b'), item('c')],
          runner: (fn, args) async {
            enviado = args;
            return const StockOpOutcome({'viaje_nuevo': false, 'movidos': 1, 'a_pedido': 0});
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('cantidad-a')), '3');
    await tester.enterText(find.byKey(const ValueKey('cantidad-b')), '2');
    await tester.pump();
    await tester.ensureVisible(find.text('Solo con cantidad'));
    await tester.tap(find.text('Solo con cantidad'));
    await tester.pump();
    expect(find.text('Producto c'), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('cantidad-a')), '');
    await tester.pump();
    expect(find.text('Producto a'), findsOneWidget, reason: 'sigue a la vista mientras se edita');
    await tester.enterText(find.byKey(const ValueKey('cantidad-a')), '0');
    await tester.pump();
    expect(find.text('No se carga'), findsOneWidget);
    expect(find.text('0 de 1 cargados'), findsOneWidget);
    await tester.tap(find.text('Producto b'));
    await tester.pump();
    await tester.tap(find.text('CONFIRMAR (1 producto)'));
    await tester.pumpAndSettle();
    expect(enviado!['p_items'], [
      {'producto_id': 'b', 'cantidad': 2.0},
    ]);
  });

  Future<void> openHome(WidgetTester tester, {required bool admin}) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: DesktopHome(name: 'Fixture', isAdmin: admin, onSignOut: () {})),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Windows: el administrador entra a Stock', (tester) async {
    await openHome(tester, admin: true);
    final menu = find.ancestor(of: find.text('Saldos'), matching: find.byType(Scrollable));
    await tester.scrollUntilVisible(find.text('Stock'), 200, scrollable: menu);
    await tester.tap(find.text('Stock'));
    await tester.pumpAndSettle();
    expect(find.byType(StockHomePage), findsOneWidget);
    expect(find.text('Lo que llevamos'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Windows: el preventista ve "Lo que llevamos" y no Stock', (tester) async {
    await openHome(tester, admin: false);
    expect(find.text('Stock'), findsNothing);
    await tester.tap(find.text('Lo que llevamos'));
    await tester.pumpAndSettle();
    expect(find.byType(VehicleLoadPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
