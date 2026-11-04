import 'dart:convert';
import 'package:distribuidora_alberdi/core/app_config.dart';
import 'package:distribuidora_alberdi/features/orders/finalization_request.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const fixtureUrl = 'https://blcgugdeluzxvpwqkhjq.supabase.co';
const fixtureScope = '$fixtureUrl/rest/v1';
AppConfig fixtureConfig() => AppConfig.resolve(
  environment: 'testing',
  testingUrl: fixtureUrl,
  testingKey: 'sb_publishable_local_fixture_123456789',
);
LocalOutbox memoryDatabase({void Function(String)? fault}) {
  final db = LocalOutbox.memory(testingFault: fault);
  addTearDown(db.close);
  return db;
}

FinalizationRequestStore memoryStore() =>
    FinalizationRequestStore(memoryDatabase(), fixtureScope, 'admin');
Map<String, dynamic> operational({
  num amount = 200,
  num quantity = 2,
  List<Map<String, dynamic>> additions = const [],
}) => {
  'p_estado': 'pendiente',
  'p_originales': [
    {'detalle_id': 'fake-detail', 'cantidad_entregada': quantity},
  ],
  'p_agregados': additions,
  'p_tipo_pago': amount == 0 ? 'sin_pago' : 'completo',
  'p_importe_pago': amount,
  'p_medio_pago': amount == 0 ? null : 'Efectivo',
  'p_motivo_no_entrega': quantity < 2 ? 'Ensayo ficticio' : null,
};
Map<String, dynamic> receipt(
  Map<String, dynamic> payload, {
  String outcome = 'entregado',
}) => {
  'pedido_id': payload['p_pedido_id'],
  'solicitud_id': payload['p_solicitud_id'],
  'resultado_entrega': outcome,
  'movimientos_stock': 0,
};
http.Response jsonResponse(
  http.Request request,
  Object? value, [
  int status = 200,
]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json'},
  request: request,
);
SupabaseClient mockClient(
  Future<http.Response> Function(http.Request) handler, {
  bool autoRefreshToken = true,
}) {
  final client = SupabaseClient(
    fixtureUrl,
    'fixture-public-key',
    authOptions: AuthClientOptions(autoRefreshToken: autoRefreshToken),
    httpClient: MockClient(handler),
  );
  addTearDown(client.dispose);
  return client;
}

Future<Map<String, dynamic>> reconcile(
  SupabaseClient client,
  FinalizationRequestStore store,
  Map<String, dynamic> payload, {
  bool retry = true,
}) => reconcileFinalization(
  client,
  payload,
  store: store,
  retry: retry,
  config: fixtureConfig(),
);
