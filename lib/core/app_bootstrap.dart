import 'app_config.dart';

/// Callbacks allow verification of startup order without real connections.
Future<AppConfig> prepareApplication({
  required AppConfig Function() resolveConfig,
  required Future<void> Function() initializeFirebase,
  required Future<void> Function(AppConfig) initializeSupabase,
}) async {
  final config = resolveConfig();
  if (config.notificationsEnabled) await initializeFirebase();
  await initializeSupabase(config);
  return config;
}
