import 'dart:async';
import 'dart:io';

import 'package:distribuidora_alberdi/core/return_outbox.dart';
import 'package:distribuidora_alberdi/features/orders/credit_notes_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const scope = 'testing:project', actor = 'admin', order = 'order';
  late Directory directory;
  late ReturnOutbox outbox;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('alberdi-returns-test-');
    outbox = ReturnOutbox.open(directory.path);
  });

  tearDown(() {
    outbox.close();
    directory.deleteSync(recursive: true);
  });

  ReturnRequest prepare(ReturnOperation operation, {String project = scope}) =>
      outbox.prepare(
        project,
        actor,
        order,
        operation,
        operation == ReturnOperation.issue
            ? {
                'p_pedido_id': order,
                'p_motivo': 'Fixture',
                'p_detalles': [
                  {'detalle_id': 'original', 'cantidad': 1},
                ],
              }
            : {
                'p_detalle_id': 'nota-renglon',
                'p_cantidad_apta': 2,
                'p_cantidad_no_apta': 1,
              },
      );

  Future<Map<String, dynamic>> send(
    ReturnRequest request,
    Future<Object?> Function(String, Map<String, dynamic>) rpc, {
    bool sessionMatches = true,
    bool definitive = false,
  }) => outbox.send(
    scope: scope,
    actor: actor,
    order: order,
    id: request.id,
    sessionMatches: () => sessionMatches,
    rpc: rpc,
    requiresReview: (_) => definitive,
  );

  Map<String, dynamic> response(ReturnRequest request) => {
    'solicitud_id': request.id,
    'actor_id': actor,
    'nota_id': 'nota',
    if (request.operation == ReturnOperation.receive) ...{
      'detalle_id': 'nota-renglon',
      'recepcion_id': 'recepcion',
    },
  };

  testWidgets('el diálogo solo confirma una recepción completa', (
    tester,
  ) async {
    (int, int)? received;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () async {
                  received = await showDialog<(int, int)>(
                    context: context,
                    builder: (_) => const ReturnReceiptDialog(total: 300),
                  );
                },
                child: const Text('Registrar recepción'),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('Registrar recepción'));
    await tester.pumpAndSettle();
    final confirm = find.widgetWithText(FilledButton, 'Confirmar recepción');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.enterText(find.byType(TextField).first, '2');
    await tester.pump();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.enterText(find.byType(TextField).last, '1');
    await tester.pump();
    expect(find.textContaining('Ingresará con Stock ON: 2.0'), findsOneWidget);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(received, (200, 100));
  });

  test('recepción completa apta, no apta o mixta y precisión decimal', () {
    expect(returnReceiptAmounts('3', '0', 300), (300, 0));
    expect(returnReceiptAmounts('0', '3', 300), (0, 300));
    expect(returnReceiptAmounts('2', '1', 300), (200, 100));
    expect(returnReceiptAmounts('0,1', '0.2', 30), (10, 20));
    for (final input in ['2.001', '-1', 'NaN', '1e2', '']) {
      expect(returnReceiptAmounts(input, '1', 300), isNull);
    }
    expect(returnReceiptAmounts('1', '1', 300), isNull);
    expect(returnReceiptAmounts('2', '2', 300), isNull);
    expect(returnReceiptLabel(null), 'Pendiente de recepción');
    expect(returnReceiptLabel({'apta_venta': true}), 'Recibido apto');
    expect(returnReceiptLabel({'apta_venta': false}), 'Recibido no apto');
    expect(
      returnReceiptLabel({'cantidad_apta': 2, 'cantidad_no_apta': 1}),
      startsWith('Recibido mixto'),
    );
  });

  test(
    'emite con RPC contextual, persistida antes de invocar y conserva el resultado',
    () async {
      final request = prepare(ReturnOperation.issue);
      final saved = await send(request, (rpc, payload) async {
        expect(rpc, 'emitir_nota_credito_contextual');
        final other = ReturnOutbox.open(directory.path);
        try {
          expect(other.active(scope, actor, order)!.payload, payload);
        } finally {
          other.close();
        }
        return response(request);
      });
      expect(saved, response(request));
      expect(
        await send(request, (_, _) async => fail('No debe reenviar')),
        saved,
      );
      outbox.seen(scope, actor, order, request.id);
      expect(outbox.active(scope, actor, order), isNull);
      expect(prepare(ReturnOperation.issue).id, isNot(request.id));
    },
  );

  test(
    'recepción mixta recupera tras reiniciar con idénticos UUID y contenido',
    () async {
      final request = prepare(ReturnOperation.receive);
      final server = <String, Object>{};
      Future<Object?> fake(String rpc, Map<String, dynamic> payload) async {
        expect(rpc, 'recibir_nota_credito_contextual');
        expect(payload, request.payload);
        final wasConfirmed = server.containsKey(request.id);
        final saved = server.putIfAbsent(request.id, () => response(request));
        if (!wasConfirmed) throw const SocketException('Respuesta perdida');
        return saved;
      }

      await expectLater(send(request, fake), throwsA(isA<SocketException>()));
      expect(
        () => prepare(ReturnOperation.receive),
        throwsA(isA<ReturnReview>()),
      );
      outbox.close();
      outbox = ReturnOutbox.open(directory.path);
      final recovered = outbox.active(scope, actor, order)!;
      expect(recovered.id, request.id);
      expect(await send(recovered, fake), response(request));
      expect(server, hasLength(1));
    },
  );

  test('excluye doble envío, actor ajeno y mezcla de entornos', () async {
    final request = prepare(ReturnOperation.issue);
    expect(
      () => outbox.active(scope, 'otro', order),
      throwsA(isA<ReturnReview>()),
    );
    expect(outbox.active('production:project', actor, order), isNull);
    expect(
      prepare(ReturnOperation.issue, project: 'production:project').id,
      isNot(request.id),
    );
    await expectLater(
      send(
        request,
        (_, _) async => fail('Sesión ajena'),
        sessionMatches: false,
      ),
      throwsA(isA<ReturnReview>()),
    );
    final gate = Completer<Object?>();
    final active = send(request, (_, _) => gate.future);
    await expectLater(
      send(request, (_, _) async => fail('Envío duplicado')),
      throwsA(isA<ReturnReview>()),
    );
    gate.complete(response(request));
    await active;
  });

  test(
    'UUID incompatible va a revisión y una respuesta inválida sigue pendiente',
    () async {
      final request = prepare(ReturnOperation.receive);
      await expectLater(
        send(request, (_, _) async => {'solicitud_id': 'otro'}),
        throwsStateError,
      );
      expect(outbox.active(scope, actor, order)!.state, 'pending');
      await expectLater(
        send(
          request,
          (_, _) async => throw const FormatException('conflicto UUID'),
          definitive: true,
        ),
        throwsFormatException,
      );
      expect(outbox.active(scope, actor, order)!.state, 'review');
      await expectLater(
        send(request, (_, _) async => fail('No se reenvía en revisión')),
        throwsA(isA<ReturnReview>()),
      );
      expect(
        () => prepare(ReturnOperation.receive),
        throwsA(isA<ReturnReview>()),
      );
    },
  );
}
