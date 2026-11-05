import 'dart:io';
import 'package:distribuidora_alberdi/core/payment_outbox.dart';
import 'package:distribuidora_alberdi/features/balances/balances_page.dart';
import 'package:distribuidora_alberdi/features/balances/client_payment_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'helpers/balance_fixture.dart';

void main() {
  late FakeBalanceRepository repo;
  late Directory pageDirectory;
  late PaymentOutbox pageStore;
  setUp(() {
    repo = FakeBalanceRepository();
    pageDirectory = Directory.systemTemp.createTempSync(
      'alberdi-balances-test-',
    );
    pageStore = PaymentOutbox.open(pageDirectory.path);
  });
  tearDown(() {
    pageStore.close();
    pageDirectory.deleteSync(recursive: true);
  });

  testWidgets('listado de deudores, buscador y total general', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BalancesPage(repository: repo, paymentStore: pageStore),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(r'Total general por cobrar: $100.00'), findsOneWidget);
    expect(find.text('Cliente QA'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'sin coincidencia');
    await tester.pump();
    expect(find.text('Sin coincidencias.'), findsOneWidget);
    expect(find.text(r'Total general por cobrar: $100.00'), findsOneWidget);
  });

  testWidgets('lista vacía y error son estados distintos', (tester) async {
    repo.debt = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: BalancesPage(repository: repo, paymentStore: pageStore),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sin clientes con deuda.'), findsOneWidget);
    repo.failReads = true;
    await tester.tap(find.byTooltip('Actualizar saldos'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('balances-error')), findsOneWidget);
    expect(find.byKey(const ValueKey('balances-total')), findsNothing);
  });

  testWidgets(
    'un pago incierto sigue recuperable aunque canceló toda la deuda',
    (tester) async {
      final saved = pageStore.prepare(repo.scope, repo.actor, 'client', {
        'p_cliente_id': 'client',
        'p_importe': 100,
        'p_medio_pago': 'Efectivo',
        'p_observacion': null,
      });
      repo.loseResponse = true;
      await expectLater(
        pageStore.send(
          scope: repo.scope,
          actor: repo.actor,
          client: 'client',
          id: saved.id,
          sessionMatches: () => true,
          rpc: repo.pay,
          requiresReview: (_) => false,
        ),
        throwsStateError,
      );
      expect(repo.debt, 0);
      await tester.pumpWidget(
        MaterialApp(
          home: BalancesPage(repository: repo, paymentStore: pageStore),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sin clientes con deuda.'), findsOneWidget);
      expect(find.text('Recuperar pago pendiente'), findsOneWidget);
      expect(find.text('Pago guardado · Cliente QA'), findsOneWidget);
    },
  );

  testWidgets('preventista no accede a la consulta administrativa', (
    tester,
  ) async {
    repo.admin = false;
    await tester.pumpWidget(
      MaterialApp(
        home: BalancesPage(repository: repo, paymentStore: pageStore),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('balances-error')), findsOneWidget);
  });

  testWidgets(
    'detalle presenta entregas reales, créditos y modo solo consulta',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ClientBalancePage(
            clientId: 'client',
            repository: repo,
            readOnly: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining(r'Entregado: $150.00'), findsOneWidget);
      expect(find.textContaining(r'Crédito aplicado: $20.00'), findsOneWidget);
      expect(find.text('Registrar pago'), findsNothing);
    },
  );

  testWidgets('oculta importes cero y conserva los ajustes positivos', (
    tester,
  ) async {
    repo.noteAmount = 0;
    repo.appliedCredit = 0;
    repo.favor = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ClientBalancePage(clientId: 'client', repository: repo),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Notas internas:'), findsNothing);
    expect(find.textContaining('Crédito aplicado:'), findsNothing);
    expect(find.textContaining('Saldo a favor:'), findsNothing);
    repo.noteAmount = 10;
    repo.appliedCredit = 20;
    repo.favor = 15;
    await tester.tap(find.byTooltip('Actualizar cuenta'));
    await tester.pumpAndSettle();
    expect(find.textContaining(r'Notas internas: $10.00'), findsOneWidget);
    expect(find.textContaining(r'Crédito aplicado: $20.00'), findsOneWidget);
    expect(find.textContaining(r'Saldo a favor: $15.00'), findsOneWidget);
  });

  for (final amount in ['25', '100']) {
    testWidgets(
      'cobro $amount confirma, muestra imputaciones y actualiza cuenta',
      (tester) async {
        final directory = Directory.systemTemp.createTempSync(
          'alberdi-form-test-',
        );
        final store = PaymentOutbox.open(directory.path);
        addTearDown(() {
          store.close();
          directory.deleteSync(recursive: true);
        });
        var refreshed = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ClientPaymentDialog(
                repository: repo,
                clientId: 'client',
                clientName: 'Cliente QA',
                store: store,
                onConfirmed: () async {
                  refreshed++;
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, amount);
        await tester.tap(find.text('Confirmar pago'));
        await tester.pumpAndSettle();
        expect(refreshed, 1);
        expect(repo.saved, hasLength(1));
        expect(find.textContaining('Aplicado'), findsNWidgets(2));
        expect(find.textContaining('Cobrado:'), findsOneWidget);
        expect(find.text('Confirmar pago'), findsNothing);
        expect(repo.debt, 10000 - int.parse(amount) * 100);
      },
    );
  }

  testWidgets('servidor sin RPC mantiene deshabilitado el formulario', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync(
      'alberdi-capability-test-',
    );
    final store = PaymentOutbox.open(directory.path);
    addTearDown(() {
      store.close();
      directory.deleteSync(recursive: true);
    });
    repo.capable = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ClientPaymentDialog(
            repository: repo,
            clientId: 'client',
            clientName: 'Cliente QA',
            store: store,
            onConfirmed: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Cobros deshabilitados'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Confirmar pago'),
          )
          .onPressed,
      isNull,
    );
    expect(repo.calls, 0);
  });

  testWidgets('un rechazo definitivo se muestra en revisión sin otro envío', (
    tester,
  ) async {
    final request = pageStore.prepare(repo.scope, repo.actor, 'client', {
      'p_cliente_id': 'client',
      'p_importe': 25,
      'p_medio_pago': 'Efectivo',
      'p_observacion': null,
    });
    await expectLater(
      pageStore.send(
        scope: repo.scope,
        actor: repo.actor,
        client: 'client',
        id: request.id,
        sessionMatches: () => true,
        rpc: (_, _) async => throw StateError('Rechazado'),
        requiresReview: (_) => true,
      ),
      throwsStateError,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ClientPaymentDialog(
            repository: repo,
            clientId: 'client',
            clientName: 'Cliente QA',
            store: pageStore,
            onConfirmed: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('El pago requiere revisión'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Recuperar pago pendiente'),
          )
          .onPressed,
      isNull,
    );
    expect(repo.calls, 0);
  });

  testWidgets(
    'respuesta perdida muestra recuperación y no habilita otro pago',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync(
        'alberdi-uncertain-test-',
      );
      final store = PaymentOutbox.open(directory.path);
      addTearDown(() {
        store.close();
        directory.deleteSync(recursive: true);
      });
      repo.loseResponse = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ClientPaymentDialog(
              repository: repo,
              clientId: 'client',
              clientName: 'Cliente QA',
              store: store,
              onConfirmed: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '25');
      await tester.tap(find.text('Confirmar pago'));
      await tester.pumpAndSettle();
      expect(find.text('Recuperar pago pendiente'), findsOneWidget);
      expect(find.text('Confirmar pago'), findsNothing);
      await tester.tap(find.text('Recuperar pago pendiente'));
      await tester.pumpAndSettle();
      expect(repo.saved, hasLength(1));
      expect(repo.debt, 7500);
      expect(find.textContaining('Cobrado:'), findsOneWidget);
    },
  );
}
