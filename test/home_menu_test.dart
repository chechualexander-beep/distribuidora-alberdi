import 'package:distribuidora_alberdi/core/app_theme.dart';
import 'package:distribuidora_alberdi/features/home/home_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('inicio: Nuevo pedido arriba y accesos en tres columnas', (tester) async {
    final tocados = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: temaClaro(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                NewOrderButton(onTap: () => tocados.add('nuevo')),
                HomeSection(
                  title: 'TRABAJO DIARIO',
                  actions: [
                    HomeAction(Icons.receipt_long_outlined, 'Pedidos', () => tocados.add('pedidos')),
                    HomeAction(Icons.people_outline, 'Clientes', () => tocados.add('clientes')),
                    HomeAction(Icons.inventory_2_outlined, 'Productos', () => tocados.add('productos')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('NUEVO PEDIDO'), findsOneWidget);
    expect(find.text('TRABAJO DIARIO'), findsOneWidget);
    // Pedidos, Clientes y Productos en la misma fila.
    expect(tester.getTopLeft(find.text('Pedidos')).dy, tester.getTopLeft(find.text('Clientes')).dy);
    expect(tester.getTopLeft(find.text('Productos')).dy, tester.getTopLeft(find.text('Pedidos')).dy);
    await tester.tap(find.text('NUEVO PEDIDO'));
    await tester.tap(find.text('Productos'));
    expect(tocados, ['nuevo', 'productos']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('modo oscuro: los accesos no quedan blancos', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: temaOscuro(),
        home: Scaffold(
          body: HomeSection(
            title: 'ADMINISTRACIÓN',
            actions: [HomeAction(Icons.account_balance_wallet_outlined, 'Saldos', () {})],
          ),
        ),
      ),
    );
    final tile = tester.widget<Material>(
      find.ancestor(of: find.text('Saldos'), matching: find.byType(Material)).first,
    );
    expect(tile.color, isNot(Colors.white));
  });

  testWidgets('inicio: cada grupo con su color, números pendientes y Hoy', (tester) async {
    final tocados = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: temaClaro(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                TodayCard(
                  title: 'Hoy, domingo 22',
                  items: [
                    TodayItem(HomeArea.facturacion, '4', 'para facturar', () => tocados.add('facturar')),
                    TodayItem(HomeArea.herramientas, '2', 'en negativo', () => tocados.add('negativos'), alert: true),
                  ],
                ),
                HomeSection(
                  title: 'REPARTO Y STOCK',
                  area: HomeArea.reparto,
                  actions: [HomeAction(Icons.route_outlined, 'Reparto', () => tocados.add('reparto'), badge: 7)],
                ),
                HomeSection(
                  title: 'PLATA',
                  area: HomeArea.plata,
                  actions: [
                    HomeAction(Icons.receipt_outlined, 'Anotar gasto', () => tocados.add('gasto'), highlight: true),
                    HomeAction(Icons.insights, 'Tablero del mes', () {}),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('para facturar'), findsOneWidget);
    expect(find.byKey(const ValueKey('badge-Reparto')), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    Color? fondo(String texto) =>
        tester.widget<Material>(find.ancestor(of: find.text(texto), matching: find.byType(Material)).first).color;
    expect(fondo('Reparto'), const Color(0xFFE1F5EE), reason: 'reparto en verde');
    expect(fondo('Anotar gasto'), AppColors.dorado, reason: 'destacado, lleno');
    expect(fondo('Tablero del mes'), const Color(0xFFFAEEDA));
    expect(fondo('en negativo'), const Color(0xFFFCEBEB), reason: 'en rojo si hay negativos');
    await tester.tap(find.text('para facturar'));
    await tester.tap(find.text('Anotar gasto'));
    await tester.tap(find.text('Reparto'));
    expect(tocados, ['facturar', 'gasto', 'reparto']);
    expect(tester.takeException(), isNull);
  });
}
