import 'dart:async';

import 'package:distribuidora_alberdi/core/network_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final slow = MockClient((request) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return http.Response('[]', 200);
  });

  test('una consulta lenta se corta y avisa "sin conexión"; la siguiente que anda lo quita', () async {
    connectionProblem.value = false;
    final client = ResilientHttpClient(slow, readTimeout: const Duration(milliseconds: 50));
    await expectLater(client.get(Uri.parse('https://x.test/rest/v1/clientes')), throwsA(isA<TimeoutException>()));
    expect(connectionProblem.value, isTrue);
    final ok = ResilientHttpClient(slow, readTimeout: const Duration(seconds: 2));
    expect((await ok.get(Uri.parse('https://x.test/rest/v1/clientes'))).statusCode, 200);
    expect(connectionProblem.value, isFalse);
  });

  test('las operaciones que guardan datos no se cortan (evita dudas de si se guardó)', () async {
    final client = ResilientHttpClient(slow, readTimeout: const Duration(milliseconds: 50));
    final response = await client.post(Uri.parse('https://x.test/rest/v1/rpc/crear_pedido_interno'));
    expect(response.statusCode, 200);
  });

  test('sin red: avisa y deja pasar el error a la pantalla', () async {
    connectionProblem.value = false;
    final client = ResilientHttpClient(
      MockClient((_) async => throw http.ClientException('sin red')),
    );
    await expectLater(client.get(Uri.parse('https://x.test/a')), throwsA(isA<http.ClientException>()));
    expect(connectionProblem.value, isTrue);
    connectionProblem.value = false;
  });

  test('ahorro de datos se recuerda', () async {
    SharedPreferences.setMockInitialValues({});
    await loadDataSaver();
    expect(dataSaver.value, isFalse);
    await setDataSaver(true);
    dataSaver.value = false;
    await loadDataSaver();
    expect(dataSaver.value, isTrue);
    await setDataSaver(false);
  });

  testWidgets('la franja aparece y desaparece sin romper la pantalla', (tester) async {
    connectionProblem.value = false;
    await tester.pumpWidget(
      const MaterialApp(home: ConnectionBanner(child: Scaffold(body: Text('pantalla')))),
    );
    expect(find.textContaining('Sin conexión'), findsNothing);
    connectionProblem.value = true;
    await tester.pump();
    expect(find.textContaining('Sin conexión'), findsOneWidget);
    expect(find.text('pantalla'), findsOneWidget);
    connectionProblem.value = false;
    await tester.pump();
    expect(find.textContaining('Sin conexión'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
