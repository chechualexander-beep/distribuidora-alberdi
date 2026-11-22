import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_theme.dart';
import '../../core/desktop_records.dart';
import '../../core/network_status.dart';
import 'stock_data.dart';
import 'stock_form_page.dart';
import 'vehicle_load_page.dart';
import '../../core/text_search.dart';

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
    // Cargar y bajar trabajan con el stock de este momento (no con el de cuando se entró a Stock).
    if (kind == StockFormKind.load || kind == StockFormKind.unload) {
      await _load();
      if (!mounted || _error != null) return;
    }
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => StockFormPage(
          kind: kind,
          items: _items,
          tripId: _vehicle.tripId,
          onlyIds: only,
          client: widget.client,
          reload: () => fetchStockItems(_client),
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
              subtitle: Text(item.onDemand ? 'Se compra a pedido' : 'Se tiene en el depósito'),
            ),
            ListTile(
              leading: const Icon(Icons.fact_check_outlined),
              title: const Text('Contar'),
              onTap: () => Navigator.pop(context, 'contar'),
            ),
            if (item.parentId != null)
              ListTile(
                leading: const Icon(Icons.call_split),
                title: Text('Fraccionar: abrir ${_name(item.parentId)}'),
                subtitle: Text('1 de ese → ${formatQty(item.unitsPerParent ?? 0)} de este'),
                onTap: () => Navigator.pop(context, 'fraccionar'),
              ),
            ListTile(
              leading: const Icon(Icons.link),
              title: Text(item.parentId == null ? 'Sale de otro producto (fraccionado)' : 'Cambiar de qué producto sale'),
              onTap: () => Navigator.pop(context, 'configurar'),
            ),
            ListTile(
              leading: const Icon(Icons.shopping_basket_outlined),
              title: Text(item.onDemand ? 'Quitar "se compra a pedido"' : 'Marcar "se compra a pedido"'),
              subtitle: Text(
                item.onDemand
                    ? 'Vuelve a ser un producto que se tiene en el depósito.'
                    : 'Sigue llevando stock; es para la lista de compras y para que su 0 no sea alarma.',
              ),
              onTap: () => Navigator.pop(context, 'a_pedido'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'contar') {
      await _open(StockFormKind.count, only: {item.id});
    } else if (action == 'fraccionar') {
      await _fraction(item);
    } else if (action == 'configurar') {
      await _configureFraction(item);
    } else if (action == 'a_pedido') {
      try {
        await _client.rpc(
          'stock_marcar_a_pedido',
          params: {'p_producto_id': item.id, 'p_valor': !item.onDemand},
        );
        await _load();
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(stockErrorText(error))));
        }
      }
    }
  }

  String _name(String? id) =>
      _items.where((i) => i.id == id).map((i) => i.name).firstOrNull ?? 'otro producto';

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// "Abrí 1 bolsa de 4 kg" → suma las unidades sueltas y resta la bolsa.
  Future<void> _fraction(StockItem item) async {

    final count = TextEditingController(text: '1');
    var location = _vehicle.tripOpen ? vehiculoCodigo : depositoCodigo;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('Fraccionar ${item.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: count,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Cuántos abrís de ${_name(item.parentId)}',
                  helperText: 'Cada uno da ${formatQty(item.unitsPerParent ?? 0)} de ${item.name}',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: depositoCodigo, label: Text('Depósito')),
                  ButtonSegment(value: vehiculoCodigo, label: Text('Vehículo')),
                ],
                selected: {location},
                onSelectionChanged: (v) => setLocal(() => location = v.first),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Fraccionar')),
          ],
        ),
      ),
    );
    // Los controladores no se liberan acá: el diálogo todavía se está cerrando.
    final n = parseQty(count.text);
    if (ok != true) return;
    if (n == null || n <= 0) {
      _snack('Escribí cuántos abrís (mayor que 0).');
      return;
    }
    try {
      final outcome = await runStockOp(
        _client,
        rpc: 'stock_fraccionar',
        args: {'p_producto_id': item.id, 'p_origenes': n, 'p_ubicacion': location},
        description: 'Fraccionar ${formatQty(n)} × ${_name(item.parentId)}',
      );
      _snack(outcome.savedOffline
          ? 'Sin señal: quedó guardado y se envía solo.'
          : 'Listo: +${formatQty(n * (item.unitsPerParent ?? 0))} de ${item.name}.');
      await _load();
    } catch (error) {
      _snack(stockErrorText(error));
    }
  }

  /// De qué producto sale este (y cuántos salen de uno).
  Future<void> _configureFraction(StockItem item) async {
    final search = TextEditingController();
    final units = TextEditingController(
      text: item.unitsPerParent == null ? '' : formatQty(item.unitsPerParent!),
    );
    String? parentId = item.parentId;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) {
          final options = _items
              .where((i) => i.id != item.id && i.parentId == null)
              .where((i) => coincideBusqueda(search.text, [i.name, i.code]))
              .take(40)
              .toList();
          return AlertDialog(
            title: Text('¿De qué producto sale ${item.name}?'),
            content: SizedBox(
              width: 480,
              height: 420,
              child: Column(
                children: [
                  TextField(
                    controller: search,
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Buscar el producto de origen...',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setLocal(() {}),
                  ),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final o in options)
                          ListTile(
                            dense: true,
                            title: Text(o.name),
                            selected: o.id == parentId,
                            trailing: o.id == parentId ? const Icon(Icons.check) : null,
                            onTap: () => setLocal(() => parentId = o.id),
                          ),
                      ],
                    ),
                  ),
                  TextField(
                    controller: units,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Cuántos ${item.name} salen de uno',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              if (item.parentId != null)
                TextButton(
                  onPressed: () => Navigator.pop(context, 'quitar'),
                  child: const Text('No es fraccionado'),
                ),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
              FilledButton(onPressed: () => Navigator.pop(context, 'guardar'), child: const Text('Guardar')),
            ],
          );
        },
      ),
    );
    final n = parseQty(units.text);
    if (result == null) return;
    if (result == 'guardar' && (parentId == null || n == null || n <= 1)) {
      _snack('Elegí el producto de origen y cuántos salen de uno (más de 1).');
      return;
    }
    try {
      await _client.rpc('stock_configurar_fraccion', params: {
        'p_producto_id': item.id,
        'p_origen_id': result == 'quitar' ? null : parentId,
        'p_unidades': result == 'quitar' ? null : n,
      });
      await _load();
    } catch (error) {
      _snack(stockErrorText(error));
    }
  }

  List<StockItem> get _visible {
    return _items.where((i) {
      if (!coincideBusqueda(_search.text, [i.name, i.code])) {
        return false;
      }
      return switch (_filter) {
        _Filter.controlled => i.controlled && !i.onDemand,
        _Filter.onDemand => i.onDemand || !i.controlled,
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
    final visible = pairLooseWithClosed(
      _visible,
      _items,
      addLoose: _filter == _Filter.controlled || _filter == _Filter.all,
    );
    final controlled = _items.where((i) => i.controlled && !i.onDemand).length;
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
                : '$controlled se tienen en el depósito · ${_items.length - controlled} se compran a pedido',
            style: const TextStyle(color: AppColors.gris),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final f in _Filter.values)
                ChoiceChip(
                  label: Text(switch (f) {
                    _Filter.controlled => 'Se tienen',
                    _Filter.onDemand => 'Se compran a pedido',
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
              margin: item.parentId != null && visible.any((v) => v.id == item.parentId)
                  ? const EdgeInsets.only(left: 28, top: 2, bottom: 6, right: 4)
                  : null,
              child: ListTile(
                leading: item.parentId != null && visible.any((v) => v.id == item.parentId)
                    ? const Icon(Icons.subdirectory_arrow_right)
                    : null,
                title: Text(item.name),
                subtitle: Text(
                  '${item.onDemand || !item.controlled ? '${item.category} · se compra a pedido' : item.category}'
                  '${item.parentId == null ? '' : '\nSuelto de ${_name(item.parentId)} (1 → ${formatQty(item.unitsPerParent ?? 0)})'}'
                  '${[for (final c in _items) if (c.parentId == item.id) '\n${looseSummary(item, c)}'].join()}',
                ),
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

  /// Poner, cambiar o sacar el preventista del viaje abierto (por si se confirmó sin elegirlo).
  Future<void> _changeSeller() async {
    final tripId = _vehicle.tripId;
    if (tripId == null) return;
    if (_sellerNames.isEmpty) {
      _snack('No se pudo traer la lista de preventistas. Probá de nuevo.');
      return;
    }
    Widget option(String value, String label) => SimpleDialogOption(
      onPressed: () => Navigator.pop(context, value),
      child: Row(
        children: [
          Icon(
            (value.isEmpty ? null : value) == _vehicle.sellerId
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(label)),
        ],
      ),
    );
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('¿Con quién sale el vehículo?'),
        children: [
          for (final e in _sellerNames.entries) option(e.key, e.value),
          option('', 'Nadie / reparto'),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    final sellerId = picked.isEmpty ? null : picked;
    if (sellerId == _vehicle.sellerId) return;
    try {
      await _client.rpc(
        'stock_viaje_preventista',
        params: {'p_viaje_id': tripId, 'p_preventista_id': sellerId},
      );
      _snack(sellerId == null
          ? 'Listo: el viaje quedó sin preventista.'
          : 'Listo: el viaje sale con ${_sellerNames[sellerId]}.');
      await _load();
    } catch (error) {
      _snack(isUncertainRequestError(error)
          ? 'Sin señal: probá de nuevo cuando haya conexión.'
          : stockErrorText(error));
    }
  }

  Widget _tripCard() {
    final open = _vehicle.tripOpen;
    final seller = _vehicle.sellerId == null ? null : _sellerNames[_vehicle.sellerId];
    final units = _vehicle.lines.values.fold<double>(0, (s, l) => s + (l.inVehicle > 0 ? l.inVehicle : 0));
    return Card(
      color: open ? Tonos.of(context).exitoFondo : null,
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
                  OutlinedButton.icon(
                    icon: const Icon(Icons.person_outline),
                    label: Text(seller == null || seller.isEmpty ? 'Elegir preventista' : 'Cambiar preventista'),
                    onPressed: _changeSeller,
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
