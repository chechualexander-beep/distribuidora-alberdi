import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_theme.dart';
import '../../core/desktop_records.dart';
import '../../core/network_status.dart';
import '../../core/offline_cache.dart';
import '../../core/offline_queries.dart';
import '../products/product_photo.dart';
import 'stock_data.dart';

/// "Lo que llevamos": todo lo que va en el vehículo, por categoría, con lo que queda para
/// vender. Lo usa el preventista para no olvidarse de ofrecer nada.
class VehicleLoadPage extends StatefulWidget {
  const VehicleLoadPage({super.key, this.client});
  final SupabaseClient? client;

  @override
  State<VehicleLoadPage> createState() => _VehicleLoadPageState();
}

class _VehicleLoadPageState extends State<VehicleLoadPage> {
  SupabaseClient get _client => widget.client ?? Supabase.instance.client;
  bool _loading = true;
  String? _error;
  VehicleStock _vehicle = const VehicleStock();
  List<Map<String, dynamic>> _products = const [];
  DateTime? _savedAt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final vehicle = await fetchVehicleStock(_client);
      final savedAt = showingCachedSince.value;
      final products = await consultarProductosParaPedido(_client);
      if (!mounted) return;
      setState(() {
        _vehicle = vehicle;
        _products = products;
        _savedAt = savedAt;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = isUncertainRequestError(error)
            ? 'Sin conexión y sin una copia guardada. Probá de nuevo cuando haya señal.'
            : 'No se pudo cargar lo que lleva el vehículo.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Lo que llevamos'),
      actions: [IconButton(tooltip: 'Actualizar', onPressed: _load, icon: const Icon(Icons.refresh))],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!, textAlign: TextAlign.center),
                  TextButton(onPressed: _load, child: const Text('Reintentar')),
                ],
              ),
            ),
          )
        : RefreshIndicator(onRefresh: _load, child: DesktopForm(child: _list())),
  );

  Widget _list() {
    final rows = [
      for (final p in _products)
        if (_vehicle.lines.containsKey(p['id'].toString())) p,
    ];
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final p in rows) {
      final category = (p['categoria']?.toString().trim().isNotEmpty ?? false)
          ? p['categoria'].toString().trim()
          : 'Sin categoría';
      groups.putIfAbsent(category, () => []).add(p);
    }
    final categories = groups.keys.toList()..sort();
    double available(Map<String, dynamic> p) => _vehicle.lines[p['id'].toString()]!.available;
    for (final list in groups.values) {
      // Lo agotado al final de cada categoría.
      list.sort((a, b) {
        final ea = available(a) <= 0, eb = available(b) <= 0;
        if (ea != eb) return ea ? 1 : -1;
        return (a['nombre']?.toString() ?? '').compareTo(b['nombre']?.toString() ?? '');
      });
    }
    final left = rows.where((p) => available(p) > 0).length;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          !_vehicle.tripOpen && rows.isEmpty
              ? 'El vehículo no tiene carga registrada. Se ve acá cuando el administrador carga el vehículo.'
              : '$left productos para ofrecer · ${rows.length - left} agotados',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        Text(
          _savedAt != null
              ? 'Sin señal: datos guardados ${describeSavedAt(_savedAt!)}'
              : 'Actualizado recién. Lo vendido y todavía no entregado ya está descontado.',
          style: const TextStyle(color: AppColors.gris),
        ),
        for (final category in categories) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
            child: Text(
              category.toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1, color: AppColors.doradoOscuro),
            ),
          ),
          for (final p in groups[category]!) _row(p),
        ],
      ],
    );
  }

  Widget _row(Map<String, dynamic> p) {
    final line = _vehicle.lines[p['id'].toString()]!;
    final out = line.available <= 0;
    return Card(
      child: ListTile(
        leading: Opacity(
          opacity: out ? 0.4 : 1,
          child: ProductPhoto(path: p['foto_path']?.toString(), size: 44),
        ),
        title: Text(
          p['nombre']?.toString() ?? 'Producto',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: out ? AppColors.gris : null,
            decoration: out ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: line.committed > 0
            ? Text('Arriba ${formatQty(line.inVehicle)} · vendido sin entregar ${formatQty(line.committed)}')
            : null,
        trailing: Text(
          out ? 'Agotado' : 'Quedan ${formatQty(line.available)}',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: out ? AppColors.rojo : AppColors.verde,
          ),
        ),
      ),
    );
  }
}
