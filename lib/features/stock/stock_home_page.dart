import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_theme.dart';
import '../../core/desktop_records.dart';
import '../../core/network_status.dart';
import 'stock_data.dart';
import 'stock_form_page.dart';
import 'vehicle_load_page.dart';

enum _Filter { controlled, onDemand, differences, all }

/// Stock del administrador: depósito y vehículo, viaje, conteos, compras.
class StockHomePage extends StatefulWidget {
  const StockHomePage({super.key, this.client});
  final SupabaseClient? client;

  @override
  State<StockHomePage> createState() => _StockHomePageState();
}

class _StockHomePageState extends State<StockHomePage> {
  SupabaseClient get _client => widget.client ?? Supabase.instance.client;
  bool _loading = true;
  String? _error;
  List<StockItem> _items = const [];
  VehicleStock _vehicle = const VehicleStock();
  Map<String, String> _sellerNames = const {};
  _Filter _filter = _Filter.controlled;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await fetchStockItems(_client);
      final vehicle = await fetchVehicleStock(_client);
      var names = _sellerNames;
      try {
        names = {
          for (final s in await fetchSellers(_client))
            s['id'].toString(): '${s['nombre'] ?? ''} ${s['apellido'] ?? ''}'.trim(),
        };
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _items = items;
        _vehicle = vehicle;
        _sellerNames = names;
        if (!items.any((i) => i.controlled) && _filter == _Filter.controlled) _filter = _Filter.all;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = isUncertainRequestError(error)
            ? 'Sin conexión. Probá de nuevo cuando haya señal.'
            : 'No se pudo cargar el stock: ${stockErrorText(error)}';
        _loading = false;
      });
    }
  }

  Future<void> _open(StockFormKind kind, {Set<String>? only}) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => StockFormPage(
          kind: kind,
          items: _items,
          tripId: _vehicle.tripId,
          onlyIds: only,
          client: widget.client,
        ),
      ),
    );
    if (changed == true && mounted) await _load();
  }

  Future<void> _productActions(StockItem item) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(item.controlled ? 'Con stock' : 'A pedido (no lleva stock)'),
            ),
            ListTile(
              leading: const Icon(Icons.fact_check_outlined),
              title: Text(item.controlled ? 'Contar' : 'Contar y pasar a "con stock"'),
              onTap: () => Navigator.pop(context, 'contar'),
            ),
            if (item.controlled)
              ListTile(
                leading: const Icon(Icons.shopping_basket_outlined),
                title: const Text('Pasar a "a pedido"'),
                subtitle: const Text('Deja de llevar stock (se compra cuando hay pedido).'),
                onTap: () => Navigator.pop(context, 'a_pedido'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'contar') {
      await _open(StockFormKind.count, only: {item.id});
    } else if (action == 'a_pedido') {
      try {
        await _client.rpc('stock_marcar_a_pedido', params: {'p_producto_id': item.id});
        await _load();
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(stockErrorText(error))));
        }
      }
    }
  }

  List<StockItem> get _visible {
    final text = _search.text.trim().toLowerCase();
    return _items.where((i) {
      if (text.isNotEmpty && !i.name.toLowerCase().contains(text) && !i.code.toLowerCase().contains(text)) {
        return false;
      }
      return switch (_filter) {
        _Filter.controlled => i.controlled,
        _Filter.onDemand => !i.controlled,
        _Filter.differences => i.negative,
        _Filter.all => true,
      };
    }).toList();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Stock'),
      actions: [IconButton(tooltip: 'Actualizar', onPressed: _load, icon: const Icon(Icons.refresh))],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!),
                TextButton(onPressed: _load, child: const Text('Reintentar')),
              ],
            ),
          )
        : RefreshIndicator(onRefresh: _load, child: _content()),
  );

  Widget _content() {
    final visible = _visible;
    final controlled = _items.where((i) => i.controlled).length;
    final negatives = _items.where((i) => i.negative).length;
    return DesktopForm(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _tripCard(),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                icon: const Icon(Icons.local_shipping_outlined),
                label: const Text('Cargar vehículo'),
                onPressed: () => _open(StockFormKind.load),
              ),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.warehouse_outlined),
                label: const Text('Bajar al depósito'),
                onPressed: () => _open(StockFormKind.unload),
              ),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.add_shopping_cart),
                label: const Text('Anotar compra'),
                onPressed: () => _open(StockFormKind.purchase),
              ),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Contar'),
                onPressed: () => _open(StockFormKind.count),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            controlled == 0
                ? 'Todavía ningún producto lleva stock: contá los primeros para empezar '
                      '(los demás quedan "a pedido").'
                : '$controlled productos con stock · ${_items.length - controlled} a pedido',
            style: const TextStyle(color: AppColors.gris),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final f in _Filter.values)
                ChoiceChip(
                  label: Text(switch (f) {
                    _Filter.controlled => 'Con stock',
                    _Filter.onDemand => 'A pedido',
                    _Filter.differences => 'En negativo ($negatives)',
                    _Filter.all => 'Todos',
                  }),
                  selected: _filter == f,
                  onSelected: (_) => setState(() => _filter = f),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _search,
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search),
              hintText: 'Buscar producto...',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          if (visible.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No hay productos con este filtro.', textAlign: TextAlign.center),
            ),
          for (final item in visible)
            Card(
              child: ListTile(
                title: Text(item.name),
                subtitle: Text(item.controlled ? item.category : '${item.category} · a pedido'),
                trailing: item.controlled
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Depósito ${formatQty(item.deposit)}',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: item.deposit < 0 ? AppColors.rojo : null,
                            ),
                          ),
                          Text(
                            'Vehículo ${formatQty(item.vehicle)}',
                            style: TextStyle(color: item.vehicle < 0 ? AppColors.rojo : AppColors.gris),
                          ),
                        ],
                      )
                    : const Icon(Icons.chevron_right),
                onTap: () => _productActions(item),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tripCard() {
    final open = _vehicle.tripOpen;
    final seller = _vehicle.sellerId == null ? null : _sellerNames[_vehicle.sellerId];
    final units = _vehicle.lines.values.fold<double>(0, (s, l) => s + (l.inVehicle > 0 ? l.inVehicle : 0));
    return Card(
      color: open ? const Color(0xFFE8F5E9) : null,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.local_shipping_outlined, color: open ? AppColors.verde : AppColors.gris),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    open ? 'Viaje abierto' : 'Sin viaje abierto',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              [
                if (open && _vehicle.openedAt != null) 'Desde ${describeSavedAt(_vehicle.openedAt!)}',
                if (seller != null && seller.isNotEmpty) 'con $seller',
                '${_vehicle.lines.length} productos arriba (${formatQty(units)} unidades)',
              ].join(' · '),
            ),
            if (!open)
              const Text(
                'Se abre al cargar el vehículo.',
                style: TextStyle(color: AppColors.gris),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: const Text('Lo que llevamos'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => VehicleLoadPage(client: widget.client)),
                  ),
                ),
                if (open)
                  FilledButton.icon(
                    icon: const Icon(Icons.flag_outlined),
                    label: const Text('Cerrar viaje'),
                    onPressed: () => _open(StockFormKind.closeTrip),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
