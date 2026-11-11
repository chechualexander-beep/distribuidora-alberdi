import 'dart:convert';

import 'package:distribuidora_alberdi/core/app_bootstrap.dart';
import 'package:distribuidora_alberdi/core/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

const testingUrl = 'https://blcgugdeluzxvpwqkhjq.supabase.co';
const fixtureKey = 'sb_publishable_local_fixture_123456789';

AppConfig testingConfig() => AppConfig.resolve(
  testingEntrypoint: true,
  testingUrl: testingUrl,
  testingKey: fixtureKey,
);

String fixtureJwt(String role, String project) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'HS256'})}.${part({'role': role, 'ref': project})}.fixture';
}

void main() {
  test('production preserves its own URL and key and routes through V2', () {
    final config = AppConfig.resolve(productionKey: fixtureKey);
    expect(config.environment, AppEnvironment.production);
    expect(config.supabaseUrl, 'https://vmbncsqapqdyffscwfwo.supabase.co');
    expect(config.supabaseKey, fixtureKey);
    expect(config.notificationsEnabled, isTrue);
    expect(config.catalogEnabled, isTrue);
    expect(config.usesV2For('pedido'), isTrue);
    expect(config.usesV2For('venta_directa'), isTrue);
  });

  test('dedicated testing entrypoint needs no production configuration', () {
    final config = AppConfig.resolve(
      testingEntrypoint: true,
      testingUrl: testingUrl,
      testingKey: fixtureKey,
      productionKey: '',
    );
    expect(config.isTesting, isTrue);
    expect(config.notificationsEnabled, isFalse);
    expect(config.catalogEnabled, isFalse);
    expect(config.usesV2For('pedido'), isTrue);
    expect(config.usesV2For('venta_directa'), isTrue);
  });

  test('explicit and historical testing defines select the same project', () {
    for (final legacy in ['', 'true']) {
      final config = AppConfig.resolve(
        environment: 'testing',
        legacyUseTesting: legacy,
        testingUrl: testingUrl,
        testingKey: fixtureKey,
      );
      expect(config.project, AppConfig.testingProject);
    }
    expect(
      AppConfig.resolve(
        legacyUseTesting: 'true',
        testingUrl: testingUrl,
        testingKey: fixtureKey,
      ).isTesting,
      isTrue,
    );
  });

  for (final invalidUrl in [
    '',
    'https://vmbncsqapqdyffscwfwo.supabase.co',
    'https://another-project.supabase.co',
    'http://blcgugdeluzxvpwqkhjq.supabase.co',
    '$testingUrl.evil.example',
    'https://user@blcgugdeluzxvpwqkhjq.supabase.co',
    '$testingUrl:443',
    '$testingUrl/rest/v1',
    '$testingUrl?redirect=production',
    '$testingUrl#fragment',
  ]) {
    test('testing rejects unauthorized URL: $invalidUrl', () {
      expect(
        () => AppConfig.resolve(
          testingEntrypoint: true,
          testingUrl: invalidUrl,
          testingKey: fixtureKey,
        ),
        throwsFormatException,
      );
    });
  }

  for (final key in [
    '',
    'sb_secret_fixture_never_allowed',
    'invalid',
    fixtureJwt('service_role', AppConfig.testingProject),
    fixtureJwt('anon', AppConfig.productionProject),
  ]) {
    test(
      'testing rejects missing, privileged or foreign key without disclosure',
      () {
        try {
          AppConfig.resolve(
            testingEntrypoint: true,
            testingUrl: testingUrl,
            testingKey: key,
          );
          fail('Invalid key accepted');
        } on FormatException catch (error) {
          if (key.isNotEmpty) expect(error.toString(), isNot(contains(key)));
        }
      },
    );
  }

  test('legacy anon JWT must name the selected project', () {
    expect(
      AppConfig.resolve(
        testingEntrypoint: true,
        testingUrl: testingUrl,
        testingKey: fixtureJwt('anon', AppConfig.testingProject),
      ).isTesting,
      isTrue,
    );
  });

  test('missing, contradictory and misspelled selectors fail closed', () {
    final attempts = <AppConfig Function()>[
      () => AppConfig.resolve(testingEntrypoint: true),
      () => AppConfig.resolve(environment: 'TESTING'),
      () => AppConfig.resolve(legacyUseTesting: 'tru'),
      () => AppConfig.resolve(testingUrl: testingUrl),
      () => AppConfig.resolve(testingKey: fixtureKey),
      () => AppConfig.resolve(
        environment: 'production',
        legacyUseTesting: 'true',
      ),
      () =>
          AppConfig.resolve(environment: 'testing', legacyUseTesting: 'false'),
      () =>
          AppConfig.resolve(testingEntrypoint: true, environment: 'production'),
      () =>
          AppConfig.resolve(testingEntrypoint: true, legacyUseTesting: 'false'),
    ];
    for (final attempt in attempts) {
      expect(attempt, throwsFormatException);
    }
  });

  test(
    'invalid configuration initializes neither Firebase nor Supabase',
    () async {
      final calls = <String>[];
      await expectLater(
        prepareApplication(
          resolveConfig: () => AppConfig.resolve(testingEntrypoint: true),
          initializeFirebase: () async => calls.add('firebase'),
          initializeSupabase: (_) async => calls.add('supabase'),
        ),
        throwsFormatException,
      );
      expect(calls, isEmpty);
    },
  );

  test(
    'testing startup skips Firebase and passes only pinned Supabase config',
    () async {
      final calls = <String>[];
      await prepareApplication(
        resolveConfig: testingConfig,
        initializeFirebase: () async => calls.add('firebase'),
        initializeSupabase: (config) async {
          expect(config.supabaseUrl, testingUrl);
          calls.add('supabase');
        },
      );
      expect(calls, ['supabase']);
    },
  );

  test('production startup retains service order', () async {
    final calls = <String>[];
    await prepareApplication(
      resolveConfig: () => AppConfig.resolve(productionKey: fixtureKey),
      initializeFirebase: () async => calls.add('firebase'),
      initializeSupabase: (_) async => calls.add('supabase'),
    );
    expect(calls, ['firebase', 'supabase']);
  });

  test(
    'catalog preference names are disjoint and ignore unscoped legacy keys',
    () {
      final production = AppConfig.resolve(productionKey: fixtureKey);
      final testing = testingConfig();
      for (final suffix in ['url', 'link:client', 'hash:client']) {
        expect(
          production.catalogPreferenceKey(suffix),
          isNot(testing.catalogPreferenceKey(suffix)),
        );
        expect(
          production.catalogPreferenceKey(suffix),
          contains(AppConfig.productionProject),
        );
        expect(
          testing.catalogPreferenceKey(suffix),
          contains(AppConfig.testingProject),
        );
      }
    },
  );
}
