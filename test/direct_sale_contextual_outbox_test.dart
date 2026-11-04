import 'dart:convert';
import 'dart:io';

import 'package:distribuidora_alberdi/features/orders/finalization_request.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'helpers/outbox_fixture.dart';

void main() {
  test(
    'direct sale keeps separate lines and recovers the same V2 UUID',
    () async {
      final dir = await Directory.systemTemp.createTemp('direct-sale-fixture-');
      addTearDown(() => dir.delete(recursive: true));
      final db = await LocalOutbox.open(dir.path);
      var openDb = db;
      addTearDown(() => openDb.close());
      final store = FinalizationRequestStore(db, fixtureScope, 'admin');
      const order = 'direct-sale-fixture';
      const regime = 'c8be6719-0681-440d-a0aa-2998d8b51c70';
      Map<String, dynamic>? serverResult;
      Map<String, dynamic>? submitted;
      var commits = 0;
      var attempts = 0;
      var preparations = 0;
      var calls = 0;
      final client = mockClient((request) async {
        calls++;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        switch (request.url.pathSegments.last) {
          case 'preparar_finalizacion_contexto':
            preparations++;
            expect(body['p_pedido_id'], order);
            return jsonResponse(request, {
              'solicitud_id': body['p_solicitud_id'],
              'pedido_id': order,
              'actor_id': 'admin',
              'regimen_id': regime,
              'protocolo': 2,
              'fecha_fisica': '2026-11-04T12:00:00Z',
            });
          case 'consultar_finalizacion_solicitud':
            if (submitted != null) {
              expect(body, {'p_solicitud_id': submitted!['p_solicitud_id']});
            }
            return jsonResponse(
              request,
              serverResult == null
                  ? {'estado': 'inexistente'}
                  : {'estado': 'confirmada', 'resultado': serverResult},
            );
          case 'finalizar_gestion_pedido_contexto':
            attempts++;
            if (submitted != null) {
              expect(body, submitted);
              return jsonResponse(request, serverResult);
            }
            commits++;
            submitted = body;
            serverResult = {
              ...receipt(body, outcome: 'parcial'),
              'movimientos_stock': 2,
            };
            throw http.ClientException('Respuesta perdida tras confirmar');
          default:
            fail('RPC inesperada: ${request.url.pathSegments.last}');
        }
      });
      final lines = contextualDeliveryLines([
        {'id': 'original', 'producto_id': 'qa', 'cantidad_entregada': 1},
        {
          'producto_id': 'qa',
          'cantidad_entregada': 0.5,
          'tipo_precio': 'promo',
          'agregado_en_entrega': true,
        },
        {
          'producto_id': 'otro',
          'cantidad_entregada': 1,
          'agregado_en_entrega': true,
        },
      ]);
      expect(lines, {
        'p_originales': [
          {'detalle_id': 'original', 'cantidad_entregada': 1},
        ],
        'p_agregados': [
          {
            'producto_id': 'qa',
            'cantidad_entregada': 0.5,
            'tipo_precio': 'promo',
          },
          {
            'producto_id': 'otro',
            'cantidad_entregada': 1,
            'tipo_precio': 'normal',
          },
        ],
      });
      final payload = await prepareCurrentFinalization(client, store, order, {
        ...operational(quantity: 1),
        ...lines,
      }, config: fixtureConfig());
      expect(payload['p_regimen_id'], regime);
      expect(payload['p_protocolo'], 2);
      expect(store.read(order), payload);
      await expectLater(
        reconcile(client, store, payload),
        throwsA(isA<Exception>()),
      );
      expect(submitted, payload);
      db.close();
      openDb = await LocalOutbox.open(dir.path);
      final restarted = FinalizationRequestStore(openDb, fixtureScope, 'admin');
      expect(restarted.read(order), payload);
      final before = calls;
      await expectLater(
        reconcile(client, restarted, {...payload, 'p_agregados': []}),
        throwsA(isA<LocalOutboxException>()),
      );
      expect(calls, before);
      expect(
        await reconcile(client, restarted, restarted.read(order)!),
        serverResult,
      );
      expect(await reconcile(client, restarted, payload), serverResult);
      expect((preparations, attempts, commits), (1, 2, 1));
      await restarted.acknowledge(order);
      expect(restarted.pendingOrderIds, isEmpty);
    },
  );
}
