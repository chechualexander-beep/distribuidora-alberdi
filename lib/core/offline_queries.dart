import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';
import 'network_status.dart';
import 'offline_cache.dart';
import 'pending_orders.dart';

// Consultas compartidas entre las pantallas y "Preparar para trabajar sin señal".
// Tienen que ser EXACTAMENTE las mismas en los dos lados: la copia local se busca por la
// consulta, así que una pantalla encuentra lo que se preparó solo si pregunta igual.

typedef Fila = Map<String, dynamic>;

/// Suma a la lista los clientes nuevos hechos sin señal que todavía no llegaron al servidor
/// (marcados con [PendingOrders.sinEnviarKey]), ordenados por nombre como el resto.
List<Fila> conClientesSinEnviar(List<Fila> clientes) {
  final nuevos = PendingOrders.instance.pendingClients;
  if (nuevos.isEmpty) return clientes;
  final ids = {for (final c in clientes) c['id']?.toString()};
  final faltan = nuevos.where((c) => !ids.contains(c['id']?.toString())).toList();
  if (faltan.isEmpty) return clientes;
  String nombre(Fila c) => (c['nombre_comercio']?.toString() ?? '').toLowerCase();
  return [...clientes, ...faltan]..sort((a, b) => nombre(a).compareTo(nombre(b)));
}

bool _sinEnviar(String clienteId) => PendingOrders.instance.isPendingClient(clienteId);

Future<Fila> consultarRol(SupabaseClient c, String uid) =>
    c.from('usuarios').select('rol').eq('id', uid).single();

Future<Fila> consultarRolActivo(SupabaseClient c, String uid) =>
    c.from('usuarios').select('rol,activo').eq('id', uid).single();

Future<Fila> consultarPerfilInicio(SupabaseClient c, String uid) => c
    .from('usuarios')
    .select('nombre, apellido, rol, activo')
    .eq('id', uid)
    .single();

/// Clientes activos con todos sus datos (pantalla Clientes), paginado de a 500.
Future<List<Fila>> consultarClientesActivos(
  SupabaseClient c, {
  required String uid,
  required bool administrador,
}) async {
  final clientes = <Fila>[];
  const tamanio = 500;
  for (var desde = 0; ; desde += tamanio) {
    var consulta = c.from('clientes').select().eq('activo', true);
    if (!administrador) consulta = consulta.eq('preventista_id', uid);
    final pagina = await consulta
        .order('nombre_comercio')
        .order('id')
        .range(desde, desde + tamanio - 1);
    clientes.addAll(List<Fila>.from(pagina));
    if (pagina.length < tamanio) break;
  }
  return conClientesSinEnviar(clientes);
}

const _camposClientePedido =
    'id, nombre_comercio, propietario, direccion, localidad, tipo_precio_habitual';

PostgrestFilterBuilder<List<Fila>> _clientesParaPedido(
  SupabaseClient c, {
  required String uid,
  required bool administrador,
}) {
  var consulta = c.from('clientes').select(_camposClientePedido).eq('activo', true);
  if (!administrador) consulta = consulta.eq('preventista_id', uid);
  return consulta;
}

/// Clientes para elegir al hacer un pedido o una venta directa.
Future<List<Fila>> consultarClientesParaPedido(
  SupabaseClient c, {
  required String uid,
  required bool administrador,
}) async => conClientesSinEnviar(
  List<Fila>.from(
    await _clientesParaPedido(c, uid: uid, administrador: administrador).order('nombre_comercio'),
  ),
);

Future<Fila?> consultarClienteParaPedido(
  SupabaseClient c, {
  required String uid,
  required bool administrador,
  required String clienteId,
}) async =>
    PendingOrders.instance.pendingClient(clienteId) ??
    await _clientesParaPedido(c, uid: uid, administrador: administrador).eq('id', clienteId).maybeSingle();

/// Productos con sus 3 precios para armar pedidos.
Future<List<Fila>> consultarProductosParaPedido(SupabaseClient c) async => List<Fila>.from(
  await c
      .from('productos')
      .select('id, codigo, nombre, descripcion, precio_normal, precio_promo, precio_interior, foto_path')
      .eq('activo', true)
      .eq('visible_preventistas', true)
      .order('nombre'),
);

/// Productos para la pantalla Productos.
Future<List<Fila>> consultarProductosCatalogo(SupabaseClient c) async => List<Fila>.from(
  await c
      .from('productos')
      .select('id,codigo,nombre,descripcion,categoria,precio_normal,precio_promo,precio_interior,foto_path')
      .eq('activo', true)
      .eq('visible_preventistas', true)
      .order('nombre'),
);

/// Saldo del cliente al elegirlo para un pedido.
Future<Fila?> consultarSaldoResumen(SupabaseClient c, String clienteId) async => _sinEnviar(clienteId)
    ? null
    : await c
    .from('saldos_pendientes_clientes')
    .select('saldo_pendiente, cantidad_pedidos_con_saldo')
    .eq('cliente_id', clienteId)
    .maybeSingle();

/// Saldo completo del cliente (ficha del cliente).
Future<Fila?> consultarSaldoDetalle(SupabaseClient c, String clienteId) async => _sinEnviar(clienteId)
    ? null
    : await c
    .from('saldos_pendientes_clientes')
    .select('total_entregado, total_neto, total_pagado, saldo_pendiente, cantidad_pedidos_con_saldo')
    .eq('cliente_id', clienteId)
    .maybeSingle();

/// Pedidos del cliente que todavía deben plata (ficha del cliente).
Future<List<Fila>> consultarPedidosConSaldo(SupabaseClient c, String clienteId) async =>
    _sinEnviar(clienteId) ? <Fila>[] : List<Fila>.from(
      await c
          .from('saldos_pendientes_pedidos')
          .select()
          .eq('cliente_id', clienteId)
          .gt('saldo_pendiente', 0),
    );

/// Teléfono del cliente para mandarle el pedido por WhatsApp.
Future<Fila?> consultarTelefonoCliente(SupabaseClient c, String clienteId) async =>
    PendingOrders.instance.pendingClient(clienteId) ??
    await c
    .from('clientes')
    .select('telefono,preventista_id')
    .eq('id', clienteId)
    .maybeSingle();

class PreparacionSinConexion {
  const PreparacionSinConexion(this.fecha, this.clientes, this.productos);
  final DateTime fecha;
  final int clientes, productos;
}

String _clavePreparacion(String uid) =>
    appConfig.localPreferenceKey('preparado_sin_conexion:$uid');

Future<PreparacionSinConexion?> leerPreparacion(String uid) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final partes = prefs.getString(_clavePreparacion(uid))?.split('|');
    if (partes == null || partes.length != 3) return null;
    return PreparacionSinConexion(
      DateTime.parse(partes[0]),
      int.parse(partes[1]),
      int.parse(partes[2]),
    );
  } catch (_) {
    return null;
  }
}

/// Al cerrar sesión: se borra la copia local y la fecha de preparación.
Future<void> borrarDatosSinConexion(String? uid) async {
  await offlineCache?.clear();
  if (uid != null) await borrarPreparacion(uid);
}

Future<void> borrarPreparacion(String uid) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_clavePreparacion(uid));
  } catch (_) {}
}

/// Descarga y guarda en el equipo lo necesario para trabajar sin señal: perfil, clientes,
/// productos con sus precios y el saldo de cada cliente. Sin red falla (no usa lo guardado).
Future<PreparacionSinConexion> prepararSinConexion(
  SupabaseClient c, {
  void Function(int hechos, int total)? progreso,
  int simultaneas = 6,
}) => withoutCacheFallback(() async {
  final uid = c.auth.currentUser?.id;
  if (uid == null) throw StateError('Sin sesión');
  final perfil = await consultarPerfilInicio(c, uid);
  await consultarRol(c, uid);
  await consultarRolActivo(c, uid);
  final administrador = perfil['rol'] == 'administrador';
  final clientes = await consultarClientesActivos(c, uid: uid, administrador: administrador);
  await consultarClientesParaPedido(c, uid: uid, administrador: administrador);
  final productos = await consultarProductosParaPedido(c);
  await consultarProductosCatalogo(c);

  final tareas = <Future<void> Function()>[
    for (final cliente in clientes) ...[
      () => consultarSaldoResumen(c, cliente['id'].toString()),
      () => consultarSaldoDetalle(c, cliente['id'].toString()),
      () => consultarPedidosConSaldo(c, cliente['id'].toString()),
      () => consultarTelefonoCliente(c, cliente['id'].toString()),
      () => consultarClienteParaPedido(
        c,
        uid: uid,
        administrador: administrador,
        clienteId: cliente['id'].toString(),
      ),
    ],
  ];
  var hechos = 0;
  progreso?.call(0, tareas.length);
  var siguiente = 0;
  Future<void> trabajador() async {
    while (siguiente < tareas.length) {
      final tarea = tareas[siguiente++];
      await tarea();
      progreso?.call(++hechos, tareas.length);
    }
  }

  await Future.wait([for (var i = 0; i < simultaneas; i++) trabajador()]);
  final resultado = PreparacionSinConexion(DateTime.now(), clientes.length, productos.length);
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _clavePreparacion(uid),
      '${resultado.fecha.toIso8601String()}|${resultado.clientes}|${resultado.productos}',
    );
  } catch (_) {}
  return resultado;
});
