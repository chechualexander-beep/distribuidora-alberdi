import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_theme.dart';
import '../../core/desktop_records.dart';
import 'stock_data.dart';

enum StockFormKind { count, load, unload, purchase, closeTrip }

/// Una sola pantalla para contar, cargar o bajar el vehículo, anotar una compra y cerrar el
/// viaje: lista de productos con la cantidad de cada uno.
class StockFormPage extends StatefulWidget {
  const StockFormPage({
    super.key,
    required this.kind,
    required this.items,
    this.tripId,
    this.onlyIds,
    this.client,
    this.runner,
    this.initialLocation,
  });

  final StockFormKind kind;
  final List<StockItem> items;
  final String? tripId;

  /// Mostrar solo estos productos (por ejemplo, contar uno solo).
  final Set<String>? onlyIds;
  final SupabaseClient? client;

  /// Solo para pruebas.
  final StockOpRunner? runner;

  /// Depósito o vehículo al abrir (compra desde el reparto: vehículo).
  final String? initialLocation;

  @override
  State<StockFormPage> createState() => _StockFormPageState();
}

class _StockFormPageState extends State<StockFormPage> {
  SupabaseClient get _client => widget.client ?? Supabase.instance.client;
  final _qty = <String, TextEditingController>{};
  final _cost = <String, TextEditingController>{};
  final _search = TextEditingController();
  final _supplier = TextEditingController();
  late String _location =
      widget.initialLocation ??
      (widget.kind == StockFormKind.purchase && widget.tripId != null ? vehiculoCodigo : depositoCodigo);
  bool _onlyFilled = false;
  bool _allProducts = false;
  bool _unloadAll = false;
  bool _updateCost = false;
  bool _saving = false;
  String? _sellerId;
  List<StockRow> _sellers = const [];

  StockFormKind get _kind => widget.kind;

  @override
  void initState() {
    super.initState();
    if (_kind == StockFormKind.closeTrip) {
      for (final item in widget.items) {
        if (item.controlled && item.vehicle != 0) {
          _controller(item.id).text = formatQty(item.vehicle < 0 ? 0 : item.vehicle);
        }
      }
      _onlyFilled = true;
    }
    if (_kind == StockFormKind.load) _loadSellers();
  }

  @override
  void dispose() {
    for (final c in [..._qty.values, ..._cost.values, _search, _supplier]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSellers() async {
    try {
      final sellers = await fetchSellers(_client);
      if (mounted) setState(() => _sellers = sellers);
    } catch (_) {}
  }

  TextEditingController _controller(String id) => _qty.putIfAbsent(id, TextEditingController.new);
  /// El costo viene precargado con el actual: si pagaste lo mismo, no hay que escribirlo.
  TextEditingController _costController(StockItem item) => _cost.putIfAbsent(
    item.id,
    () => TextEditingController(text: item.cost > 0 ? formatQty(item.cost) : ''),
  );

  String get _title => switch (_kind) {
    StockFormKind.count => 'Contar stock',
    StockFormKind.load => 'Cargar vehículo',
    StockFormKind.unload => 'Bajar al depósito',
    StockFormKind.purchase => 'Anotar compra',
    StockFormKind.closeTrip => 'Cerrar viaje',
  };

  String get _help => switch (_kind) {
    StockFormKind.count =>
      'Escribí lo que contaste. Los productos "a pedido" que cuentes pasan a "con stock".',
    StockFormKind.load =>
      'Lo que subís al vehículo sale del depósito. Los productos "a pedido" no se descuentan.',
    StockFormKind.unload => 'Lo que bajás del vehículo vuelve al depósito.',
    StockFormKind.purchase =>
      'Lo comprado entra al stock (un producto "a pedido" pasa a llevar stock). '
          'El costo viene cargado: cambialo solo si pagaste otro precio.',
    StockFormKind.closeTrip =>
      'Contá lo que sobró en el vehículo y corregí lo que no coincida. '
          'La app compara con lo que debería quedar.',
  };

  bool get _zeroAllowed => _kind == StockFormKind.count || _kind == StockFormKind.closeTrip;

  void _fill(Map<String, double> values) {
    setState(() {
      for (final entry in values.entries) {
        if (!widget.items.any((i) => i.id == entry.key)) continue;
        _controller(entry.key).text = formatQty(entry.value);
      }
      _onlyFilled = true;
    });
  }

  Future<void> _propose(Future<Map<String, double>> Function(SupabaseClient) source, String empty) async {
    try {
      final values = await source(_client);
      if (!mounted) return;
      if (values.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(empty)));
        return;
      }
      _fill(values);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(stockErrorText(error))));
      }
    }
  }

  List<StockItem> get _visible {
    final text = _normalize(_search.text);
    return widget.items.where((item) {
      if (widget.onlyIds != null && !widget.onlyIds!.contains(item.id)) return false;
      if (text.isNotEmpty &&
          !_normalize(item.name).contains(text) &&
          !item.code.toLowerCase().contains(text)) {
        return false;
      }
      final filled = (_qty[item.id]?.text.trim().isNotEmpty ?? false);
      if (_onlyFilled && text.isEmpty && !filled) return false;
      if (_kind == StockFormKind.count && !_allProducts && !item.controlled && !filled &&
          text.isEmpty && widget.onlyIds == null) {
        return false;
      }
      return true;
    }).toList();
  }

  static String _normalize(String text) => text
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ñ', 'n')
      .trim();

  /// Productos con cantidad escrita. Null si alguna es inválida.
  List<Map<String, dynamic>>? _lines() {
    final lines = <Map<String, dynamic>>[];
    for (final item in widget.items) {
      final text = _qty[item.id]?.text ?? '';
      if (text.trim().isEmpty) continue;
      final q = parseQty(text);
      if (q == null || (!_zeroAllowed && q == 0)) return null;
      final line = <String, dynamic>{'producto_id': item.id, 'cantidad': q};
      if (_kind == StockFormKind.purchase) {
        final costText = _costController(item).text;
        if (costText.trim().isNotEmpty) {
          final cost = parseQty(costText);
          if (cost == null) return null;
          line['costo_unitario'] = cost;
        }
      }
      lines.add(line);
    }
    return lines;
  }

  String _name(String id) =>
      widget.items.where((i) => i.id == id).map((i) => i.name).firstOrNull ?? 'Producto';

  Future<void> _confirm() async {
    final lines = _lines();
    if (lines == null) {
      _snack(_zeroAllowed
          ? 'Revisá las cantidades: números de 0 en adelante.'
          : 'Revisá las cantidades: tienen que ser mayores que 0.');
      return;
    }
    if (lines.isEmpty && !(_kind == StockFormKind.closeTrip)) {
      _snack('Escribí la cantidad de al menos un producto.');
      return;
    }
    final total = lines.fold<double>(
      0,
      (sum, l) => sum + stockNum(l['cantidad']) * stockNum(l['costo_unitario']),
    );
    final (rpc, args, description) = switch (_kind) {
      StockFormKind.count => (
        'stock_contar',
        <String, dynamic>{'p_ubicacion': _location, 'p_items': lines},
        'Conteo (${lines.length} productos)',
      ),
      StockFormKind.load => (
        'stock_cargar_vehiculo',
        <String, dynamic>{'p_items': lines, 'p_preventista_id': _sellerId},
        'Carga del vehículo (${lines.length} productos)',
      ),
      StockFormKind.unload => (
        'stock_bajar_vehiculo',
        <String, dynamic>{'p_items': lines},
        'Bajada al depósito (${lines.length} productos)',
      ),
      StockFormKind.purchase => (
        'stock_registrar_compra',
        <String, dynamic>{
          'p_ubicacion': _location,
          'p_items': lines,
          'p_proveedor': _supplier.text.trim().isEmpty ? null : _supplier.text.trim(),
          'p_actualizar_costo': _updateCost,
        },
        'Compra${_supplier.text.trim().isEmpty ? '' : ' · ${_supplier.text.trim()}'}',
      ),
      StockFormKind.closeTrip => (
        'stock_cerrar_viaje',
        <String, dynamic>{
          'p_viaje_id': widget.tripId,
          'p_conteo': lines.isEmpty ? null : lines,
          'p_bajar': _unloadAll,
        },
        'Cierre del viaje',
      ),
    };
    setState(() => _saving = true);
    final StockOpOutcome outcome;
    try {
      final runner = widget.runner;
      outcome = runner != null
          ? await runner(rpc, args)
          : await runStockOp(
              _client,
              rpc: rpc,
              args: args,
              description: description,
              total: total,
            );
    } catch (error) {
      if (mounted) setState(() => _saving = false);
      _snack(stockErrorText(error));
      return;
    }
    if (!mounted) return;
    // Sin la ruedita girando detrás del resultado.
    setState(() => _saving = false);
    await _showResult(outcome.result);
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _showResult(Map<String, dynamic>? result) async {
    final lines = <String>[];
    if (result == null) {
      lines.add(
        'No hay señal: quedó guardado en el teléfono y se envía solo cuando vuelva la conexión. '
        'Lo ves en "Pendientes de enviar".',
      );
    } else {
      switch (_kind) {
        case StockFormKind.count:
          final n = stockNum(result['productos']).round();
          lines.add('Listo: ${n == 1 ? '1 producto contado' : '$n productos contados'}.');
          final nuevos = stockNum(result['nuevos_con_stock']).round();
          if (nuevos > 0) lines.add('$nuevos pasaron a "con stock".');
          for (final d in (result['diferencias'] as List? ?? const [])) {
            final m = Map<String, dynamic>.from(d as Map);
            lines.add(
              '${_name(m['producto_id'].toString())}: había ${formatQty(stockNum(m['antes']))}, '
              'contaste ${formatQty(stockNum(m['contado']))}',
            );
          }
        case StockFormKind.load:
          lines.add(result['viaje_nuevo'] == true
              ? 'Vehículo cargado. Se abrió el viaje.'
              : 'Vehículo cargado (se sumó al viaje abierto).');
          final sinDescontar = stockNum(result['a_pedido']).round();
          if (sinDescontar > 0) lines.add('$sinDescontar productos "a pedido" no se descontaron del depósito.');
        case StockFormKind.unload:
          lines.add('Listo: ${result['movidos']} productos volvieron al depósito.');
        case StockFormKind.purchase:
          lines.add('Compra anotada.');
          if (stockNum(result['total']) > 0) {
            lines.add('Total: \$${formatQty(stockNum(result['total']))}');
          }
          final pasaron = stockNum(result['nuevos_con_stock']).round();
          if (pasaron > 0) lines.add('$pasaron productos "a pedido" pasaron a llevar stock.');
        case StockFormKind.closeTrip:
          final diffs = (result['diferencias'] as List? ?? const []);
          lines.add(diffs.isEmpty ? 'Viaje cerrado: todo coincide.' : 'Viaje cerrado. Diferencias:');
          for (final d in diffs) {
            final m = Map<String, dynamic>.from(d as Map);
            final diff = stockNum(m['diferencia']);
            lines.add(
              '${m['nombre']}: ${diff < 0 ? 'faltan ${formatQty(-diff)}' : 'sobran ${formatQty(diff)}'} '
              '(debía quedar ${formatQty(stockNum(m['esperado']))}, hay ${formatQty(stockNum(m['contado']))})',
            );
          }
          lines.add('Ventas del viaje: ${result['ventas']}.');
          final pending = stockNum(result['pendientes_de_entrega']).round();
          if (pending > 0) lines.add('Atención: $pending ventas del viaje siguen sin entregar.');
          if (stockNum(result['bajados']) > 0) {
            lines.add('${result['bajados']} productos volvieron al depósito.');
          }
      }
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(
          result == null ? Icons.cloud_upload_outlined : Icons.check_circle_outline,
          size: 44,
        ),
        title: Text(result == null ? 'Guardado en el teléfono' : _title),
        content: SingleChildScrollView(child: Text(lines.join('\n'))),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('ACEPTAR')),
        ],
      ),
    );
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final filled = _qty.values.where((c) => c.text.trim().isNotEmpty).length;
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: DesktopForm(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(_help, style: const TextStyle(color: AppColors.gris)),
                  const SizedBox(height: 8),
                  ..._options(),
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
                  Wrap(
                    spacing: 8,
                    children: [
                      FilterChip(
                        label: const Text('Solo con cantidad'),
                        selected: _onlyFilled,
                        onSelected: (v) => setState(() => _onlyFilled = v),
                      ),
                      if (_kind == StockFormKind.count && widget.onlyIds == null)
                        FilterChip(
                          label: const Text('Incluir "a pedido"'),
                          selected: _allProducts,
                          onSelected: (v) => setState(() => _allProducts = v),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: visible.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No hay productos para mostrar. Buscá uno o sacá el filtro.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      itemCount: visible.length,
                      itemBuilder: (context, index) => _row(visible[index]),
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: _saving ? null : _confirm,
            icon: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                _kind == StockFormKind.closeTrip
                    ? 'CERRAR VIAJE'
                    : 'CONFIRMAR ($filled ${filled == 1 ? 'producto' : 'productos'})',
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _options() {
    switch (_kind) {
      case StockFormKind.count:
      case StockFormKind.purchase:
        return [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: depositoCodigo, label: Text('Depósito'), icon: Icon(Icons.warehouse_outlined)),
              ButtonSegment(value: vehiculoCodigo, label: Text('Vehículo'), icon: Icon(Icons.local_shipping_outlined)),
            ],
            selected: {_location},
            onSelectionChanged: (v) => setState(() => _location = v.first),
          ),
          if (_kind == StockFormKind.purchase) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _supplier,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Proveedor o comercio (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Actualizar el costo de los productos'),
              value: _updateCost,
              onChanged: (v) => setState(() => _updateCost = v),
            ),
          ],
        ];
      case StockFormKind.load:
        return [
          DropdownButtonFormField<String?>(
            initialValue: _sellerId,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Sale con (preventista, opcional)',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Nadie / reparto')),
              for (final s in _sellers)
                DropdownMenuItem<String?>(
                  value: s['id'].toString(),
                  child: Text('${s['nombre'] ?? ''} ${s['apellido'] ?? ''}'.trim()),
                ),
            ],
            onChanged: (v) => setState(() => _sellerId = v),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('Pedidos a entregar'),
                onPressed: () => _propose(fetchPendingDeliveries, 'No hay pedidos facturados para entregar.'),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.replay),
                label: const Text('Repetir la última carga'),
                onPressed: () => _propose(fetchLastLoad, 'Todavía no hay cargas anteriores.'),
              ),
            ],
          ),
        ];
      case StockFormKind.unload:
        return [
          OutlinedButton.icon(
            icon: const Icon(Icons.select_all),
            label: const Text('Todo lo del vehículo'),
            onPressed: () => _fill({
              for (final i in widget.items)
                if (i.controlled && i.vehicle > 0) i.id: i.vehicle,
            }),
          ),
        ];
      case StockFormKind.closeTrip:
        return [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Bajar todo lo que sobró al depósito'),
            subtitle: const Text('Si no, queda arriba para el próximo viaje.'),
            value: _unloadAll,
            onChanged: (v) => setState(() => _unloadAll = v),
          ),
        ];
    }
  }

  Widget _row(StockItem item) {
    final info = !item.controlled
        ? 'A pedido'
        : 'Depósito ${formatQty(item.deposit)} · Vehículo ${formatQty(item.vehicle)}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(
                    _kind == StockFormKind.closeTrip && item.controlled
                        ? 'Debería quedar ${formatQty(item.vehicle)}'
                        : info,
                    style: TextStyle(
                      fontSize: 13,
                      color: item.negative ? AppColors.rojo : AppColors.gris,
                    ),
                  ),
                ],
              ),
            ),
            if (_kind == StockFormKind.purchase) ...[
              SizedBox(
                width: 96,
                child: TextField(
                  controller: _costController(item),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.end,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Costo c/u',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
            ],
            SizedBox(
              width: 84,
              child: TextField(
                controller: _controller(item.id),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.end,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Cantidad',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
