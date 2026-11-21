import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_theme.dart';
import '../../core/money_format.dart';
import '../../core/offline_queries.dart';
import '../../core/text_search.dart';
import 'calculator_math.dart';

/// Producto para "Traer producto". El costo solo viene cuando lo carga el administrador.
class CalcProduct {
  const CalcProduct({
    required this.id,
    required this.nombre,
    this.descripcion,
    this.codigo,
    this.normal = 0,
    this.promo,
    this.interior,
    this.costo,
  });

  factory CalcProduct.fromMap(Map<String, dynamic> m) {
    double? n(Object? v) => v == null ? null : double.tryParse(v.toString());
    return CalcProduct(
      id: m['id'].toString(),
      nombre: m['nombre']?.toString() ?? 'Producto',
      descripcion: m['descripcion']?.toString(),
      codigo: m['codigo']?.toString() ?? m['codigo_original']?.toString(),
      normal: n(m['precio_normal']) ?? 0,
      promo: n(m['precio_promo']),
      interior: n(m['precio_interior']),
      costo: n(m['costo']),
    );
  }

  final String id;
  final String nombre;
  final String? descripcion;
  final String? codigo;
  final double normal;
  final double? promo;
  final double? interior;
  final double? costo;

  double precio(String lista) => switch (lista) {
    'promo' when (promo ?? 0) > 0 => promo!,
    'interior' when (interior ?? 0) > 0 => interior!,
    _ => normal,
  };

  /// Kilos que trae, leídos del nombre (o de la descripción).
  double? get kilos => kilosDelTexto(nombre) ?? kilosDelTexto(descripcion);
}

/// Administrador: productos con costo. Preventista: los del pedido, sin costo.
Future<List<CalcProduct>> cargarProductosCalculadora(SupabaseClient c) async {
  final uid = c.auth.currentUser?.id;
  if (uid == null) throw Exception('No hay usuario autenticado');
  final usuario = await consultarRolActivo(c, uid);
  final filas = usuario['rol']?.toString() == 'administrador'
      ? List<Map<String, dynamic>>.from(
          await c
              .from('productos_administracion')
              .select(
                'id,codigo,nombre,descripcion,costo,precio_normal,precio_promo,precio_interior',
              )
              .eq('activo', true)
              .order('nombre'),
        )
      : await consultarProductosParaPedido(c);
  return filas.map(CalcProduct.fromMap).toList();
}

/// Lo que se usó la última vez en "Por bulto" (queda en el teléfono).
class BultoPrefs {
  const BultoPrefs({
    this.recargo = 30,
    this.kgPedido = 1,
    this.redondeo = 50,
    this.kgBulto = 4,
  });

  final double recargo;
  final double kgPedido;
  final double redondeo;
  final double kgBulto;

  static const _recargo = 'calc_bulto_recargo';
  static const _pide = 'calc_bulto_pide';
  static const _redondeo = 'calc_bulto_redondeo';
  static const _trae = 'calc_bulto_trae';

  static Future<BultoPrefs> leer() async {
    final p = await SharedPreferences.getInstance();
    const d = BultoPrefs();
    return BultoPrefs(
      recargo: p.getDouble(_recargo) ?? d.recargo,
      kgPedido: p.getDouble(_pide) ?? d.kgPedido,
      redondeo: p.getDouble(_redondeo) ?? d.redondeo,
      kgBulto: p.getDouble(_trae) ?? d.kgBulto,
    );
  }

  Future<void> guardar() async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_recargo, recargo);
    await p.setDouble(_pide, kgPedido);
    await p.setDouble(_redondeo, redondeo);
    await p.setDouble(_trae, kgBulto);
  }
}

/// Buscador de productos de la calculadora (sin acentos, por palabras).
Future<CalcProduct?> elegirProductoCalculadora(
  BuildContext context,
  List<CalcProduct> productos,
  String lista,
) {
  return showDialog<CalcProduct>(
    context: context,
    builder: (context) {
      var busqueda = '';
      return StatefulBuilder(
        builder: (context, setLocal) {
          final lista0 = productos
              .where((p) => coincideBusqueda(busqueda, [p.nombre, p.codigo, p.descripcion]))
              .take(60)
              .toList();
          return AlertDialog(
            title: const Text('Traer producto'),
            contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            content: SizedBox(
              width: 460,
              height: 420,
              child: Column(
                children: [
                  TextField(
                    key: const Key('calc-buscar-producto'),
                    autofocus: true,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Buscar producto...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => setLocal(() => busqueda = v),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: productos.isEmpty
                        ? const Center(
                            child: Text(
                              'No hay productos cargados. Probá de nuevo con señal.',
                              textAlign: TextAlign.center,
                            ),
                          )
                        : lista0.isEmpty
                        ? const Center(child: Text('No se encontraron productos'))
                        : ListView.separated(
                            itemCount: lista0.length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final p = lista0[i];
                              return ListTile(
                                dense: true,
                                title: Text(
                                  p.nombre,
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                trailing: Text(
                                  formatoPesos(p.precio(lista)),
                                  style: TextStyle(color: colorLista(lista)),
                                ),
                                onTap: () => Navigator.pop(context, p),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Volver'),
              ),
            ],
          );
        },
      );
    },
  );
}
