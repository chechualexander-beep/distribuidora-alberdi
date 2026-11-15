import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:distribuidora_alberdi/core/app_config.dart';
import 'package:distribuidora_alberdi/features/invoicing/atomic_invoice.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'helpers/outbox_fixture.dart';

void main() {
  const order = '11111111-2222-4333-8444-555555555555';
  final pending = PendingInvoice(
    newInvoiceRequestId(Random(7)),
    [
      {'detalle_id': 'd1', 'cantidad_facturada': 2},
      {'detalle_id': 'd2', 'cantidad_facturada': 0},
    ],
    [
      {
        'producto_id': 'p3',
        'tipo_precio': 'promo',
        'cantidad_facturada': 4,
        'precio_unitario': 150.5,
      },
    ],
  );

  setUp(() => activateAppConfig(fixtureConfig()));

  test('identificador UUID v4', () {
    for (var i = 0; i < 20; i++) {
      expect(
        newInvoiceRequestId(),
        matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')),
      );
    }
  });

  test('la solicitud pendiente se guarda y se recupera igual', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await AtomicInvoiceStore.open();
    expect(store.read(order), isNull);
    await store.save(order, pending);
    final again = (await AtomicInvoiceStore.open()).read(order)!;
    expect(again.requestId, pending.requestId);
    expect(jsonEncode(again.toJson()), jsonEncode(pending.toJson()));
    await store.clear(order);
    expect(store.read(order), isNull);
  });

  test('qué errores dejan la facturación "sin confirmar"', () {
    expect(isUncertainInvoiceError(TimeoutException('x')), isTrue);
    expect(isUncertainInvoiceError(const PostgrestException(message: 'gw', code: '503')), isTrue);
    expect(isUncertainInvoiceError(const PostgrestException(message: 'x')), isTrue);
    expect(
      isUncertainInvoiceError(const PostgrestException(message: 'ya facturado', code: 'PT409')),
      isFalse,
    );
    expect(isUncertainInvoiceError(const PostgrestException(message: 'no', code: '42501')), isFalse);
  });

  test('corte y reintento: se envía exactamente la misma solicitud', () async {
    final bodies = <Map<String, dynamic>>[];
    var call = 0;
    final client = mockClient((request) async {
      expect(request.url.path, endsWith('/rpc/facturar_pedido'));
      bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
      call++;
      if (call == 1) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      return jsonResponse(request, {
        'numero_comprobante': '1234',
        'fecha_facturacion': '2026-11-16T12:00:00+00:00',
        'repetida': call > 1,
      });
    });
    await expectLater(
      sendAtomicInvoice(client, order, pending, timeout: const Duration(milliseconds: 50)),
      throwsA(isA<UncertainInvoiceException>()),
    );
    final result = await sendAtomicInvoice(client, order, pending);
    expect(result.number, '1234');
    expect(bodies, hasLength(2));
    expect(bodies[0], bodies[1]);
    expect(bodies[0]['p_solicitud_id'], pending.requestId);
    expect(bodies[0]['p_pedido_id'], order);
    expect(bodies[0]['p_originales'], pending.originals);
    expect(bodies[0]['p_agregados'], pending.added);
  });

  test('si el servidor rechaza, el error se informa (no queda pendiente)', () async {
    final client = mockClient(
      (request) async => jsonResponse(request, {
        'code': 'PT409',
        'message': 'El pedido ya está facturado (comprobante 99)',
      }, 409),
    );
    await expectLater(
      sendAtomicInvoice(client, order, pending),
      throwsA(isA<PostgrestException>().having((e) => e.message, 'message', contains('ya está facturado'))),
    );
  });
}
