import 'dart:convert';

import 'production_config.dart';

enum AppEnvironment { production, testing }

/// Resolved once, before initializing any network client or external service.
class AppConfig {
  const AppConfig._(this.environment, this.supabaseUrl, this.supabaseKey);

  static const productionProject = 'vmbncsqapqdyffscwfwo';
  static const testingProject = 'blcgugdeluzxvpwqkhjq';
  final AppEnvironment environment;
  final String supabaseUrl;
  final String supabaseKey;

  bool get isTesting => environment == AppEnvironment.testing;
  bool get notificationsEnabled => !isTesting;
  // No testing catalog destination has been approved yet.
  bool get catalogEnabled => !isTesting;
  // 1.0.8: cierres, venta directa, cobros y devoluciones por el circuito V2
  // en ambos entornos. Stock V2 puede estar apagado (régimen OFF).
  bool get finalizationV2Enabled => true;
  bool get directSalesEnabled => true;
  static const directSalesTestingMessage =
      'Venta directa temporalmente fuera de operación en TESTING. Su integración con Stock V2 está pendiente.';
  bool blocksOrderOperation(String operation) =>
      !directSalesEnabled && operation == 'venta_directa';
  String get project => isTesting ? testingProject : productionProject;
  String get title =>
      isTesting ? 'Alberdi TESTING — datos ficticios' : 'Distribuidora Alberdi';

  bool usesV2For(String? operation) =>
      finalizationV2Enabled && !blocksOrderOperation(operation ?? '');

  String catalogPreferenceKey(String suffix) => 'catalogo:$project:$suffix';

  // Keep existing commercial templates; testing never reads their old keys.
  String localPreferenceKey(String legacyKey) =>
      isTesting ? 'testing:$project:$legacyKey' : legacyKey;

  factory AppConfig.fromCompileTime({bool testingEntrypoint = false}) =>
      AppConfig.resolve(
        environment: const String.fromEnvironment('APP_ENV'),
        legacyUseTesting: const String.fromEnvironment('USE_TESTING'),
        testingUrl: const String.fromEnvironment('SUPABASE_TESTING_URL'),
        testingKey: const String.fromEnvironment('SUPABASE_TESTING_KEY'),
        testingEntrypoint: testingEntrypoint,
      );

  factory AppConfig.resolve({
    String environment = '',
    String legacyUseTesting = '',
    String testingUrl = '',
    String testingKey = '',
    bool testingEntrypoint = false,
    String productionKey = productionSupabaseKey,
  }) {
    if (!{'', 'testing', 'production'}.contains(environment) ||
        !{'', 'true', 'false'}.contains(legacyUseTesting)) {
      throw const FormatException('Selección de entorno inválida.');
    }
    final explicitTesting = environment == 'testing';
    final explicitProduction = environment == 'production';
    if ((explicitTesting && legacyUseTesting == 'false') ||
        (explicitProduction && legacyUseTesting == 'true') ||
        (testingEntrypoint &&
            (explicitProduction || legacyUseTesting == 'false'))) {
      throw const FormatException('Las opciones de entorno se contradicen.');
    }
    final testing =
        testingEntrypoint || explicitTesting || legacyUseTesting == 'true';
    if (!testing && (testingUrl.isNotEmpty || testingKey.isNotEmpty)) {
      throw const FormatException(
        'Hay configuración TESTING sin seleccionar TESTING.',
      );
    }
    final project = testing ? testingProject : productionProject;
    final expectedUrl = 'https://$project.supabase.co';
    final suppliedUrl = testing ? testingUrl : expectedUrl;
    final uri = Uri.tryParse(suppliedUrl);
    if (uri == null ||
        (suppliedUrl != expectedUrl && suppliedUrl != '$expectedUrl/') ||
        uri.scheme != 'https' ||
        uri.host != '$project.supabase.co' ||
        uri.hasPort ||
        uri.userInfo.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException('URL Supabase ausente o no autorizada.');
    }
    final key = testing ? testingKey : productionKey;
    _validatePublicKey(key, project);
    return AppConfig._(
      testing ? AppEnvironment.testing : AppEnvironment.production,
      expectedUrl,
      key,
    );
  }

  static void _validatePublicKey(String key, String project) {
    // Opaque publishable keys cannot be bound to a project offline. The URL
    // remains pinned; Supabase validates the key on that project's server.
    if (RegExp(r'^sb_publishable_[A-Za-z0-9_-]{16,}$').hasMatch(key)) return;
    try {
      final parts = key.split('.');
      if (parts.length == 3 && parts.every((p) => p.isNotEmpty)) {
        final claims = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
        );
        // This checks public-key claims, not the JWT signature.
        if (claims is Map &&
            claims['role'] == 'anon' &&
            claims['ref'] == project) {
          return;
        }
      }
    } catch (_) {
      // Never include the key or decoded claims in an error.
    }
    throw const FormatException('Se requiere la clave pública del proyecto.');
  }

  void requireV2Client(String restUrl) {
    final uri = Uri.tryParse(restUrl);
    if (!finalizationV2Enabled ||
        uri == null ||
        uri.scheme != 'https' ||
        uri.host != '$project.supabase.co' ||
        uri.hasPort ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        !{'/rest/v1', '/rest/v1/'}.contains(uri.path)) {
      throw StateError('El cliente Supabase no corresponde al entorno activo.');
    }
  }
}

AppConfig? _activeConfig;
AppConfig get appConfig => _activeConfig ?? AppConfig.fromCompileTime();

void activateAppConfig(AppConfig config) => _activeConfig = config;
