import 'dart:async';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'stock_models.dart';

class StockException implements Exception {
  const StockException(this.message);
  final String message;
}

String stockError(Object error) {
  if (error is StockException) return error.message;
  if (error is SocketException || error is TimeoutException) {
    return 'No pudimos confirmar la conexión. Actualizá Stock antes de reintentar.';
  }
  if (error is AuthException) {
    return 'La sesión venció. Volvé a iniciar sesión.';
  }
  if (error is PostgrestException) {
    if (error.code == 'PGRST301' ||
        error.code == 'PGRST302' ||
        error.code == 'PGRST303') {
      return 'La sesión venció. Volvé a iniciar sesión.';
    }
    if (error.code == '42501') {
      return 'No tenés permiso para operar Stock. Se requiere un administrador activo.';
    }
    if (error.code == '23505') {
      return 'Un producto ya tiene stock inicial cargado. Cerrá el formulario y actualizá Stock.';
    }
    if (error.code == '22023') {
      if (error.message.contains('todavía no tiene stock inicial')) {
        return 'El producto todavía no tiene stock inicial cargado.';
      }
      if (error.message.contains('ubicación')) {
        return 'La ubicación no existe o está inactiva.';
      }
      if (error.message.contains('motivo')) return 'Ingresá un motivo válido.';
      if (error.message.contains('coincide')) {
        return 'El conteo coincide con el stock actual. Actualizá Stock.';
      }
      return 'Revisá los productos y las cantidades: deben ser no negativas y tener hasta tres decimales.';
    }
  }
  return 'No pudimos completar la operación. Cerrá el formulario y actualizá Stock antes de reintentar.';
}

class StockService {
  StockService({SupabaseClient? client}) : _providedClient = client;
  final SupabaseClient? _providedClient;
  SupabaseClient get _client => _providedClient ?? Supabase.instance.client;
  static const movementPageSize = 100;

  Future<StockSnapshot> load() async {
    final row = await _client
        .from('ubicaciones_stock')
        .select('id,nombre,activo')
        .eq('codigo', 'deposito_alberdi')
        .maybeSingle();
    if (row == null) {
      throw const StockException(
        'No se encontró Depósito Distribuidora Alberdi. Contactá a administración.',
      );
    }
    final location = StockLocation(
      row['id'] as String,
      row['nombre'] as String,
      row['activo'] as bool,
    );
    final responses = await Future.wait([
      _client.rpc('consultar_stock', params: {'p_ubicacion_id': location.id}),
      _client.rpc('resumen_stock', params: {'p_ubicacion_id': location.id}),
    ]);
    return StockSnapshot(
      location,
      (responses[0] as List)
          .map(
            (r) => StockProduct.fromJson(Map<String, dynamic>.from(r as Map)),
          )
          .toList(),
      StockSummary.fromJson(
        Map<String, dynamic>.from((responses[1] as List).single as Map),
      ),
    );
  }

  Future<int> initialize(
    String location,
    List<Map<String, dynamic>> items,
  ) async {
    if (items.isEmpty || items.length > 300) {
      throw const StockException(
        'Seleccioná entre 1 y 300 productos por carga.',
      );
    }
    final result = await _client.rpc(
      'cargar_stock_inicial',
      params: {'p_ubicacion_id': location, 'p_items': items},
    );
    return int.parse(result.toString());
  }

  Future<void> adjust(
    String location,
    String product,
    StockQuantity quantity,
    String reason,
    String observation,
  ) async {
    await _client.rpc(
      'ajustar_stock',
      params: {
        'p_ubicacion_id': location,
        'p_producto_id': product,
        'p_cantidad_nueva': quantity.toJsonNumber(),
        'p_motivo': reason.trim(),
        'p_observacion': observation.trim().isEmpty ? null : observation.trim(),
      },
    );
  }

  Future<List<StockMovement>> movements(
    String location, {
    String search = '',
    String? type,
    int offset = 0,
  }) async {
    var query = _client
        .from('stock_movimientos')
        .select(
          'id,created_at,tipo,cantidad_anterior,cantidad_delta,cantidad_nueva,motivo,observacion,producto:productos!inner(nombre,codigo),usuario:usuarios(nombre,apellido)',
        )
        .eq('ubicacion_id', location);
    if (type != null) query = query.eq('tipo', type);
    if (search.trim().isNotEmpty) {
      final term = search
          .trim()
          .replaceAll('\\', '\\\\')
          .replaceAll('"', '\\"')
          .replaceAll('%', '\\%')
          .replaceAll('_', '\\_')
          .replaceAll('*', '\\*');
      query = query.or(
        'nombre.ilike."%$term%",codigo.ilike."%$term%"',
        referencedTable: 'producto',
      );
    }
    final rows = await query
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .range(offset, offset + movementPageSize - 1);
    return rows.map(StockMovement.fromJson).toList();
  }
}
