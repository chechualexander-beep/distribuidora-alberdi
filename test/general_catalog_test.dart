import 'package:distribuidora_alberdi/core/app_config.dart';
import 'package:distribuidora_alberdi/core/whatsapp_link.dart';
import 'package:distribuidora_alberdi/features/catalog/new_general_catalog_page.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_config_test.dart' show testingConfig, fixtureKey;

void main() {
  final token = 'a' * 64;
  tearDown(
    () => activateAppConfig(AppConfig.resolve(productionKey: fixtureKey)),
  );

  test('general link uses #general= without slash on each environment site', () {
    activateAppConfig(AppConfig.resolve(productionKey: fixtureKey));
    expect(
      generalCatalogLink(token),
      'https://distribuidora-alberdi.pages.dev#general=$token',
    );
    activateAppConfig(testingConfig());
    expect(
      generalCatalogLink(token),
      'https://alberdi-catalogo-testing.pages.dev#general=$token',
    );
  });

  test('stored links are namespaced per project', () {
    activateAppConfig(testingConfig());
    expect(generalCatalogLinkKey('x'), contains('blcgugdeluzxvpwqkhjq'));
    activateAppConfig(AppConfig.resolve(productionKey: fixtureKey));
    expect(generalCatalogLinkKey('x'), contains('vmbncsqapqdyffscwfwo'));
  });

  test('seller WhatsApp accepts a plain national mobile number', () {
    for (final input in ['3794 123456', '03794 15 123456', '+54 9 3794 123456']) {
      expect(
        normalizeArgentineWhatsApp(input, nationalMobileConfirmed: true),
        '5493794123456',
        reason: input,
      );
    }
    expect(
      normalizeArgentineWhatsApp('123', nationalMobileConfirmed: true),
      isNull,
    );
  });
}
