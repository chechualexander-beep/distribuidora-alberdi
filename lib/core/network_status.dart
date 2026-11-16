import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// true mientras la última consulta falló por la conexión (sin señal, señal débil o caída).
final connectionProblem = ValueNotifier<bool>(false);

/// Cliente HTTP de Supabase con tiempo máximo para las CONSULTAS (GET).
///
/// Con poca señal una pantalla podía quedarse cargando minutos: ahora, si no responde en
/// [readTimeout], falla y la pantalla ofrece "Reintentar". Las operaciones que guardan datos
/// (POST, PATCH, DELETE) no se cortan desde acá, para no dejar dudas sobre si se guardaron:
/// esas tienen su propio manejo (reintento sin duplicar).
class ResilientHttpClient extends http.BaseClient {
  ResilientHttpClient(
    this._inner, {
    this.readTimeout = const Duration(seconds: 15),
  });

  final http.Client _inner;
  final Duration readTimeout;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final isRead = request.method == 'GET' || request.method == 'HEAD';
    try {
      final pending = _inner.send(request);
      final response = await (isRead ? pending.timeout(readTimeout) : pending);
      connectionProblem.value = false;
      return response;
    } on TimeoutException {
      connectionProblem.value = true;
      rethrow;
    } on SocketException {
      connectionProblem.value = true;
      rethrow;
    } on http.ClientException {
      connectionProblem.value = true;
      rethrow;
    }
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
                    Expanded(
                      child: Text(
                        'Sin conexión o señal débil. Lo que no cargó se puede reintentar.',
                        style: TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );
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
