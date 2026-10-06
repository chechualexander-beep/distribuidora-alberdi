import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:distribuidora_alberdi/core/session_lock.dart';

void main() {
  testWidgets('Atrás no descarta la ruta que está debajo del bloqueo', (
    tester,
  ) async {
    final nav = GlobalKey<NavigatorState>();
    final guard = SessionLockNavigation();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        navigatorObservers: [guard],
        builder: (context, child) => SessionLock(
          userId: 'vendedor',
          navigation: guard,
          authenticate: () async => true,
          signOut: () async {},
          child: child!,
        ),
        home: const Scaffold(body: Text('Inicio')),
      ),
    );
    nav.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Pedido en curso')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Desbloquear'));
    await tester.pumpAndSettle();
    expect(find.text('Pedido en curso'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    guard.canPopNotifier.dispose();
  });
  testWidgets(
    'bloquea sesión restaurada; cancelación no permite entrar; conserva borrador',
    (tester) async {
      var allow = false;
      final controller = TextEditingController(text: 'Pedido sin guardar');
      await tester.pumpWidget(
        MaterialApp(
          home: SessionLock(
            userId: 'vendedor',
            authenticate: () async => allow,
            signOut: () async {},
            child: Scaffold(body: TextField(controller: controller)),
          ),
        ),
      );
      expect(find.text('Alberdi bloqueada'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.text('Desbloquear'));
      await tester.pumpAndSettle();
      expect(find.text('Alberdi bloqueada'), findsOneWidget);
      allow = true;
      await tester.tap(find.text('Desbloquear'));
      await tester.pumpAndSettle();
      expect(find.text('Pedido sin guardar'), findsOneWidget);
      await tester.pump(const Duration(minutes: 5));
      expect(find.text('Alberdi bloqueada'), findsOneWidget);
      await tester.tap(find.text('Desbloquear'));
      await tester.pumpAndSettle();
      expect(controller.text, 'Pedido sin guardar');
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
  testWidgets(
    'error de autenticación mantiene bloqueo y permite cerrar sesión',
    (tester) async {
      var signedOut = false;
      await tester.pumpWidget(
        MaterialApp(
          home: SessionLock(
            userId: 'vendedor',
            authenticate: () async => throw Exception('sin PIN'),
            signOut: () async {
              signedOut = true;
            },
            child: const Text('Datos privados'),
          ),
        ),
      );
      await tester.tap(find.text('Desbloquear'));
      await tester.pumpAndSettle();
      expect(find.text('Datos privados'), findsNothing);
      expect(find.textContaining('No se pudo verificar'), findsOneWidget);
      await tester.tap(find.text('Cerrar sesión y descartar lo no guardado'));
      await tester.pumpAndSettle();
      expect(signedOut, isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
