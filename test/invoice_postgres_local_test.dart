import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:distribuidora_alberdi/features/invoicing/invoice_request.dart';
import 'package:distribuidora_alberdi/features/orders/finalization_request.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const actor = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
String quote(Object? v) => "'${v.toString().replaceAll("'", "''")}'";
void main() {
  final container = Platform.environment['ALBERDI_113B_CONTAINER'];
  test(
    'SQLite + real local PostgreSQL recovery, incompatibility and no commercial effects',
    () async {
      if (container == null ||
          !RegExp(r'^alberdi113b-[a-f0-9]{10}$').hasMatch(container)) {
        throw StateError('Local lab identity required');
      }
      final inspection = await Process.run('docker', ['inspect', container]);
      expect(inspection.exitCode, 0);
      final info = (jsonDecode(inspection.stdout as String) as List).single;
      expect(info['HostConfig']['NetworkMode'], 'none');
      expect(info['Config']['Labels']['alberdi.step'], '113b');
      expect((info['NetworkSettings']['Ports'] as Map?) ?? {}, isEmpty);
      Future<String> sql(String q) async {
        final process = await Process.start('docker', [
          'exec',
          '-i',
          container,
          'psql',
          '-XAtq',
          '-v',
          'ON_ERROR_STOP=1',
          '-v',
          'VERBOSITY=sqlstate',
          '-U',
          'postgres',
          '-d',
          'alberdi_v2_lab',
        ]);
        process.stdin.write(q);
        await process.stdin.close();
        final out = await process.stdout.transform(utf8.decoder).join();
        final error = await process.stderr.transform(utf8.decoder).join();
        final code = await process.exitCode;
        if (code != 0) {
          throw PostgrestException(
            message: error.contains('PT409')
                ? 'solicitud_incompatible'
                : 'local_query_error',
            code: error.contains('PT409') ? 'PT409' : 'LOCAL',
          );
        }
        return out.trim();
      }

      Map<String, dynamic> parse(String v) => Map<String, dynamic>.from(
        jsonDecode(v.split('\n').where((s) => s.startsWith('{')).last) as Map,
      );
      expect(await sql('select current_database();'), 'alberdi_v2_lab');
      final regime = await sql('select regimen_id from stock_transicion;');
      Future<Map<String, dynamic>> seed() async {
        final s = parse(
          await sql(
            "select set_config('request.jwt.claim.sub','$actor',false);select lab_seed('113B LOCAL',2);",
          ),
        );
        await sql(
          "update pedidos set facturado=false,fecha_facturacion=null,numero_comprobante=null where id=${quote(s['order'])};update pedido_detalles set cantidad_facturada=null where id=${quote(s['detail'])};",
        );
        return s;
      }

      var loseResponse = true, emissions = 0;
      Future<dynamic> rpc(String name, Map<String, dynamic> p) async {
        final expression = switch (name) {
          'stock_estado_transicion' => 'stock_estado_transicion()',
          'consultar_boleta_interna' =>
            'consultar_boleta_interna(${quote(p['p_solicitud_id'])}::uuid)',
          'consultar_comprobante_pedido' =>
            'consultar_comprobante_pedido(${quote(p['p_pedido_id'])}::uuid)',
          'emitir_boleta_preventa' =>
            'emitir_boleta_preventa(${quote(p['p_solicitud_id'])}::uuid,${quote(p['p_pedido_id'])}::uuid,${quote(p['p_regimen_id'])}::uuid,${quote(jsonEncode(p['p_originales']))}::jsonb,${quote(jsonEncode(p['p_agregados']))}::jsonb)',
          _ => throw StateError('No legacy allowed'),
        };
        final result = parse(
          await sql(
            "begin;set local role authenticated;select set_config('request.jwt.claim.sub','$actor',true);select $expression;commit;",
          ),
        );
        if (name == 'emitir_boleta_preventa') {
          emissions++;
          if (loseResponse) {
            loseResponse = false;
            throw TimeoutException('LOCAL lost response after actual commit');
          }
        }
        return result;
      }

      Future<String> effects() => sql(
        "select jsonb_build_object('cobros',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from cobros_cliente x),'pagos',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from pedido_pagos x),'eventos',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from stock_eventos x),'movimientos',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from stock_movimientos x),'confirmaciones',(select coalesce(jsonb_agg(to_jsonb(x) order by solicitud_id),'[]') from finalizacion_pedido_solicitudes x),'creditos',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from movimientos_credito_cliente x),'stock',(select coalesce(jsonb_agg(to_jsonb(x) order by ubicacion_id,producto_id),'[]') from stock_actual x),'entregas_comisiones',(select jsonb_agg(jsonb_build_array(id,cantidad_entregada,cantidad_no_entregada,importe_comision,porcentaje_comision) order by id) from pedido_detalles))::text;",
      );
      final s = await seed();
      final order = s['order'] as String;
      final before = await effects();
      final dir = await Directory.systemTemp.createTemp('113b-integrated-');
      addTearDown(() => dir.delete(recursive: true));
      var db = await LocalOutbox.open(dir.path);
      InvoiceService service() => InvoiceService(
        InvoiceStore(db, 'local-isolated', actor),
        rpc,
        enabled: true,
        requireScope: () {},
      );
      final payload = await service().prepare(order, {
        'p_originales': [
          {'detalle_id': s['detail'], 'cantidad_facturada': 1},
        ],
        'p_agregados': [],
      });
      expect(payload['p_regimen_id'], regime);
      await expectLater(
        service().reconcile(order, sendIfAbsent: true),
        throwsA(isA<TimeoutException>()),
      );
      expect(await sql('select count(*) from comprobantes_internos;'), '1');
      db.close();
      db = await LocalOutbox.open(dir.path);
      addTearDown(db.close);
      final doc = (await service().reconcile(order))!;
      expect(doc.result['solicitud_id'], payload['p_solicitud_id']);
      expect(doc.snapshot['lineas'][0]['cantidad_documentada'], 1);
      expect(emissions, 2);
      expect(await sql('select count(*) from comprobantes_internos;'), '1');
      await expectLater(
        service().printConfirmed(
          order,
          (_) async => throw StateError('LOCAL printer'),
        ),
        throwsStateError,
      );
      await service().printConfirmed(order, (_) async => true);
      await service().printConfirmed(order, (_) async => true);
      expect(emissions, 2);
      expect(await effects(), before);
      final bad = await seed();
      final badOrder = bad['order'] as String;
      final beforeConflict = await effects();
      final saved = await service().prepare(badOrder, {
        'p_originales': [
          {'detalle_id': bad['detail'], 'cantidad_facturada': 999},
        ],
        'p_agregados': [],
      });
      await rpc('emitir_boleta_preventa', {
        ...saved,
        'p_originales': [
          {'detalle_id': bad['detail'], 'cantidad_facturada': 2},
        ],
      });
      await expectLater(
        service().reconcile(badOrder),
        throwsA(isA<PostgrestException>()),
      );
      expect(service().store.read(badOrder)!.state, 'review');
      expect(service().store.read(badOrder)!.result, isNull);
      expect(
        await sql(
          "select (captura->>'total')::numeric=200 from comprobantes_internos where pedido_id=${quote(badOrder)};",
        ),
        't',
      );
      expect(await sql('select count(*) from comprobantes_internos;'), '2');
      expect(await effects(), beforeConflict);
    },
    skip: container == null
        ? 'Requires explicitly isolated local PostgreSQL lab'
        : false,
  );
}
