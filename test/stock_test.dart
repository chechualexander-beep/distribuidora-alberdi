import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:distribuidora_alberdi/features/stock/stock_models.dart';
import 'package:distribuidora_alberdi/features/stock/stock_service.dart';
import 'package:distribuidora_alberdi/features/stock/stock_page.dart';
import 'package:distribuidora_alberdi/features/stock/stock_adjust_dialog.dart';
import 'package:distribuidora_alberdi/features/stock/stock_movements_page.dart';

StockProduct product(
  String id, {
  bool initialized = false,
  bool active = true,
  int millis = 0,
}) => StockProduct.fromJson({
  'producto_id': id,
  'nombre': 'Producto $id',
  'codigo': id.toUpperCase(),
  'activo': active,
  'costo_actual': '50.25',
  'cantidad': StockQuantity(millis).format(),
  'inicializado': initialized,
  'valor_stock': millis / 1000 * 50.25,
});
const location = StockLocation(
  'deposito-id',
  'Depósito Distribuidora Alberdi',
  true,
);
StockSnapshot snapshot(List<StockProduct> products) => StockSnapshot(
  location,
  products,
  StockSummary(
    products.where((p) => p.initialized).length,
    StockQuantity(
      products
          .where((p) => p.initialized)
          .fold(0, (sum, p) => sum + p.quantity.millis),
    ),
    products.where((p) => p.initialized).fold(0, (sum, p) => sum + p.value),
  ),
);

class FakeStockService extends StockService {
  FakeStockService(this.data);
  StockSnapshot data;
  int loads = 0, initialCalls = 0, adjustCalls = 0;
  List<Map<String, dynamic>>? submitted;
  Completer<int>? pending;
  Object? failure;
  StockQuantity? adjusted;
  List<StockMovement> history = [];
  int historyCalls = 0;
  @override
  Future<List<StockMovement>> movements(
    String location, {
    String search = '',
    String? type,
    int offset = 0,
  }) async {
    historyCalls++;
    return history
        .where(
          (m) =>
              (type == null || m.type == type) &&
              '${m.name} ${m.code}'.toLowerCase().contains(
                search.toLowerCase(),
              ),
        )
        .skip(offset)
        .take(StockService.movementPageSize)
        .toList();
  }

  @override
  Future<StockSnapshot> load() async {
    loads++;
    if (failure != null) throw failure!;
    return data;
  }

  @override
  Future<int> initialize(
    String location,
    List<Map<String, dynamic>> items,
  ) async {
    initialCalls++;
    submitted = items;
    if (pending != null) await pending!.future;
    data = snapshot([
      for (final p in data.products)
        items.any((i) => i['producto_id'] == p.id)
            ? product(
                p.id,
                initialized: true,
                millis: StockQuantity.fromRpc(
                  items.firstWhere((i) => i['producto_id'] == p.id)['cantidad'],
                ).millis,
              )
            : p,
    ]);
    return items.length;
  }

  @override
  Future<void> adjust(
    String location,
    String id,
    StockQuantity quantity,
    String reason,
    String observation,
  ) async {
    adjustCalls++;
    adjusted = quantity;
    data = snapshot([
      for (final p in data.products)
        p.id == id
            ? product(id, initialized: true, millis: quantity.millis)
            : p,
    ]);
  }
}

void main() {
  test(
    'Cantidades exactas, hasta tres decimales y sin redondeos silenciosos',
    () {
      for (final pair in {
        '20.000': '20',
        '20.500': '20.5',
        '1,250': '1.25',
        '0': '0',
        '0.001': '0.001',
        '99999999999.999': '99999999999.999',
      }.entries) {
        final quantity = StockQuantity.input(pair.key)!;
        expect(quantity.format(), pair.value);
        expect(
          StockQuantity.fromRpc(
            jsonDecode(jsonEncode(quantity.toJsonNumber())),
          ).millis,
          quantity.millis,
        );
      }
      for (final text in [
        '-1',
        'NaN',
        'Infinity',
        '1.0001',
        '100000000000',
        '1.2.3',
        '1e3',
        'abc',
      ]) {
        expect(() => StockQuantity.input(text), throwsFormatException);
      }
    },
  );
  test(
    'Vacío omite, cero inicializa; productos inicializados nunca se envían',
    () {
      final products = [
        product('a'),
        product('b'),
        product('c', initialized: true),
      ];
      expect(initialStockItems(products, {'a': '', 'b': '0', 'c': '99'}), [
        {'producto_id': 'b', 'cantidad': 0},
      ]);
      expect(StockQuantity.input('   '), isNull);
      expect(
        () => initialStockItems(products, {'a': '1.1111'}),
        throwsFormatException,
      );
    },
  );
  test('Diferencias visuales exactas, positivas, negativas y cero', () {
    final previous = StockQuantity.input('20')!;
    expect(
      StockQuantity.input('18')!.difference(previous).format(signed: true),
      '-2',
    );
    expect(
      StockQuantity.input('25')!.difference(previous).format(signed: true),
      '+5',
    );
    expect(
      StockQuantity.input('20')!.difference(previous).format(signed: true),
      '0',
    );
    expect(
      StockQuantity.input('20.001')!.difference(previous).format(signed: true),
      '+0.001',
    );
  });
  test(
    'Filtros por texto, estado y pendientes independientes del saldo cero',
    () {
      final products = [
        product('a'),
        product('b', initialized: true),
        product('c', active: false),
      ];
      expect(filterStock(products, 'B', StockFilter.all).map((p) => p.id), [
        'b',
      ]);
      expect(filterStock(products, '', StockFilter.active).length, 2);
      expect(filterStock(products, '', StockFilter.inactive).single.id, 'c');
      expect(
        filterInitialStock(
          products,
          '',
          InitialStockFilter.initialized,
        ).single.id,
        'b',
      );
      expect(
        filterInitialStock(products, '', InitialStockFilter.pending).length,
        2,
      );
    },
  );
  test('Parseo RPC de números y strings, resumen e historial con joins', () {
    final zero = product('a', initialized: true);
    expect(zero.initialized, isTrue);
    expect(zero.quantity.millis, 0);
    final summary = StockSummary.fromJson({
      'productos_distintos': 2,
      'unidades_totales': '1.250',
      'valor_estimado_total': 62.8125,
    });
    expect(summary.units.format(), '1.25');
    expect(summary.products, 2);
    final movement = StockMovement.fromJson({
      'id': 'm',
      'created_at': '2026-10-06T12:30:00Z',
      'producto': {'nombre': 'Tutuca', 'codigo': '124'},
      'usuario': {'nombre': 'Admin', 'apellido': 'Pruebas'},
      'tipo': 'ajuste_salida',
      'cantidad_anterior': '20.000',
      'cantidad_delta': -2,
      'cantidad_nueva': 18,
      'motivo': 'Rotura',
      'observacion': null,
    });
    expect(movement.user, 'Admin Pruebas');
    expect(movement.delta.format(signed: true), '-2');
    expect(movement.formattedDate, '06/10/2026 09:30');
    expect(movementLabel(movement.type), 'Ajuste salida');
  });
  test(
    'Errores seguros sin detalles PostgreSQL y sin confirmar éxito de red',
    () {
      expect(
        stockError(const SocketException('SECRET')),
        contains('Actualizá Stock'),
      );
      expect(
        stockError(
          const PostgrestException(message: 'secret SQL', code: '42501'),
        ),
        contains('administrador activo'),
      );
      expect(
        stockError(
          const PostgrestException(message: 'secret SQL', code: '23505'),
        ),
        contains('ya tiene stock inicial'),
      );
      expect(
        stockError(Exception('password SECRET stack')),
        isNot(contains('SECRET')),
      );
    },
  );

  Future<void> page(
    WidgetTester tester,
    FakeStockService service, {
    bool dark = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1250, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
        home: StockPage(service: service),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('TESTING vacío y modo oscuro sin errores ni escrituras', (
    tester,
  ) async {
    final service = FakeStockService(snapshot([]));
    await page(tester, service, dark: true);
    expect(find.text('No hay productos cargados.'), findsOneWidget);
    expect(find.text('Valor estimado a costo actual'), findsOneWidget);
    expect(service.initialCalls + service.adjustCalls, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Ubicación ausente: error claro y reintento, sin crear ubicación', (
    tester,
  ) async {
    final service = FakeStockService(snapshot([]))
      ..failure = const StockException(
        'No se encontró Depósito Distribuidora Alberdi. Contactá a administración.',
      );
    await page(tester, service);
    expect(find.textContaining('No se encontró Depósito'), findsOneWidget);
    service.failure = null;
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.text('No hay productos cargados.'), findsOneWidget);
    expect(service.loads, 2);
  });
  testWidgets('Carga masiva una sola vez, cero explícito y refresh inmediato', (
    tester,
  ) async {
    final service = FakeStockService(
      snapshot([product('a'), product('b', initialized: true), product('c')]),
    )..pending = Completer<int>();
    await page(tester, service);
    await tester.tap(find.text('Cargar inventario inicial'));
    await tester.pumpAndSettle();
    final disabled = tester.widget<TextField>(
      find.byKey(const ValueKey('initial-b')),
    );
    expect(disabled.enabled, isFalse);
    await tester.enterText(find.byKey(const ValueKey('initial-a')), '0');
    await tester.pump();
    expect(find.text('Productos a inicializar: 1'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('initial-search')),
      'Producto c',
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('initial-a')), findsNothing);
    expect(find.text('Productos a inicializar: 1'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('initial-search')), '');
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('initial-a')))
          .controller!
          .text,
      '0',
    );
    await tester.tap(find.text('Guardar inventario inicial'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('inventario inicial de 1 producto'),
      findsOneWidget,
    );
    await tester.tap(find.text('Confirmar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(service.initialCalls, 1);
    expect(service.submitted, [
      {'producto_id': 'a', 'cantidad': 0},
    ]);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Procesando…'),
          )
          .onPressed,
      isNull,
    );
    service.pending!.complete(1);
    await tester.pumpAndSettle();
    expect(service.loads, 2);
    expect(find.text('Se inicializó 1 producto.'), findsOneWidget);
    expect(service.data.products.first.initialized, isTrue);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Ajuste no guarda delta cero y refresca al guardar', (
    tester,
  ) async {
    final service = FakeStockService(
      snapshot([product('a', initialized: true, millis: 20000)]),
    );
    await page(tester, service);
    await tester.tap(find.text('Ajustar'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('physical-count')), '20');
    await tester.pump();
    expect(find.text('Diferencia: 0'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Guardar'))
          .onPressed,
      isNull,
    );
    await tester.enterText(find.byKey(const ValueKey('physical-count')), '25');
    await tester.pump();
    expect(find.text('Diferencia: +5'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('physical-count')), '18');
    await tester.pump();
    expect(find.text('Diferencia: -2'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await tester.pumpAndSettle();
    expect(find.byType(StockAdjustDialog), findsNothing);
    expect(service.adjustCalls, 1);
    expect(service.adjusted!.millis, 18000);
    expect(service.loads, 2);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Windows compacto con texto aumentado no desborda', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 650);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = FakeStockService(
      snapshot([product('a', initialized: true, millis: 20000)]),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: Row(
          children: [
            const SizedBox(width: 220),
            Expanded(child: StockPage(service: service)),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Stock')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('Historial de solo lectura, etiquetas amigables y búsqueda', (
    tester,
  ) async {
    final service = FakeStockService(snapshot([]))
      ..history = [
        StockMovement.fromJson({
          'id': 'm',
          'created_at': '2026-10-06T12:30:00Z',
          'producto': {'nombre': 'Tutuca', 'codigo': '124'},
          'usuario': {'nombre': 'Admin', 'apellido': 'Pruebas'},
          'tipo': 'ajuste_salida',
          'cantidad_anterior': 20,
          'cantidad_delta': -2,
          'cantidad_nueva': 18,
          'motivo': 'Rotura',
          'observacion': null,
        }),
      ];
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: StockMovementsPage(location: location, service: service),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ajuste salida'), findsOneWidget);
    expect(find.text('ajuste_salida'), findsNothing);
    expect(find.text('Tutuca'), findsOneWidget);
    expect(find.text('Guardar'), findsNothing);
    await tester.enterText(find.byType(TextField), 'inexistente');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(
      find.text('No hay movimientos que coincidan con los filtros.'),
      findsOneWidget,
    );
    expect(service.historyCalls, 2);
    expect(service.adjustCalls + service.initialCalls, 0);
    expect(tester.takeException(), isNull);
  });
}
