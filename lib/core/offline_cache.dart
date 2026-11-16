import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Copia local de las consultas de lectura (clientes, productos, saldos, ...).
///
/// Cada consulta que funciona se guarda en el equipo. Si después no hay señal, la misma
/// consulta devuelve lo guardado, así la pantalla se ve igual (con la franja que avisa de
/// cuándo son los datos). Es por usuario: la clave incluye quién consulta, y todo se borra
/// al cerrar sesión.
class OfflineCache {
  OfflineCache(this.directory);
  final Directory directory;

  static Future<OfflineCache> open(String path) async {
    final dir = Directory(path);
    await dir.create(recursive: true);
    return OfflineCache(dir);
  }

  File _file(String key) => File(
    p.join(directory.path, '${sha256.convert(utf8.encode(key))}.json'),
  );

  Future<CachedResponse?> read(String key) async {
    try {
      final file = _file(key);
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if (json['key'] != key) return null;
      return CachedResponse(
        json['status'] as int,
        Map<String, String>.from(json['headers'] as Map),
        json['body'] as String,
        DateTime.parse(json['saved_at'] as String),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String key, CachedResponse response) async {
    try {
      final file = _file(key);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(
        jsonEncode({
          'key': key,
          'status': response.status,
          'headers': response.headers,
          'body': response.body,
          'saved_at': response.savedAt.toUtc().toIso8601String(),
        }),
        flush: true,
      );
      await tmp.rename(file.path);
    } catch (_) {
      /* Sin copia local esta vez: la app sigue igual. */
    }
  }

  Future<void> clear() async {
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
      await directory.create(recursive: true);
    } catch (_) {
      /* Se intentará de nuevo en el próximo cierre de sesión. */
    }
  }
}

class CachedResponse {
  const CachedResponse(this.status, this.headers, this.body, this.savedAt);
  final int status;
  final Map<String, String> headers;
  final String body;
  final DateTime savedAt;
}

/// Copia activa (se abre al iniciar la app). Null en pruebas o si no se pudo abrir.
OfflineCache? offlineCache;

/// Fecha de los datos guardados que se están mostrando por falta de conexión (o null).
final showingCachedSince = ValueNotifier<DateTime?>(null);

/// Quién consulta, leído del token (para que la copia de un usuario nunca se use con otro).
String requestUser(Map<String, String> headers) {
  final auth = headers['authorization'] ?? headers['Authorization'] ?? '';
  final parts = auth.replaceFirst(RegExp('^Bearer ', caseSensitive: false), '').split('.');
  if (parts.length != 3) return 'anon';
  try {
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    ) as Map<String, dynamic>;
    return payload['sub']?.toString() ?? 'anon';
  } catch (_) {
    return 'anon';
  }
}

/// Clave de una consulta: usuario + formato pedido + dirección con parámetros ordenados.
String cacheKey(Uri url, Map<String, String> headers) {
  String header(String name) =>
      headers[name] ?? headers[name.toLowerCase()] ?? headers[_title(name)] ?? '';
  final params = url.queryParametersAll.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  final query = params
      .expand((e) => (List.of(e.value)..sort()).map((v) => '${e.key}=$v'))
      .join('&');
  return [
    requestUser(headers),
    header('accept'),
    header('prefer'),
    '${url.path}?$query',
  ].join('|');
}

String _title(String name) =>
    name.split('-').map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join('-');

/// Solo lecturas de la base (PostgREST). Nunca autenticación ni archivos.
bool isCacheableRequest(String method, Uri url) =>
    method == 'GET' && url.path.contains('/rest/v1/');
