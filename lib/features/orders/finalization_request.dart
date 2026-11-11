import 'dart:convert';
import 'dart:io';

import '../../core/app_config.dart';
import '../../core/local_outbox.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_android/shared_preferences_android.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

export '../../core/local_outbox.dart' show LocalOutbox, LocalOutboxException;

class FinalizationRequestStore {
  FinalizationRequestStore(this.database, this.projectUrl, this.actorId);
  final LocalOutbox database;
  final String projectUrl, actorId;
  OutboxKey key(String orderId) => OutboxKey(projectUrl, actorId, orderId);

  Map<String, dynamic>? read(String orderId) =>
      database.read(key(orderId))?.payload;
  List<String> get pendingOrderIds => database.pending(projectUrl, actorId);

  static const allowedInput = {
    'p_estado',
    'p_originales',
    'p_agregados',
    'p_tipo_pago',
    'p_motivo_no_entrega',
    'p_importe_pago',
    'p_medio_pago',
  };

  Future<Map<String, dynamic>> prepare(
    String orderId,
    Map<String, dynamic> input, {
    DateTime? physicalDate,
    Future<DateTime> Function()? serverClock,
    Future<Map<String, dynamic>> Function(String requestId)? serverContext,
  }) async {
    // Snapshot operational input before any await. Existing rows always win.
    if (read(orderId) != null) return read(orderId)!;
    if (input.keys.any((name) => !allowedInput.contains(name))) {
      throw ArgumentError('La solicitud contiene campos no operativos');
    }
    final frozen = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(input)) as Map,
    );
    return database.prepare(key(orderId), (id) async {
      if (serverContext != null) {
        final context = await serverContext(id);
        final date = context['fecha_fisica'];
        if (context['solicitud_id'] != id ||
            context['pedido_id'] != orderId ||
            context['actor_id'] != actorId ||
            context['protocolo'] != 2 ||
            context['regimen_id'] is! String ||
            !RegExp(
              r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$',
            ).hasMatch(context['regimen_id'] as String) ||
            date is! String ||
            !RegExp(
              r'(Z|[+-]\d{2}:\d{2})$',
              caseSensitive: false,
            ).hasMatch(date) ||
            DateTime.tryParse(date) == null) {
          throw const FinalizationClockException();
        }
        return {
          ...frozen,
          'p_pedido_id': orderId,
          'p_solicitud_id': id,
          'p_fecha_fisica': DateTime.parse(date).toUtc().toIso8601String(),
          'p_regimen_id': context['regimen_id'],
          'p_protocolo': 2,
        };
      }
      if (physicalDate == null && serverClock == null) {
        throw StateError(
          'Se requiere una fecha explícita o la hora del servidor.',
        );
      }
      final date = physicalDate ?? await serverClock!();
      return {
        ...frozen,
        'p_pedido_id': orderId,
        'p_solicitud_id': id,
        'p_fecha_fisica': date.toUtc().toIso8601String(),
      };
    });
  }

  Future<void> acknowledge(String orderId) =>
      database.withKeyLock(key(orderId), () async {
        database.acknowledge(key(orderId));
      });

  void markForReview(String orderId, String code) =>
      database.review(key(orderId), code);

  /// Imports operational requests atomically. Retains all legacy preferences.
  /// Full-file parsing is supplied separately so malformed files fail closed.
  Future<void> migrateLegacy(
    Future<Map<String, Object?>> Function() readLegacy,
  ) => database.withKeyLock(key('__legacy_import__'), () async {
    final id = LocalOutbox.digest(jsonEncode([projectUrl, actorId]));
    if (database.legacyImported(id)) return;
    importLegacyValues(await readLegacy(), migrationId: id);
  });

  void importLegacyValues(Map<String, Object?> values, {String? migrationId}) {
    final prefix = 'preventa_v1:${Uri.encodeComponent(projectUrl)}:$actorId:';
    final imported = <OutboxKey, Map<String, dynamic>>{};
    try {
      for (final entry in values.entries) {
        final name = entry.key.startsWith('flutter.')
            ? entry.key.substring(8)
            : entry.key;
        if (!name.startsWith(prefix)) continue;
        if (entry.value is! String) throw const FormatException();
        final payload = Map<String, dynamic>.from(
          jsonDecode(entry.value as String) as Map,
        );
        final order = name.substring(prefix.length);
        final id = payload['p_solicitud_id'];
        if (order.isEmpty ||
            payload['p_pedido_id'] != order ||
            id is! String ||
            !RegExp(
              r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$',
            ).hasMatch(id) ||
            payload['p_fecha_fisica'] is! String ||
            DateTime.tryParse(payload['p_fecha_fisica'] as String) == null ||
            payload.keys.any(
              (k) =>
                  !allowedInput.contains(k) &&
                  !{
                    'p_pedido_id',
                    'p_solicitud_id',
                    'p_fecha_fisica',
                  }.contains(k),
            )) {
          throw const FormatException();
        }
        final duplicate = imported.entries.where(
          (entry) => entry.key.order == order,
        );
        if (duplicate.isNotEmpty &&
            jsonEncode(duplicate.single.value) != jsonEncode(payload)) {
          throw const FormatException('Conflicting legacy aliases');
        }
        if (duplicate.isEmpty) imported[key(order)] = payload;
      }
      database.importLegacy(imported, migrationId: migrationId);
    } catch (_) {
      throw const LocalOutboxException(
        'Las solicitudes antiguas están dañadas o contradicen la cola local. Se conservaron; requiere revisión antes de continuar.',
      );
    }
  }

  static Map<String, Object?> parseLegacyFile(String bytes) {
    try {
      if (bytes.trim().isEmpty) throw const FormatException();
      final decoded = jsonDecode(bytes);
      if (decoded is! Map) throw const FormatException();
      return Map<String, Object?>.from(decoded);
    } catch (_) {
      throw const LocalOutboxException(
        'El archivo de preferencias antiguo está dañado. No se importó ni restableció.',
      );
    }
  }
}

class FinalizationClockException implements Exception {
  const FinalizationClockException();
  @override
  String toString() =>
      'No se pudo obtener la hora y el contexto de Stock del servidor. La gestión no se envió. Revisá la conexión y volvé a intentar.';
}

Map<String, dynamic> contextualDeliveryLines(
  Iterable<Map<String, dynamic>> details,
) {
  final originals = <Map<String, dynamic>>[];
  final additions = <Map<String, dynamic>>[];
  for (final detail in details) {
    if (detail['agregado_en_entrega'] == true) {
      additions.add({
        'producto_id': detail['producto_id'],
        'cantidad_entregada': detail['cantidad_entregada'],
        'tipo_precio': detail['tipo_precio'] ?? 'normal',
      });
    } else {
      originals.add({
        'detalle_id': detail['id'],
        'cantidad_entregada': detail['cantidad_entregada'],
      });
    }
  }
  return {'p_originales': originals, 'p_agregados': additions};
}

Future<Map<String, dynamic>> prepareCurrentFinalization(
  SupabaseClient client,
  FinalizationRequestStore store,
  String orderId,
  Map<String, dynamic> input, {
  AppConfig? config,
}) async {
  (config ?? appConfig).requireV2Client(client.rest.url);
  _requireScope(client, store);
  return store.prepare(
    orderId,
    input,
    serverContext: (id) async {
      try {
        final raw = await client
            .rpc(
              'preparar_finalizacion_contexto',
              params: {'p_solicitud_id': id, 'p_pedido_id': orderId},
            )
            .timeout(const Duration(seconds: 20));
        if (raw is! Map) throw const FormatException();
        return Map<String, dynamic>.from(raw);
      } on PostgrestException catch (error) {
        if (error.code == 'PT409') rethrow;
        throw const FinalizationClockException();
      } catch (_) {
        throw const FinalizationClockException();
      }
    },
  );
}

bool isFinalizationDateError(PostgrestException error) =>
    error.code == 'PT422' &&
    error.message.toLowerCase().contains('fecha o solicitud inválida');

Future<LocalOutbox>? _openingDatabase;

Future<FinalizationRequestStore> finalizationStore(
  SupabaseClient client,
) async {
  appConfig.requireV2Client(client.rest.url);
  final actor = client.auth.currentUser?.id;
  if (actor == null) throw StateError('Sesión requerida');
  final support = await getApplicationSupportDirectory();
  LocalOutbox db;
  try {
    db = await (_openingDatabase ??= LocalOutbox.open(
      p.join(support.path, 'stock_v2_outbox_${appConfig.environment.name}'),
    ));
  } catch (_) {
    _openingDatabase = null;
    rethrow;
  }
  final store = FinalizationRequestStore(db, client.rest.url, actor);
  await store.migrateLegacy(() async {
    if (Platform.isWindows) {
      final legacy = File(p.join(support.path, 'shared_preferences.json'));
      return await legacy.exists()
          ? FinalizationRequestStore.parseLegacyFile(
              await legacy.readAsString(),
            )
          : <String, Object?>{};
    }
    if (Platform.isAndroid) {
      // Explicit legacy backend/file: Async defaults to DataStore, which would
      // miss requests previously saved by the original SharedPreferences API.
      return SharedPreferencesAsync(
        options: const SharedPreferencesAsyncAndroidOptions(
          backend: SharedPreferencesAndroidBackendLibrary.SharedPreferences,
          originalSharedPreferencesOptions:
              AndroidSharedPreferencesStoreOptions(
                fileName: 'FlutterSharedPreferences',
              ),
        ),
      ).getAll();
    }
    throw const LocalOutboxException(
      'Cola local habilitada únicamente para Windows y Android.',
    );
  });
  return store;
}

void _requireScope(SupabaseClient client, FinalizationRequestStore store) {
  final scope = store.projectUrl.replaceFirst(RegExp(r'/$'), '');
  if (scope != client.rest.url.replaceFirst(RegExp(r'/$'), '') ||
      (client.auth.currentUser != null &&
          client.auth.currentUser!.id != store.actorId)) {
    throw const LocalOutboxException(
      'La solicitud pertenece a otro proyecto o usuario. No se envió.',
    );
  }
}

void _validateResult(
  Map<String, dynamic> result,
  Map<String, dynamic> payload,
) {
  if ((result.containsKey('pedido_id') &&
          result['pedido_id'] != payload['p_pedido_id']) ||
      (result.containsKey('solicitud_id') &&
          result['solicitud_id'] != payload['p_solicitud_id']) ||
      !{
        'entregado',
        'parcial',
        'no_entregado',
      }.contains(result['resultado_entrega'])) {
    throw const LocalOutboxException(
      'La confirmación recibida no coincide con la solicitud. Se conserva para revisión.',
    );
  }
}

Future<Map<String, dynamic>> reconcileFinalization(
  SupabaseClient client,
  Map<String, dynamic> payload, {
  required FinalizationRequestStore store,
  bool retry = false,
  AppConfig? config,
}) async {
  (config ?? appConfig).requireV2Client(client.rest.url);
  _requireScope(client, store);
  // Freeze caller data; only the exact committed payload may be submitted.
  final frozen = Map<String, dynamic>.from(
    jsonDecode(jsonEncode(payload)) as Map,
  );
  final order = frozen['p_pedido_id'];
  if (order is! String) {
    throw const LocalOutboxException('Solicitud local inválida.');
  }
  final key = store.key(order);
  return store.database.withKeyLock(key, () async {
    store.database.requirePersisted(key, frozen);
    final saved = store.database.read(key)!;
    if (saved.result != null) {
      _validateResult(saved.result!, frozen);
      return saved.result!;
    }
    final status = Map<String, dynamic>.from(
      await client
              .rpc(
                'consultar_finalizacion_solicitud',
                params: {'p_solicitud_id': frozen['p_solicitud_id']},
              )
              .timeout(const Duration(seconds: 20))
          as Map,
    );
    if (status['estado'] != 'confirmada') {
      if (status['estado'] != 'inexistente') {
        throw const LocalOutboxException(
          'Estado de recuperación no reconocido. Se conserva la solicitud.',
        );
      }
      if (!retry) return status;
    }
    // A lookup by UUID does not validate this local request's content. V2 is
    // authoritative: identical retries return the original result without effects.
    // Keep the same interprocess lock and recheck the exact committed payload.
    store.database.requirePersisted(key, frozen);
    Map<String, dynamic> result;
    try {
      result = Map<String, dynamic>.from(
        await client
                .rpc(
                  frozen.containsKey('p_regimen_id') ||
                          frozen.containsKey('p_protocolo')
                      ? 'finalizar_gestion_pedido_contexto'
                      : 'finalizar_gestion_pedido_v2',
                  params: frozen,
                )
                .timeout(const Duration(seconds: 20))
            as Map,
      );
    } on PostgrestException catch (error) {
      final detail = '${error.message} ${error.details ?? ''}'.toLowerCase();
      if (error.code == 'PT409' &&
          (detail.contains('solicitud_incompatible') ||
              detail.contains('regimen_incompatible') ||
              detail.contains('contexto_regimen_requerido'))) {
        try {
          store.database.review(
            key,
            detail.contains('solicitud_incompatible')
                ? 'solicitud_incompatible'
                : 'regimen_incompatible',
          );
        } on LocalOutboxException {
          throw const LocalOutboxException(
            'La solicitud tiene contenido incompatible y requiere revisión. No se pudo guardar la marca local; no se confirmó ni se creó otra solicitud.',
          );
        }
      }
      rethrow;
    }
    _validateResult(result, frozen);
    store.database.confirm(key, frozen, result);
    return store.database.read(key)!.result!;
  });
}

String finalizationErrorMessage(PostgrestException error) {
  final detail = '${error.details ?? ''} ${error.message}'.toLowerCase();
  if (detail.contains('stock_en_mantenimiento')) {
    return 'Las operaciones de Stock están pausadas. La solicitud se conserva para recuperar o reintentar cuando administración habilite el servicio.';
  }
  if (detail.contains('regimen_incompatible') ||
      detail.contains('contexto_regimen_requerido') ||
      detail.contains('regimen_inconsistente')) {
    return 'La solicitud corresponde a un régimen de Stock anterior o no compatible. Se conserva sin confirmar y requiere revisión; no cambies su fecha ni crees otra.';
  }
  if (detail.contains('stock_insuficiente') ||
      detail.contains('stock insuficiente')) {
    return 'Stock insuficiente. La solicitud se conserva para revisión; no inicies otra gestión.';
  }
  if (detail.contains('no inicializado') ||
      detail.contains('stock_no_inicializado')) {
    return 'El producto todavía no tiene stock inicial. La solicitud se conserva para revisión.';
  }
  if (detail.contains('solicitud_incompatible')) {
    return 'Esta solicitud ya tiene otro contenido. Se conserva sin confirmar y requiere revisión; no crees otra.';
  }
  if (detail.contains('actualizacion_requerida')) {
    return 'Actualizá la aplicación para continuar con esta operación.';
  }
  if (detail.contains('operacion_ya_finalizada')) {
    return 'El pedido ya fue finalizado. Revisá la operación guardada.';
  }
  if (isFinalizationDateError(error)) {
    return 'La fecha de la solicitud no fue aceptada por el servidor. La solicitud se conserva para revisión; no inicies otra gestión.';
  }
  if (error.code == 'PT422') {
    return 'El servidor rechazó cantidades, facturación, motivo o pago. La solicitud se conserva para revisión.';
  }
  return 'No se pudo confirmar la gestión. La solicitud se conserva para revisar o reintentar.';
}
