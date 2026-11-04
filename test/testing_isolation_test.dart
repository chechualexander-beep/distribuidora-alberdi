import 'dart:convert';

import 'package:distribuidora_alberdi/core/app_config.dart';
import 'package:distribuidora_alberdi/core/environment_frame.dart';
import 'package:distribuidora_alberdi/core/environment_auth_storage.dart';
import 'package:distribuidora_alberdi/features/clients/client_catalog_page.dart';
import 'package:distribuidora_alberdi/features/orders/finalization_request.dart';
import 'package:distribuidora_alberdi/features/orders/pending_finalizations_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'helpers/outbox_fixture.dart' show memoryDatabase;
import 'app_config_test.dart' show testingConfig, fixtureKey, testingUrl;

void main() {
  test(
    'testing auth ignores external links and isolates PKCE and preferences',
    () async {
      SharedPreferences.setMockInitialValues({'verifier': 'commercial-value'});
      final production = AppConfig.resolve(productionKey: fixtureKey);
      final testing = testingConfig();
      final options = authOptionsFor(testing);
      expect(options.detectSessionInUri, isFalse);
      expect(authOptionsFor(production).detectSessionInUri, isTrue);
      expect(authOptionsFor(production).pkceAsyncStorage, isNull);
      expect(
        production.localPreferenceKey('templates:admin'),
        'templates:admin',
      );
      expect(
        testing.localPreferenceKey('templates:admin'),
        isNot('templates:admin'),
      );
      final storage = options.pkceAsyncStorage!;
      expect(await storage.getItem(key: 'verifier'), isNull);
      await storage.setItem(key: 'verifier', value: 'testing-value');
      expect(await storage.getItem(key: 'verifier'), 'testing-value');
      await storage.removeItem(key: 'verifier');
      expect(
        (await SharedPreferences.getInstance()).getString('verifier'),
        'commercial-value',
      );
    },
  );
  tearDown(
    () => activateAppConfig(AppConfig.resolve(productionKey: fixtureKey)),
  );

  testWidgets(
    'testing catalog is blocked without initializing any Supabase client',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'catalogo_url': 'https://distribuidora-alberdi.pages.dev',
        'catalogo_link_client':
            'https://distribuidora-alberdi.pages.dev/#token=fixture',
      });
      activateAppConfig(testingConfig());
      await tester.pumpWidget(
        const MaterialApp(home: ClientCatalogPage(cliente: {'id': 'client'})),
      );
      await tester.pumpAndSettle();
      expect(find.text('Catálogo deshabilitado'), findsOneWidget);
      expect(find.text('Ver catálogo'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('catalogo_url'),
        'https://distribuidora-alberdi.pages.dev',
      );
    },
  );

  testWidgets('production recovery screen cannot access V2 or storage', (
    tester,
  ) async {
    activateAppConfig(AppConfig.resolve(productionKey: fixtureKey));
    await tester.pumpWidget(
      const MaterialApp(home: PendingFinalizationsPage()),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Recuperación V2 disponible únicamente en TESTING.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('testing label remains above routes and dialogs at narrow width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        builder: (context, child) =>
            EnvironmentFrame(config: testingConfig(), child: child!),
        home: const Scaffold(body: Text('Inicio')),
      ),
    );
    const label =
        'TESTING — SOLO DATOS FICTICIOS\nNotificaciones y catálogo deshabilitados';
    expect(find.text(label), findsOneWidget);
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Segunda pantalla')),
      ),
    );
    await tester.pumpAndSettle();
    showDialog<void>(
      context: navigator.currentContext!,
      builder: (_) => const AlertDialog(content: Text('Confirmación')),
    );
    await tester.pumpAndSettle();
    expect(find.text(label), findsOneWidget);
    expect(find.text('Confirmación'), findsOneWidget);
    expect(
      tester.getBottomLeft(find.text(label)).dy,
      lessThan(tester.getTopLeft(find.byType(AlertDialog)).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('production has no testing label', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) => EnvironmentFrame(
          config: AppConfig.resolve(productionKey: fixtureKey),
          child: child!,
        ),
        home: const Scaffold(body: Text('Comercial')),
      ),
    );
    expect(find.textContaining('SOLO DATOS FICTICIOS'), findsNothing);
    expect(find.text('Comercial'), findsOneWidget);
  });

  test(
    'V2 rejects production configuration or a foreign client before HTTP',
    () async {
      var requests = 0;
      final client = SupabaseClient(
        'https://vmbncsqapqdyffscwfwo.supabase.co',
        fixtureKey,
        httpClient: MockClient((request) async {
          requests++;
          throw StateError('No request authorized');
        }),
      );
      try {
        for (final config in [
          testingConfig(),
          AppConfig.resolve(productionKey: fixtureKey),
        ]) {
          await expectLater(
            reconcileFinalization(
              client,
              {'p_solicitud_id': 'fixture'},
              store: FinalizationRequestStore(
                memoryDatabase(),
                '$testingUrl/rest/v1',
                'admin',
              ),
              retry: true,
              config: config,
            ),
            throwsStateError,
          );
        }
        expect(requests, 0);
      } finally {
        await client.dispose();
      }
    },
  );

  test(
    'ambiguous V2 failure never calls legacy and preserves the durable request',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = FinalizationRequestStore(
        memoryDatabase(),
        '$testingUrl/rest/v1',
        'admin',
      );
      final payload = await store.prepare('order', {
        'p_tipo_pago': 'sin_pago',
      }, physicalDate: DateTime.utc(2026, 1));
      final paths = <String>[];
      final client = SupabaseClient(
        testingUrl,
        fixtureKey,
        httpClient: MockClient((request) async {
          paths.add(request.url.path);
          if (request.url.path.endsWith('consultar_finalizacion_solicitud')) {
            return http.Response(
              jsonEncode({'estado': 'inexistente'}),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }
          expect(jsonDecode(request.body), payload);
          throw http.ClientException('Response lost after possible commit');
        }),
      );
      try {
        await expectLater(
          reconcileFinalization(
            client,
            payload,
            store: store,
            retry: true,
            config: testingConfig(),
          ),
          throwsA(isA<Exception>()),
        );
        expect(paths, [
          '/rest/v1/rpc/consultar_finalizacion_solicitud',
          '/rest/v1/rpc/finalizar_gestion_pedido_v2',
        ]);
        expect(store.read('order'), payload);
      } finally {
        await client.dispose();
      }
    },
  );

  test(
    'unrecognized reconciliation status cannot cause a finalization',
    () async {
      final store = FinalizationRequestStore(
        memoryDatabase(),
        '$testingUrl/rest/v1',
        'admin',
      );
      final payload = await store.prepare(
        'order',
        {},
        physicalDate: DateTime.utc(2026),
      );
      final paths = <String>[];
      final client = SupabaseClient(
        testingUrl,
        fixtureKey,
        httpClient: MockClient((request) async {
          paths.add(request.url.path);
          return http.Response(
            '{"estado":"desconocido"}',
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      try {
        await expectLater(
          reconcileFinalization(
            client,
            payload,
            store: store,
            retry: true,
            config: testingConfig(),
          ),
          throwsA(isA<LocalOutboxException>()),
        );
        expect(paths, ['/rest/v1/rpc/consultar_finalizacion_solicitud']);
      } finally {
        await client.dispose();
      }
    },
  );
}
