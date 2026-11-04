import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';

FlutterAuthClientOptions authOptionsFor(AppConfig config) => config.isTesting
    ? FlutterAuthClientOptions(
        // The current test flow uses password login. Ignore external auth links.
        detectSessionInUri: false,
        pkceAsyncStorage: EnvironmentPkceStorage(config),
      )
    : const FlutterAuthClientOptions();

/// The SDK scopes sessions by project, but its default PKCE storage is shared.
class EnvironmentPkceStorage extends GotrueAsyncStorage {
  EnvironmentPkceStorage(this.config);

  final AppConfig config;
  String _key(String key) => config.localPreferenceKey(key);

  @override
  Future<String?> getItem({required String key}) async =>
      (await SharedPreferences.getInstance()).getString(_key(key));

  @override
  Future<void> setItem({required String key, required String value}) async {
    if (!await (await SharedPreferences.getInstance()).setString(
      _key(key),
      value,
    )) {
      throw StateError('No se pudo guardar la configuración de autenticación.');
    }
  }

  @override
  Future<void> removeItem({required String key}) async {
    if (!await (await SharedPreferences.getInstance()).remove(_key(key))) {
      throw StateError('No se pudo cerrar la configuración de autenticación.');
    }
  }
}
