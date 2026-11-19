import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_theme.dart';
import '../../core/desktop_records.dart';
import 'stock_data.dart';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/app_config.dart';
import 'product_summary.dart';

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

  // Carga del vehículo como lista para tachar (reemplaza el papel). Queda guardada en el
  // teléfono hasta confirmar, aunque se cierre la pantalla.
  final _loaded = <String>{};
  bool _onlyPending = false;

  /// Cantidad propuesta (pedidos a entregar o última carga): si se borra, vuelve esta.
  final _proposed = <String, String>{};

  /// Filas que siguen a la vista con "Solo con cantidad" aunque se borre el número al editarlo.
  final _kept = <String>{};

  /// Arriba solo queda la barra del avance; lo demás se abre con "Opciones".
  bool _optionsOpen = true;
  static const _zebra = Color(0xFFE6F1FB);
  static const _zebraText = Color(0xFF0C447C);
  static const _fluor = Color(0xFFFFF176);
  static const _fluorEdge = Color(0xFFF2D600);
  String get _draftKey => appConfig.localPreferenceKey('carga_vehiculo_borrador');

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
    if (_kind == StockFormKind.load) {
      _loadSellers();
      _restoreDraft();
    }
  }

  @override
  void dispose() {
    _closeProposeSnack();
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

  Future<void> _restoreDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_draftKey);
      if (raw == null) return;
      final data = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final quantities = Map<String, dynamic>.from(data['cantidades'] as Map? ?? const {});
      final loaded = List<String>.from(data['cargados'] as List? ?? const []);
      final proposed = Map<String, dynamic>.from(data['propuestas'] as Map? ?? const {});
      bool known(String id) => widget.items.any((i) => i.id == id);
      if (!mounted) return;
      setState(() {
        for (final e in proposed.entries) {
          if (!known(e.key)) continue;
          _proposed[e.key] = e.value.toString();
          _controller(e.key).text = e.value.toString();
          _kept.add(e.key);
        }
        for (final e in quantities.entries) {
          if (!known(e.key)) continue;
          _controller(e.key).text = e.value.toString();
          _kept.add(e.key);
        }
        _loaded.addAll(loaded.where(known));
        if (quantities.isNotEmpty) {
          _onlyFilled = true;
          _optionsOpen = false;
        }
      });
    } catch (_) {}
  }

  Future<void> _saveDraft() async {
    if (_kind != StockFormKind.load) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final quantities = {
        for (final e in _qty.entries)
          if (e.value.text.trim().isNotEmpty) e.key: e.value.text.trim(),
      };
      if (quantities.isEmpty && _loaded.isEmpty && _proposed.isEmpty) {
        await prefs.remove(_draftKey);
      } else {
        await prefs.setString(
          _draftKey,
          jsonEncode({'cantidades': quantities, 'cargados': _loaded.toList(), 'propuestas': _proposed}),
        );
      }
    } catch (_) {}
  }

  Future<void> _clearDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_draftKey);
    } catch (_) {}
  }

  void _toggleLoaded(String id) {
    setState(() {
      if (!_loaded.remove(id)) _loaded.add(id);
    });
    _saveDraft();
  }

  bool _hasText(String id) => _qty[id]?.text.trim().isNotEmpty ?? false;

  /// Con cantidad para mandar. Al cargar, 0 quiere decir "no se carga".
  bool _filled(String id) {
    final text = _qty[id]?.text.trim() ?? '';
    if (text.isEmpty) return false;
    return !(_kind == StockFormKind.load && parseQty(text) == 0);
  }

  /// Al tocar la cantidad queda toda seleccionada: se escribe la nueva sin borrar antes.
  void _selectAll(String id) {
    final c = _controller(id);
    c.selection = TextSelection(baseOffset: 0, extentOffset: c.text.length);
  }

  /// Si se dejó vacía, vuelve la cantidad del pedido.
  void _restoreIfEmpty(String id) {
    if (_kind != StockFormKind.load || _hasText(id)) return;
    final original = _proposed[id];
    if (original == null || !mounted) return;
    setState(() => _controller(id).text = original);
    _saveDraft();
  }

  void _quantityChanged(String id) {
    setState(() {
      if (_hasText(id)) _kept.add(id);
    });
    _saveDraft();
  }

  /// Lo que falta subir, para mandar por WhatsApp a quien ayuda a cargar.
  String _pendingText() {
    final lines = [
      for (final item in pairLooseWithClosed(widget.items, widget.items))
        if (_filled(item.id) && !_loaded.contains(item.id)) '• ${_qty[item.id]!.text.trim()} × ${item.name}',
    ];
    return lines.isEmpty
        ? 'Ya está todo cargado en el vehículo.'
        : 'Falta cargar en el vehículo (${lines.length}):\n${lines.join('\n')}';
  }

  Future<void> _sharePending() async {
    final text = _pendingText();
    try {
      await SharePlus.instance.share(ShareParams(text: text));
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
      _snack('Lista copiada: pegala en WhatsApp.');
    }
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
        _kept.add(entry.key);
        if (_kind == StockFormKind.load) _proposed[entry.key] = formatQty(entry.value);
      }
      _onlyFilled = true;
      if (_kind == StockFormKind.load) _optionsOpen = false;
    });
    _saveDraft();
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

  /// Aviso de "PROPONER TODO" abierto (se cierra con la X, solo o al salir de la pantalla).
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _proposeSnack;

  void _closeProposeSnack() {
    final snack = _proposeSnack;
    _proposeSnack = null;
    snack?.close();
  }

  /// "Pedidos a entregar": solo lo que falta subir (lo demás ya está arriba del vehículo).
  Future<void> _proposeForDeliveries() async {
    try {
      final all = await fetchPendingDeliveries(_client);
      if (!mounted) return;
      if (all.isEmpty) {
        _snack('No hay pedidos facturados para entregar.');
        return;
      }
      final missing = stillToLoad(all, widget.items);
      final partial = missing.length != all.length || missing.entries.any((e) => e.value < (all[e.key] ?? 0));
      if (missing.isNotEmpty) _fill(missing);
      if (!partial) return;
      _closeProposeSnack();
      final snack = ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 10),
          showCloseIcon: true,
          content: Text(missing.isEmpty
              ? 'Ya está todo arriba del vehículo para los pedidos a entregar.'
              : 'Propuesto solo lo que falta subir: lo demás ya está en el vehículo.'),
          action: SnackBarAction(label: 'PROPONER TODO', onPressed: () => _fill(all)),
        ),
      );
      _proposeSnack = snack;
      snack.closed.then((_) {
        if (identical(_proposeSnack, snack)) _proposeSnack = null;
      });
      // Con botón, el aviso no se va solo: se cierra a los 10 segundos o al salir.
      Future.delayed(const Duration(seconds: 10), () {
        if (identical(_proposeSnack, snack)) _closeProposeSnack();
      });
    } catch (error) {
      _snack(stockErrorText(error));
    }
  }

  List<StockItem> get _visible {
    final text = _normalize(_search.text);
    final base = widget.items.where((item) {
      if (widget.onlyIds != null && !widget.onlyIds!.contains(item.id)) return false;
      if (text.isNotEmpty &&
          !_normalize(item.name).contains(text) &&
          !item.code.toLowerCase().contains(text)) {
        return false;
      }
      final filled = _hasText(item.id);
      final kept = filled || _kept.contains(item.id);
      if (_onlyFilled && text.isEmpty && !kept) return false;
      if (_onlyPending && text.isEmpty &&
          (!kept || _loaded.contains(item.id) || (filled && !_filled(item.id)))) {
        return false;
      }
      if (_kind == StockFormKind.count && !_allProducts && !item.controlled && !filled &&
          text.isEmpty && widget.onlyIds == null) {
        return false;
      }
      return true;
    }).toList();
    // Cada suelto justo debajo de su cerrado; al contar, aparecen aunque sean "a pedido".
    return pairLooseWithClosed(base, widget.items, addLoose: _kind == StockFormKind.count);
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
      if (q == null) return null;
      if (q == 0 && _kind == StockFormKind.load) continue;
      if (!_zeroAllowed && q == 0) return null;
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
    if (_kind == StockFormKind.load) {
      final missing = lines.where((l) => !_loaded.contains(l['producto_id'])).length;
      if (missing > 0) {
        final go = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Faltan marcar'),
            content: Text(
              'Quedan $missing ${missing == 1 ? 'producto' : 'productos'} sin marcar. '
              '¿Confirmar la carga igual?',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Volver')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirmar')),
            ],
          ),
        );
        if (go != true || !mounted) return;
      }
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
    if (_kind == StockFormKind.load) await _clearDraft();
    if (!mounted) return;
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
    if (_kind == StockFormKind.load) return _buildLoad();
    final visible = _visible;
    final filled = widget.items.where((i) => _filled(i.id)).length;
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
      bottomNavigationBar: _confirmBar(filled),
    );
  }

  Widget _confirmBar(int filled) => SafeArea(
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
  );

  /// Cargar el vehículo: lista a pantalla completa como el resumen de productos, con el color
  /// del stock del depósito y lo cargado resaltado en flúor (como el marcador sobre el papel).
  Widget _buildLoad() {
    final visible = _visible;
    final status = _loadStatus();
    final filled = widget.items.where((i) => _filled(i.id)).length;
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: DesktopForm(
        child: Column(
          children: [
            _loadBar(),
            if (_optionsOpen)
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.5),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
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
                            onSelected: (v) => setState(() {
                              _onlyFilled = v;
                              _kept
                                ..clear()
                                ..addAll(widget.items.where((i) => _hasText(i.id)).map((i) => i.id));
                            }),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            const Divider(height: 1),
            Expanded(
              child: visible.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No hay productos para mostrar. Abrí "Opciones" para buscar o sacar el filtro.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 12),
                      itemCount: visible.length,
                      itemBuilder: (context, index) => _loadRow(visible[index], index, status[visible[index].id]),
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _confirmBar(filled),
    );
  }

  /// Si alcanza lo del depósito para lo que se va a cargar (abriendo cajas si hace falta).
  Map<String, SummaryRow> _loadStatus() {
    final lines = <SummaryLine>[];
    for (final item in widget.items) {
      final q = parseQty(_qty[item.id]?.text ?? '');
      if (q != null && q > 0) lines.add(SummaryLine(item.id, item.name, q));
    }
    if (lines.isEmpty) return const {};
    final deposit = {for (final i in widget.items) i.id: i.depositOnly()};
    return {for (final r in evaluateSummary(lines, deposit)) r.line.productId!: r};
  }

  /// Barra fija: "3 de 9 cargados", "Falta cargar", compartir y "Opciones".
  Widget _loadBar() {
    final filled = widget.items.where((i) => _filled(i.id)).toList();
    final done = filled.where((i) => _loaded.contains(i.id)).length;
    final complete = filled.isNotEmpty && done == filled.length;
    return Container(
      color: const Color(0xFFF4F4F2),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    filled.isEmpty ? 'Escribí qué cargar' : '$done de ${filled.length} cargados',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: complete ? AppColors.verde : null,
                    ),
                  ),
                ),
                if (filled.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  LinearProgressIndicator(
                    value: done / filled.length,
                    minHeight: 4,
                    color: complete ? AppColors.verde : _fluorEdge,
                    backgroundColor: Colors.black12,
                  ),
                ],
              ],
            ),
          ),
          if (filled.isNotEmpty) ...[
            const SizedBox(width: 6),
            FilterChip(
              visualDensity: VisualDensity.compact,
              label: const Text('Falta cargar'),
              selected: _onlyPending,
              onSelected: (v) => setState(() => _onlyPending = v),
            ),
            IconButton(
              tooltip: 'Compartir lista',
              icon: const Icon(Icons.share),
              onPressed: _sharePending,
            ),
          ],
          TextButton.icon(
            icon: Icon(_optionsOpen ? Icons.expand_less : Icons.tune),
            label: const Text('Opciones'),
            onPressed: () => setState(() {
              _optionsOpen = !_optionsOpen;
              if (!_optionsOpen && _search.text.isNotEmpty) _search.clear();
            }),
          ),
        ],
      ),
    );
  }

  Widget _loadRow(StockItem item, int index, SummaryRow? st) {
    final closed = item.parentId == null
        ? null
        : widget.items.where((i) => i.id == item.parentId).firstOrNull;
    final loaded = _loaded.contains(item.id);
    final filled = _filled(item.id);
    final zebra = !loaded && index.isOdd;
    final textColor = zebra ? _zebraText : Colors.black87;
    String have(double v) => formatQty(v < 0 ? 0 : v);
    final badge = st == null
        ? null
        : switch (st.state) {
            SummaryState.enough => 'Hay ${have(st.have ?? 0)}',
            SummaryState.open => 'Abrir ${formatQty(st.openParents)} × ${st.parentName}',
            SummaryState.missing => st.openParents > 0
                ? 'Abrir ${formatQty(st.openParents)} × ${st.parentName} · faltan ${formatQty(st.missing)}'
                : 'Faltan ${formatQty(st.missing)} · hay ${have(st.have ?? 0)}',
            SummaryState.onDemand => 'A pedido',
            SummaryState.unknown => null,
          };
    final skipped = _hasText(item.id) && !filled;
    final original = _proposed[item.id];
    final changed = original != null && _qty[item.id]!.text.trim() != original;
    final info = skipped
        ? 'No se carga'
        : !item.controlled
        ? 'A pedido'
        : [
            'Depósito ${formatQty(item.deposit)}',
            if (closed != null && closed.controlled) '${closed.name}: ${formatQty(closed.deposit)}',
          ].join(' · ');
    return Material(
      color: loaded ? _fluor : (zebra ? _zebra : Colors.white),
      child: InkWell(
        onTap: filled || loaded ? () => _toggleLoaded(item.id) : null,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: loaded ? _fluorEdge : Colors.transparent, width: 6),
            ),
          ),
          padding: EdgeInsets.fromLTRB(closed != null ? 18 : 0, 3, 10, 3),
          child: Row(
            children: [
              Checkbox(
                value: loaded,
                visualDensity: VisualDensity.compact,
                onChanged: filled || loaded ? (_) => _toggleLoaded(item.id) : null,
              ),
              if (closed != null)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.subdirectory_arrow_right, size: 18, color: AppColors.gris),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.name, style: TextStyle(fontWeight: FontWeight.w600, color: textColor)),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (badge != null && st != null)
                          summaryBadge(badge, st.state)
                        else
                          Text(info, style: TextStyle(fontSize: 12, color: zebra ? _zebraText : AppColors.gris)),
                        if (changed)
                          Text(
                            'Pedidos: $original',
                            style: TextStyle(fontSize: 12, color: zebra ? _zebraText : AppColors.gris),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 64,
                child: Focus(
                  skipTraversal: true,
                  onFocusChange: (focused) {
                    if (!focused) _restoreIfEmpty(item.id);
                  },
                  child: TextField(
                    key: ValueKey('cantidad-${item.id}'),
                    controller: _controller(item.id),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: _proposed[item.id] ?? 'Cant.',
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      border: const OutlineInputBorder(),
                    ),
                    onTap: () => _selectAll(item.id),
                    onChanged: (_) => _quantityChanged(item.id),
                    onSubmitted: (_) => _restoreIfEmpty(item.id),
                  ),
                ),
              ),
            ],
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
                onPressed: _proposeForDeliveries,
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
    final closed = item.parentId == null
        ? null
        : widget.items.where((i) => i.id == item.parentId).firstOrNull;
    final hasLoose = widget.items.any((i) => i.parentId == item.id);
    final info = [
      if (closed != null) 'Sueltos de ${closed.name}',
      if (hasLoose) 'Cerrados',
      !item.controlled
          ? 'A pedido'
          : 'Depósito ${formatQty(item.deposit)} · Vehículo ${formatQty(item.vehicle)}',
    ].join(' · ');
    return Card(
      margin: closed != null ? const EdgeInsets.only(left: 24, top: 2, bottom: 6, right: 4) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            if (closed != null)
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Icon(Icons.subdirectory_arrow_right, size: 20),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
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
                onTap: () => _selectAll(item.id),
                onChanged: (_) => _quantityChanged(item.id),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
