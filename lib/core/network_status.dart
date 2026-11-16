import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'offline_cache.dart';

/// true mientras la última consulta falló por la conexión (sin señal, señal débil o caída).
final connectionProblem = ValueNotifier<bool>(false);

/// Marca de zona: dentro de [withoutCacheFallback] las consultas fallan si no hay red
/// (no devuelven lo guardado). La usa "Preparar para trabajar sin señal".
const _noFallback = #alberdiSinRespaldoLocal;

Future<T> withoutCacheFallback<T>(Future<T> Function() action) =>
    runZoned(action, zoneValues: {_noFallback: true});

/// Cliente HTTP de Supabase: tiempo máximo para las CONSULTAS (GET) y copia local.
///
/// - Con poca señal una pantalla podía quedarse cargando minutos: ahora, si no responde a
///   tiempo, falla y la pantalla ofrece "Reintentar".
/// - Cada consulta que funciona se guarda; si después no hay conexión, se devuelve lo guardado
///   y la franja avisa de cuándo son los datos. Con copia guardada se espera menos.
/// - Las operaciones que guardan datos (POST, PATCH, DELETE) no se cortan ni se copian.
class ResilientHttpClient extends http.BaseClient {
  ResilientHttpClient(
    this._inner, {
    this.readTimeout = const Duration(seconds: 15),
    this.cachedTimeout = const Duration(seconds: 8),
    this.offlineTimeout = const Duration(seconds: 3),
    OfflineCache? Function()? cache,
  }) : _cache = cache ?? (() => offlineCache);

  final http.Client _inner;
  final Duration readTimeout, cachedTimeout, offlineTimeout;
  final OfflineCache? Function() _cache;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final isRead = request.method == 'GET' || request.method == 'HEAD';
    final cache = isCacheableRequest(request.method, request.url) ? _cache() : null;
    final key = cache == null ? null : cacheKey(request.url, request.headers);
    final saved = key == null ? null : await cache!.read(key);
    final fallback = saved != null && Zone.current[_noFallback] != true;
    final timeout = !fallback
        ? readTimeout
        : (connectionProblem.value ? offlineTimeout : cachedTimeout);
    try {
      final pending = _inner.send(request);
      var response = await (isRead ? pending.timeout(timeout) : pending);
      if (cache != null && response.statusCode == 200) {
        final body = await response.stream.bytesToString().timeout(timeout);
        final headers = {
          for (final h in ['content-type', 'content-range'])
            if (response.headers[h] != null) h: response.headers[h]!,
        };
        await cache.write(key!, CachedResponse(200, headers, body, DateTime.now()));
        response = _replay(request, 200, headers, body);
      }
      connectionProblem.value = false;
      showingCachedSince.value = null;
      return response;
    } on Exception catch (error) {
      final network =
          error is TimeoutException || error is SocketException || error is http.ClientException;
      if (!network) rethrow;
      connectionProblem.value = true;
      if (fallback) {
        final copy = saved!;
        showingCachedSince.value = copy.savedAt;
        return _replay(request, copy.status, copy.headers, copy.body);
      }
      rethrow;
    }
  }

  http.StreamedResponse _replay(
    http.BaseRequest request,
    int status,
    Map<String, String> headers,
    String body,
  ) {
    final bytes = utf8.encode(body);
    return http.StreamedResponse(
      Stream.value(bytes),
      status,
      contentLength: bytes.length,
      headers: headers,
      request: request,
    );
  }

  @override
  void close() => _inner.close();
}

/// Franja inferior "Sin conexión" (aparece sola y se va con la próxima consulta que funcione).
///
/// La estructura es SIEMPRE la misma (columna con la app arriba y la franja opcional abajo):
/// si cambiara al aparecer la franja, se perderían las pantallas abiertas.
class ConnectionBanner extends StatelessWidget {
  const ConnectionBanner({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: connectionProblem,
    child: child,
    builder: (context, offline, app) => Column(
      // stretch: la app ocupa TODO el ancho (si no, la pantalla de bloqueo queda en ancho 0).
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeBottom: offline,
            child: app!,
          ),
        ),
        if (offline)
          Material(
            color: const Color(0xFFC05A00),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  children: const [
                    Icon(Icons.signal_wifi_bad, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Expanded(child: _BannerText()),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _BannerText extends StatelessWidget {
  const _BannerText();
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<DateTime?>(
    valueListenable: showingCachedSince,
    builder: (context, since, _) => Text(
      since == null
          ? 'Sin conexión o señal débil. Lo que no cargó se puede reintentar.'
          : 'Sin conexión: mostrando datos guardados ${describeSavedAt(since)}.',
      style: const TextStyle(color: Colors.white, fontSize: 13),
    ),
  );
}

/// "hoy 08:15", "ayer 19:02" o "14/11 08:15".
String describeSavedAt(DateTime when, {DateTime? now}) {
  final t = when.toLocal();
  final n = (now ?? DateTime.now()).toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  final hour = '${two(t.hour)}:${two(t.minute)}';
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(t.year, t.month, t.day);
  if (day == today) return 'hoy $hour';
  if (day == today.subtract(const Duration(days: 1))) return 'ayer $hour';
  return 'el ${two(t.day)}/${two(t.month)} $hour';
}

/// Ahorro de datos: no se descargan las fotos de productos (se ven solo si se tocan).
final dataSaver = ValueNotifier<bool>(false);
const _dataSaverKey = 'ahorro_de_datos';

Future<void> loadDataSaver() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    dataSaver.value = prefs.getBool(_dataSaverKey) ?? false;
  } catch (_) {
    dataSaver.value = false;
  }
}

Future<void> setDataSaver(bool value) async {
  dataSaver.value = value;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_dataSaverKey, value);
  } catch (_) {
    /* Queda activo hasta cerrar la app. */
  }
}

/// Botón para la barra superior: activa o desactiva el ahorro de datos.
class DataSaverButton extends StatelessWidget {
  const DataSaverButton({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: dataSaver,
    builder: (context, on, _) => IconButton(
      tooltip: on
          ? 'Ahorro de datos activado (sin fotos)'
          : 'Activar ahorro de datos (sin fotos)',
      icon: Icon(on ? Icons.data_saver_on : Icons.data_saver_off),
      onPressed: () async {
        await setDataSaver(!on);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              !on
                  ? 'Ahorro de datos activado: las fotos se ven solo si las tocás.'
                  : 'Ahorro de datos desactivado.',
            ),
          ),
        );
      },
    ),
  );
}
