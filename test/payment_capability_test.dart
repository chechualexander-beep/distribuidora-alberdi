import 'dart:convert';
import 'dart:io';
import 'package:distribuidora_alberdi/core/payment_outbox.dart';
import 'package:distribuidora_alberdi/features/balances/balance_repository.dart';
import 'package:distribuidora_alberdi/features/balances/client_payment_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'helpers/balance_fixture.dart';
import 'helpers/outbox_fixture.dart';

class CapabilityBalanceRepository extends FakeBalanceRepository {
  CapabilityBalanceRepository(this.delegate);
  final BalanceRepository delegate;
  @override
  Future<bool> paymentsAvailable() async {
    final available = await delegate.paymentsAvailable();
    capabilityIssue = delegate.capabilityIssue;
    return available;
  }
}

void main() {
  late SupabaseClient client;
  late BalanceRepository repository;
  late Object? response;
  late int status, reads;
  late String role;
  late bool changeActor, connectionError;

  Future<void> session(String actor) => client.auth.setInitialSession(
    jsonEncode({
      'access_token': 'e30.eyJleHAiOjQxMDI0NDQ4MDB9.fixture',
      'refresh_token': 'fixture',
      'token_type': 'bearer',
      'expires_in': 3600,
      'user': {
        'id': actor,
        'aud': 'authenticated',
        'role': 'authenticated',
        'email': 'fixture@example.invalid',
        'app_metadata': {},
        'user_metadata': {},
        'created_at': '2026-01-01T00:00:00Z',
      },
    }),
  );

  Map<String, dynamic> compatible() => {
    'capacidad': 'cobros_contextuales',
    'version': 1,
    'disponible': true,
    'actor_id': 'admin',
    'rpc': 'registrar_pago_cliente_contextual',
  };

  setUp(() async {
    response = compatible();
    status = 200;
    reads = 0;
    role = 'administrador';
    changeActor = false;
    connectionError = false;
    client = mockClient((request) async {
      expect(request.method, 'GET');
      if (request.url.path == '/rest/v1/usuarios') {
        return jsonResponse(request, {'rol': role, 'activo': true});
      }
      expect(
        request.url.path,
        '/rest/v1/rpc/obtener_capacidad_cobros_contextuales',
      );
      expect(request.url.queryParameters.keys, isNot(contains('p_cliente_id')));
      expect(request.url.queryParameters.keys, isNot(contains('p_importe')));
      expect(request.body, isEmpty);
      expect(request.headers['apikey'], 'fixture-public-key');
      expect(
        request.headers['Authorization'] ?? request.headers['authorization'],
        'Bearer e30.eyJleHAiOjQxMDI0NDQ4MDB9.fixture',
      );
      reads++;
      if (connectionError) throw const SocketException('Fixture offline');
      if (changeActor) await session('other');
      return jsonResponse(request, response, status);
    }, autoRefreshToken: false);
    await session('admin');
    repository = BalanceRepository(client, config: fixtureConfig());
  });

  test(
    'capacidad usa GET autenticado del SDK sin llamar al cobro ni OpenAPI',
    () async {
      expect(await repository.paymentsAvailable(), isTrue);
      expect(reads, 1);
      expect(repository.capabilityIssue, isNull);
    },
  );

  test('no administrador y sin autenticación quedan bloqueados', () async {
    role = 'preventista';
    expect(await repository.paymentsAvailable(), isFalse);
    expect(reads, 0);
    final anonymous = mockClient(
      (_) async => fail('Sesión ausente no debe consultar'),
      autoRefreshToken: false,
    );
    expect(
      await BalanceRepository(
        anonymous,
        config: fixtureConfig(),
      ).paymentsAvailable(),
      isFalse,
    );
  });

  test(
    'RPC inexistente y permiso insuficiente quedan bloqueados con mensaje',
    () async {
      response = {'code': 'PGRST202', 'message': 'Fixture missing'};
      status = 404;
      expect(await repository.paymentsAvailable(), isFalse);
      expect(repository.capabilityIssue, contains('todavía no está instalada'));
      response = {'code': 'PT403', 'message': 'Fixture forbidden'};
      status = 403;
      expect(await repository.paymentsAvailable(), isFalse);
      expect(repository.capabilityIssue, contains('administración activa'));
    },
  );

  test(
    'error de conexión y respuesta sin contrato quedan bloqueados',
    () async {
      connectionError = true;
      expect(await repository.paymentsAvailable(), isFalse);
      connectionError = false;
      for (final invalid in <Object?>[null, [], {}, 'incierto']) {
        response = invalid;
        expect(await repository.paymentsAvailable(), isFalse);
      }
    },
  );

  test('versión, capacidad, disponibilidad y actor deben coincidir', () async {
    for (final change in [
      {'version': 2},
      {'actor_id': 'other'},
      {'disponible': false},
      {'rpc': 'registrar_pago_cliente'},
      {'capacidad': 'otra'},
    ]) {
      response = {...compatible(), ...change};
      expect(await repository.paymentsAvailable(), isFalse);
    }
  });

  test('cambio de actor durante la consulta conserva bloqueo', () async {
    changeActor = true;
    expect(await repository.paymentsAvailable(), isFalse);
    expect(repository.capabilityIssue, contains('sesión cambió'));
  });

  for (final valid in [true, false]) {
    testWidgets('formulario habilitado solo con contrato compatible $valid', (
      tester,
    ) async {
      if (!valid) response = {...compatible(), 'version': 2};
      final directory = Directory.systemTemp.createTempSync(
        'alberdi-capability-test-',
      );
      final store = PaymentOutbox.open(directory.path);
      addTearDown(() {
        store.close();
        directory.deleteSync(recursive: true);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ClientPaymentDialog(
              repository: CapabilityBalanceRepository(repository),
              clientId: 'client',
              clientName: 'Cliente QA',
              store: store,
              onConfirmed: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField).first).enabled,
        valid,
      );
      expect(
        tester
                .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Confirmar pago'),
                )
                .onPressed !=
            null,
        valid,
      );
      if (!valid) {
        expect(find.textContaining('versión compatible'), findsOneWidget);
      }
      expect(reads, 1);
    });
  }
}
