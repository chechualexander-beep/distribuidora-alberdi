import 'dart:convert';

import 'package:distribuidora_alberdi/core/app_config.dart';
import 'package:distribuidora_alberdi/core/pending_orders.dart';
import 'package:distribuidora_alberdi/features/desktop/desktop_home.dart';
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

  test('lo que lleva el vehículo: disponible = arriba − vendido sin entregar', () {
    final v = VehicleStock.fromJson({
      'viaje': {'id': 'v1', 'preventista_id': 'mary', 'abierto_at': '2026-11-17T12:00:00Z'},
      'productos': [
        {'producto_id': 'a', 'en_vehiculo': 8, 'comprometido': 3, 'disponible': 5},
        {'producto_id': 'b', 'en_vehiculo': '2', 'comprometido': '2', 'disponible': 0},
      ],
    });
    expect(v.tripOpen, isTrue);
    expect(v.sellerId, 'mary');
    expect(v.lines['a']!.available, 5);
    expect(v.lines['b']!.available, 0);
    expect(VehicleStock.fromJson({'viaje': null, 'productos': []}).tripOpen, isFalse);
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
    Map<String, dynamic>? enviado;
    final client = mockClient((request) async {
      expect(request.url.path, endsWith('/rpc/stock_contar'));
      enviado = jsonDecode(request.body) as Map<String, dynamic>;
      return jsonResponse(request, {
        'productos': 1,
        'nuevos_con_stock': 0,
        'diferencias': [
          {'producto_id': 'a', 'antes': 10, 'contado': 7},
        ],
      });
    }, autoRefreshToken: false);
    await tester.pumpWidget(
      MaterialApp(
        home: StockFormPage(
          kind: StockFormKind.count,
          items: [item('a'), item('b', controlled: false)],
          client: client,
        ),
      ),
    );
    expect(find.text('Producto a'), findsOneWidget);
    expect(find.text('Producto b'), findsNothing, reason: 'los "a pedido" se suman con el filtro');
    await tester.enterText(find.widgetWithText(TextField, 'Cantidad'), '7');
    await tester.pump();
    await tester.tap(find.text('CONFIRMAR (1 producto)'));
    // Espera acotada (sin pumpAndSettle): deja correr la respuesta y dibuja el resultado.
    for (var i = 0; i < 50 && find.textContaining('Listo').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(enviado!['p_ubicacion'], depositoCodigo);
    expect(enviado!['p_items'], [
      {'producto_id': 'a', 'cantidad': 7.0},
    ]);
    expect(enviado!['p_id'], isA<String>());
    expect(find.textContaining('Listo: 1 producto contado.'), findsOneWidget);
    expect(find.textContaining('Producto a: había 10, contaste 7'), findsOneWidget);
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
