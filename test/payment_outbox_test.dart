import 'dart:async';
import 'dart:io';
import 'package:distribuidora_alberdi/core/payment_outbox.dart';
import 'package:distribuidora_alberdi/core/payment_money.dart';
import 'package:distribuidora_alberdi/features/balances/balance_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'helpers/balance_fixture.dart';

void main() {
  late Directory directory;
  late PaymentOutbox store;
  late FakeBalanceRepository repo;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('alberdi-payment-test-');
    store = PaymentOutbox.open(directory.path);
    repo = FakeBalanceRepository();
  });
  tearDown(() {
    store.close();
    directory.deleteSync(recursive: true);
  });

  PaymentRequest prepare() => store.prepare(repo.scope, repo.actor, 'client', {
    'p_cliente_id': 'client',
    'p_importe': 25.25,
    'p_medio_pago': 'Efectivo',
    'p_observacion': null,
  });
  Future<Map<String, dynamic>> send(
    PaymentRequest r, {
    Future<Object?> Function(String, Map<String, dynamic>)? rpc,
    bool definitive = false,
  }) => store.send(
    scope: repo.scope,
    actor: repo.actor,
    client: 'client',
    id: r.id,
    sessionMatches: () => repo.sessionMatches,
    rpc: rpc ?? repo.pay,
    requiresReview: (_) => definitive,
  );

  test(
    'paginación respeta count incluso con un límite menor al solicitado',
    () async {
      final offsets = <int>[];
      final rows = await allBalancePages((offset) async {
        offsets.add(offset);
        return BalancePage(
          List.generate(
            offset == 1000 ? 5 : 500,
            (i) => {'cliente_id': 'c${offset + i}', 'saldo_pendiente': 1},
          ),
          1005,
        );
      });
      expect(offsets, [0, 500, 1000]);
      expect(debtorTotal(rows), 100500);
      await expectLater(
        allBalancePages((_) async => BalancePage([], 1)),
        throwsStateError,
      );
      await expectLater(
        allBalancePages(
          (offset) async => BalancePage([{}], offset == 0 ? 2 : 3),
        ),
        throwsStateError,
      );
    },
  );

  test('importes monetarios exactos y fecha argentina', () {
    expect(paymentCents('12,25'), 1225);
    expect(paymentCents('12.2500'), 1225);
    expect(centsMoney(1225), r'$12.25');
    expect(balanceDate('2026-11-05T01:00:00Z'), '04/11/2026');
    for (final value in [null, 'NaN', '-1', '1.001', 'Infinity']) {
      expect(() => paymentCents(value), throwsFormatException);
    }
  });

  test(
    'persiste antes del envío, RPC única e imputaciones de varios pedidos',
    () async {
      final r = prepare();
      final result = await send(
        r,
        rpc: (name, params) async {
          expect(name, 'registrar_pago_cliente_contextual');
          final second = PaymentOutbox.open(directory.path);
          try {
            expect(
              second.active(repo.scope, repo.actor, 'client')!.payload,
              params,
            );
          } finally {
            second.close();
          }
          return repo.pay(name, params);
        },
      );
      expect(result['imputaciones'], hasLength(2));
      expect(repo.saved, hasLength(1));
      final calls = repo.calls;
      expect(await send(r), result);
      expect(repo.calls, calls);
      store.seen(repo.scope, repo.actor, 'client', r.id);
      expect(prepare().id, isNot(r.id));
    },
  );

  test('respuesta perdida y reinicio recuperan el mismo UUID', () async {
    final r = prepare();
    repo.loseResponse = true;
    await expectLater(send(r), throwsStateError);
    expect(() => prepare(), throwsA(isA<PaymentReview>()));
    store.close();
    store = PaymentOutbox.open(directory.path);
    final recovered = store.active(repo.scope, repo.actor, 'client')!;
    expect(recovered.payload, r.payload);
    await send(recovered);
    expect(repo.saved, hasLength(1));
    expect(repo.calls, 2);
  });

  test('doble clic, actor y entorno quedan separados', () async {
    final r = prepare();
    expect(
      () => store.active(repo.scope, 'other', 'client'),
      throwsA(isA<PaymentReview>()),
    );
    expect(store.active('production:fixture', repo.actor, 'client'), isNull);
    store.prepare('production:fixture', repo.actor, 'client', {
      'p_cliente_id': 'client',
      'p_importe': 1,
    });
    final gate = Completer<Object?>();
    final first = send(r, rpc: (_, _) => gate.future);
    await expectLater(send(r), throwsA(isA<PaymentReview>()));
    gate.complete(
      await repo.pay('registrar_pago_cliente_contextual', r.payload),
    );
    await first;
    repo.validSession = false;
    await expectLater(send(r), throwsA(isA<PaymentReview>()));
  });

  test('conflicto definitivo conserva solicitud y bloquea reemplazo', () async {
    final r = prepare();
    await expectLater(
      send(
        r,
        rpc: (_, _) async => throw StateError('conflicto'),
        definitive: true,
      ),
      throwsStateError,
    );
    expect(store.active(repo.scope, repo.actor, 'client')!.state, 'review');
    expect(() => prepare(), throwsA(isA<PaymentReview>()));
    await expectLater(send(r), throwsA(isA<PaymentReview>()));
  });

  test('respuesta incompatible conserva pago incierto', () async {
    final r = prepare();
    await expectLater(
      send(r, rpc: (_, _) async => {'solicitud_id': 'otro'}),
      throwsStateError,
    );
    expect(store.active(repo.scope, repo.actor, 'client')!.state, 'pending');
  });
}
