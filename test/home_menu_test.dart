import 'package:distribuidora_alberdi/core/app_theme.dart';
import 'package:distribuidora_alberdi/features/home/home_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('inicio: Nuevo pedido arriba y accesos en dos columnas', (tester) async {
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
    // Pedidos y Clientes en la misma fila.
    expect(tester.getTopLeft(find.text('Pedidos')).dy, tester.getTopLeft(find.text('Clientes')).dy);
    expect(tester.getTopLeft(find.text('Productos')).dy, greaterThan(tester.getTopLeft(find.text('Pedidos')).dy));
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
}
