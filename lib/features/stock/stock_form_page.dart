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
import '../finance/finance_data.dart';
import '../finance/finance_forms.dart' show isoDate;
import 'package:distribuidora_alberdi/core/money_format.dart';
import '../../core/text_search.dart';

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
    this.reload,
  });

  final StockFormKind kind;
  final List<StockItem> items;
  final String? tripId;

  /// Mostrar solo estos productos (por ejemplo, contar uno solo).
  final Set<String>? onlyIds;
  final SupabaseClient? client;

  /// Solo para pruebas.
  final StockOpRunner? runner;

  /// Depósito o vehículo al abrir. En la compra, sin esto hay que elegirlo (no arranca en uno).
  final String? initialLocation;

  /// Vuelve a leer el stock (cargar y bajar trabajan siempre con el stock de este momento).
  final Future<List<StockItem>> Function()? reload;


  @override
  State<StockFormPage> createState() => _StockFormPageState();
}

class _StockFormPageState extends State<StockFormPage> {
  SupabaseClient get _client => widget.client ?? Supabase.instance.client;
  final _qty = <String, TextEditingController>{};
  final _cost = <String, TextEditingController>{};
  final _search = TextEditingController();
  final _supplier = TextEditingController();

  /// Con el teclado abierto (escribiendo cantidad o costo) se esconden las opciones de arriba
  /// para que se vean los productos; salvo que se esté escribiendo el proveedor.
  final _supplierFocus = FocusNode();
  // En la compra el lugar se elige siempre ('' = todavía no se eligió).
  late String _location =
      widget.initialLocation ?? (widget.kind == StockFormKind.purchase ? '' : depositoCodigo);

  /// Productos con su stock; cargar y bajar lo vuelven a leer con el botón de actualizar.
  late List<StockItem> _items = widget.items;
  DateTime _dataAt = DateTime.now();
  bool _reloading = false;

  /// Pedidos a entregar sin stock en el depósito (se ven, pero no se pueden subir).
  final _noStock = <String, double>{};

  /// Para el resultado: lo propuesto que quedó sin marcar (no se pasó).
  String? _leftNote;
  bool _onlyFilled = false;
  bool _allProducts = false;
  bool _unloadAll = false;
  bool _updateCost = false;

  // Compra: cómo se pagó (va a "Plata del negocio"). "nada" = no anotar el pago.
  String _payWith = efectivo;
  DateTime _due = DateTime.now().add(const Duration(days: 15));
  String? _payNote;
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
  String get _draftKey => appConfig.localPreferenceKey('carga_vehiculo_borrador');

  late StockFormKind _kind = widget.kind;

  /// Cargar o bajar: pasar mercadería de un lugar al otro.
  bool get _isTransfer => _kind == StockFormKind.load || _kind == StockFormKind.unload;

  /// Lo máximo que se puede pasar: lo que figura en el lugar de origen (al cargar un suelto,
  /// también las bolsas cerradas del depósito que se pueden abrir).
  double _maxFor(StockItem item) {
    if (_kind == StockFormKind.unload) return item.vehicle > 0 ? item.vehicle : 0.0;
    var max = item.deposit > 0 ? item.deposit : 0.0;
    final parent = item.parentId == null ? null : _items.where((i) => i.id == item.parentId).firstOrNull;
    final units = item.unitsPerParent ?? 0;
    if (parent != null && parent.controlled && units > 0 && parent.deposit > 0) {
      max += parent.deposit.floorToDouble() * units;
    }
    return max;
  }

  /// Lo marcado en flúor con su cantidad: es lo único que se pasa al confirmar.
  List<StockItem> get _marked =>
      _items.where((i) => _loaded.contains(i.id) && _filled(i.id)).toList();

  double get _markedUnits =>
      _marked.fold<double>(0, (s, i) => s + (parseQty(_qty[i.id]?.text ?? '') ?? 0));

  Future<void> _reload() async {
    final reload = widget.reload;
    if (reload == null || _reloading) return;
    setState(() => _reloading = true);
    try {
      final items = await reload();
      if (!mounted) return;
      setState(() {
        _items = items;
        _dataAt = DateTime.now();
      });
    } catch (error) {
      _snack('No se pudo actualizar: ${stockErrorText(error)}');
    } finally {
      if (mounted) setState(() => _reloading = false);
    }
  }

  /// Borra lo escrito, lo marcado y lo propuesto (y el borrador guardado).
  void _startOver() {
    setState(() {
      for (final c in _qty.values) {
        c.clear();
      }
      _loaded.clear();
      _proposed.clear();
      _kept.clear();
      _noStock.clear();
      _onlyFilled = false;
      _onlyPending = false;
    });
    _clearDraft();
  }

  /// ⇄ Cargar ↔ Bajar. Si hay algo escrito, pregunta antes (se borra).
  Future<void> _swapDirection() async {
    final dirty = _qty.values.any((c) => c.text.trim().isNotEmpty) || _loaded.isNotEmpty;
    if (dirty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(_kind == StockFormKind.load ? '¿Pasar a bajar al depósito?' : '¿Pasar a cargar el vehículo?'),
          content: const Text('Se borra lo que escribiste y marcaste.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Volver')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sí, dar vuelta')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    _startOver();
    setState(() {
      _kind = _kind == StockFormKind.load ? StockFormKind.unload : StockFormKind.load;
      _optionsOpen = true;
    });
    if (_kind == StockFormKind.load && _sellers.isEmpty) _loadSellers();
  }

  static String _today() {
    final d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _supplierFocus.addListener(() {
      if (mounted) setState(() {});
    });
    if (_kind == StockFormKind.closeTrip) {
      for (final item in _items) {
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
    _supplierFocus.dispose();
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
      // Un borrador de otro día no sirve: se descarta solo.
      if (data['fecha'] != _today()) {
        await prefs.remove(_draftKey);
        return;
      }
      final quantities = Map<String, dynamic>.from(data['cantidades'] as Map? ?? const {});
      final loaded = List<String>.from(data['cargados'] as List? ?? const []);
      final proposed = Map<String, dynamic>.from(data['propuestas'] as Map? ?? const {});
      bool known(String id) => _items.any((i) => i.id == id);
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
          jsonEncode({
            'fecha': _today(),
            'cantidades': quantities,
            'cargados': _loaded.toList(),
            'propuestas': _proposed,
          }),
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
    if (!_loaded.contains(id) && _isTransfer) {
      final item = _items.where((i) => i.id == id).firstOrNull;
      final q = parseQty(_qty[id]?.text ?? '') ?? 0;
      if (item != null && q > _maxFor(item)) {
        final where = _kind == StockFormKind.unload ? 'en el vehículo' : 'en el depósito';
        _snack('Solo hay ${formatQty(_maxFor(item))} $where: corregí la cantidad para poder marcarlo.');
        return;
      }
    }
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
    return !(_isTransfer && parseQty(text) == 0);
  }

  /// Al tocar la cantidad queda toda seleccionada: se escribe la nueva sin borrar antes.
  void _selectAll(String id) {
    final c = _controller(id);
    c.selection = TextSelection(baseOffset: 0, extentOffset: c.text.length);
  }

  /// Si se dejó vacía, vuelve la cantidad del pedido.
  void _restoreIfEmpty(String id) {
    if (!_isTransfer || _hasText(id)) return;
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
      for (final item in pairLooseWithClosed(_items, _items))
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
      'Escribí lo que contaste.',
    StockFormKind.load =>
      'Se sube solo lo marcado en flúor, y no más de lo que hay en el depósito.',
    StockFormKind.unload => 'Se baja solo lo marcado en flúor, y no más de lo que hay arriba.',
    StockFormKind.purchase =>
      'Elegí dónde entra lo comprado. El costo viene cargado: cambialo solo si pagaste otro precio.',
    StockFormKind.closeTrip =>
      'Contá lo que sobró en el vehículo y corregí lo que no coincida. '
          'La app compara con lo que debería quedar.',
  };

  bool get _zeroAllowed => _kind == StockFormKind.count || _kind == StockFormKind.closeTrip;

  void _fill(Map<String, double> values) {
    setState(() {
      for (final entry in values.entries) {
        if (!_items.any((i) => i.id == entry.key)) continue;
        _controller(entry.key).text = formatQty(entry.value);
        _kept.add(entry.key);
        if (_isTransfer) _proposed[entry.key] = formatQty(entry.value);
      }
      _onlyFilled = true;
      if (_isTransfer) _optionsOpen = false;
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
      if (_isTransfer) {
        _replaceProposals(values);
      } else {
        _fill(values);
      }
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

  /// Pone la propuesta nueva en lugar de la anterior: saca lo propuesto antes que nadie tocó (lo
  /// escrito a mano y lo ya marcado se respeta) y no propone más de lo que hay en el origen.
  /// Lo que no alcanza queda a la vista ("No hay en el depósito"), sin cantidad.
  Map<String, double> _replaceProposals(Map<String, double> wanted) {
    setState(() {
      for (final e in _proposed.entries.toList()) {
        final c = _qty[e.key];
        if (c != null && c.text.trim() == e.value && !_loaded.contains(e.key)) {
          c.clear();
          _kept.remove(e.key);
        }
        _proposed.remove(e.key);
      }
      _noStock.clear();
    });
    final fill = <String, double>{};
    for (final e in wanted.entries) {
      final item = _items.where((i) => i.id == e.key).firstOrNull;
      if (item == null || e.value <= 0) continue;
      final max = _maxFor(item);
      if (max <= 0) {
        _noStock[e.key] = e.value;
        _kept.add(e.key);
        continue;
      }
      fill[e.key] = e.value < max ? e.value : max;
      if (e.value > max) _noStock[e.key] = e.value - max;
    }
    if (fill.isNotEmpty) {
      _fill(fill);
    } else {
      setState(() => _onlyFilled = true);
      _saveDraft();
    }
    return fill;
  }

  /// "Pedidos a entregar": lo que falta subir (lo demás ya está arriba del vehículo), sin pasar de
  /// lo que hay en el depósito. Con [everything], todo lo de los pedidos.
  Future<void> _proposeForDeliveries({bool everything = false}) async {
    try {
      final all = await fetchPendingDeliveries(_client);
      if (!mounted) return;
      if (all.isEmpty) {
        _snack('No hay pedidos facturados para entregar.');
        return;
      }
      final missing = everything ? all : stillToLoad(all, _items);
      final fill = _replaceProposals(missing);
      final upAlready = missing.length != all.length || missing.entries.any((e) => e.value < (all[e.key] ?? 0));
      final message = [
        if (fill.isEmpty && _noStock.isEmpty)
          'Ya está todo arriba del vehículo para los pedidos a entregar.'
        else if (upAlready)
          'Propuesto lo que falta subir: lo demás ya está en el vehículo.'
        else
          'Propuesto lo de los pedidos a entregar.',
        if (_noStock.isNotEmpty)
          'No alcanza en el depósito: ${_noStock.length} ${_noStock.length == 1 ? 'producto' : 'productos'}.',
      ].join(' ');
      _closeProposeSnack();
      final snack = ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 10),
          showCloseIcon: true,
          content: Text(message),
          action: upAlready && !everything
              ? SnackBarAction(
                  label: 'PROPONER TODO',
                  onPressed: () => _proposeForDeliveries(everything: true),
                )
              : null,
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
    final text = sinAcentos(_search.text);
    final base = _items.where((item) {
      if (widget.onlyIds != null && !widget.onlyIds!.contains(item.id)) return false;
      if (!coincideBusqueda(_search.text, [item.name, item.code])) {
        return false;
      }
      final filled = _hasText(item.id);
      final kept = filled || _kept.contains(item.id);
      if (_onlyFilled && text.isEmpty && !kept) return false;
      if (_onlyPending && text.isEmpty &&
          (!kept || _loaded.contains(item.id) || (filled && !_filled(item.id)))) {
        return false;
      }
      if (_kind == StockFormKind.count && !_allProducts && (item.onDemand || !item.controlled) && !filled &&
          text.isEmpty && widget.onlyIds == null) {
        return false;
      }
      return true;
    }).toList();
    // Cada suelto justo debajo de su cerrado; al contar, aparecen aunque sean "a pedido".
    return pairLooseWithClosed(base, _items, addLoose: _kind == StockFormKind.count);
  }

  /// Productos con cantidad escrita. Null si alguna es inválida.
  List<Map<String, dynamic>>? _lines() {
    final lines = <Map<String, dynamic>>[];
    for (final item in _items) {
      final text = _qty[item.id]?.text ?? '';
      if (text.trim().isEmpty) continue;
      final q = parseQty(text);
      if (q == null) return null;
      if (q == 0 && _isTransfer) continue;
      // Cargar y bajar: pasa solo lo marcado en flúor.
      if (_isTransfer && !_loaded.contains(item.id)) continue;
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
      _items.where((i) => i.id == id).map((i) => i.name).firstOrNull ?? 'Producto';

  Future<void> _confirm() async {
    final lines = _lines();
    if (lines == null) {
      _snack(_zeroAllowed
          ? 'Revisá las cantidades: números de 0 en adelante.'
          : 'Revisá las cantidades: tienen que ser mayores que 0.');
      return;
    }
    if (_kind == StockFormKind.purchase && _location.isEmpty) {
      _snack('Elegí dónde entra la compra: Depósito o Vehículo.');
      return;
    }
    if (lines.isEmpty && _isTransfer) {
      _snack(_kind == StockFormKind.load
          ? 'Marcá en flúor lo que vas subiendo: solo eso se carga.'
          : 'Marcá en flúor lo que vas bajando: solo eso se baja.');
      return;
    }
    if (lines.isEmpty && !(_kind == StockFormKind.closeTrip)) {
      _snack('Escribí la cantidad de al menos un producto.');
      return;
    }
    if (_isTransfer) {
      for (final l in lines) {
        final item = _items.where((i) => i.id == l['producto_id']).firstOrNull;
        if (item != null && stockNum(l['cantidad']) > _maxFor(item)) {
          _snack('${item.name}: solo hay ${formatQty(_maxFor(item))} '
              '${_kind == StockFormKind.unload ? 'en el vehículo' : 'en el depósito'}.');
          return;
        }
      }
    }
    if (_kind == StockFormKind.closeTrip) {
      final seguir = await _negativosDelDeposito();
      if (!seguir || !mounted) return;
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
    if (_isTransfer) {
      final left = _items.where((i) => _filled(i.id) && !_loaded.contains(i.id)).length;
      _leftNote = left == 0
          ? null
          : '$left ${left == 1 ? 'producto quedó' : 'productos quedaron'} sin marcar: no se '
                '${_kind == StockFormKind.load ? 'cargaron' : 'bajaron'}.';
    }
    if (_kind == StockFormKind.purchase) await _registerPayment(total);
    if (!mounted) return;
    await _showResult(outcome.result);
    if (mounted) Navigator.of(context).pop(true);
  }

  /// Al cerrar el viaje: lo que quedó en negativo en el vehículo (se vendió más de lo que figuraba
  /// arriba) se puede descontar del depósito, en vez de ponerlo en 0 sin tocar el depósito.
  /// Devuelve false si el usuario vuelve atrás o si falló.
  Future<bool> _negativosDelDeposito() async {
    final negativos = _items.where((i) => i.controlled && i.vehicle < 0).toList();
    if (negativos.isEmpty) return true;
    final descontar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: AppColors.naranja, size: 40),
        title: const Text('Quedó en negativo en el vehículo'),
        content: SingleChildScrollView(
          child: Text(
            'Se vendió más de lo que figuraba arriba:\n'
            '${negativos.map((i) => '• ${i.name}: ${formatQty(i.vehicle)}').join('\n')}\n\n'
            'Si salió del depósito, descontalo de ahí. Si no, el vehículo queda en 0 y el '
            'depósito no cambia.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Volver')),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Solo poner en 0'),
          ),
          FilledButton(
            key: const Key('descontar-deposito'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Descontar del depósito'),
          ),
        ],
      ),
    );
    if (descontar == null || !mounted) return false;
    if (!descontar) return true;
    const rpc = 'stock_vehiculo_faltante_del_deposito';
    final args = <String, dynamic>{
      'p_items': [
        for (final i in negativos) {'producto_id': i.id, 'cantidad': -i.vehicle},
      ],
    };
    setState(() => _saving = true);
    try {
      final runner = widget.runner;
      if (runner != null) {
        await runner(rpc, args);
      } else {
        await runStockOp(
          _client,
          rpc: rpc,
          args: args,
          description: 'Faltante del vehículo descontado del depósito',
          total: 0,
        );
      }
      return true;
    } catch (error) {
      _snack(stockErrorText(error));
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// La compra ya quedó en el stock: ahora el pago (si falla, la compra igual queda).
  Future<void> _registerPayment(double total) async {
    if (_payWith == 'nada') return;
    if (total <= 0) {
      _payNote = 'El pago no se anotó: faltan los costos. Anotalo en "Plata del negocio".';
      return;
    }
    final supplier = _supplier.text.trim();
    final (rpc, args) = _payWith == 'a_pagar'
        ? (
            'fin_deuda',
            <String, dynamic>{
              'p_proveedor': supplier.isEmpty ? 'Proveedor' : supplier,
              'p_importe': total,
              'p_vence': isoDate(_due),
              'p_descripcion': 'Compra de mercadería',
            },
          )
        : (
            'fin_movimiento',
            <String, dynamic>{
              'p_tipo': 'compra',
              'p_cuenta': _payWith,
              'p_importe': total,
              'p_categoria': 'Mercadería',
              'p_descripcion': supplier.isEmpty ? null : supplier,
            },
          );
    try {
      final outcome = await runFinOp(
        widget.client,
        rpc: rpc,
        args: args,
        description: _payWith == 'a_pagar' ? 'A pagar · $supplier' : 'Pago de compra',
        total: total,
        runner: widget.runner,
      );
      _payNote = _payWith == 'a_pagar'
          ? 'Queda a pagar ${pesos(total)} (vence el ${diaMes(_due)}).'
          : 'Pago anotado: ${pesos(total)} en ${cuentaNombre(_payWith).toLowerCase()}'
                '${outcome.savedOffline ? ' (se envía al volver la señal)' : ''}.';
    } catch (error) {
      _payNote = 'El pago no se anotó: ${stockErrorText(error)}';
    }
  }

  Future<void> _showResult(Map<String, dynamic>? result) async {
    final lines = <String>[];
    if (result == null) {
      lines.add(
        'No hay señal: quedó guardado en el teléfono y se envía solo cuando vuelva la conexión. '
        'Lo ves en "Pendientes de enviar".',
      );
      if (_kind == StockFormKind.purchase && _payNote != null) lines.add(_payNote!);
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
          if (_leftNote != null) lines.add(_leftNote!);
        case StockFormKind.unload:
          lines.add('Listo: ${result['movidos']} productos volvieron al depósito.');
          if (_leftNote != null) lines.add(_leftNote!);
        case StockFormKind.purchase:
          lines.add('Compra anotada.');
          if (stockNum(result['total']) > 0) {
            lines.add('Total: ${formatoPesos(result['total'])}');
          }
          final pasaron = stockNum(result['nuevos_con_stock']).round();
          if (pasaron > 0) lines.add('$pasaron productos "a pedido" pasaron a llevar stock.');
          if (_payNote != null) lines.add(_payNote!);
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
    if (_isTransfer) return _buildLoad();
    final visible = _visible;
    final filled = _items.where((i) => _filled(i.id)).length;
    final teclado =
        MediaQuery.viewInsetsOf(context).bottom > 0 && !_supplierFocus.hasFocus;
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: DesktopForm(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(16, teclado ? 6 : 12, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (teclado)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        _resumenOpciones,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.gris),
                      ),
                    )
                  else ...[
                    Text(_help, style: const TextStyle(color: AppColors.gris)),
                    const SizedBox(height: 8),
                    ..._options(),
                    const SizedBox(height: 8),
                  ],
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
                  if (!teclado)
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
                          label: const Text('Incluir los que se compran a pedido'),
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
      bottomNavigationBar: teclado ? null : _confirmBar(filled),
    );
  }

  /// Una línea con lo elegido arriba, para cuando las opciones quedan escondidas por el teclado.
  String get _resumenOpciones {
    final lugar = _location == vehiculoCodigo
        ? 'Vehículo'
        : _location.isEmpty
        ? 'Sin elegir el lugar'
        : 'Depósito';
    if (_kind != StockFormKind.purchase) {
      return _kind == StockFormKind.count
          ? '$lugar · cerrá el teclado para ver las opciones'
          : 'Cerrá el teclado para ver las opciones';
    }
    final pago = switch (_payWith) {
      efectivo => 'Efectivo',
      billetera => 'Billetera',
      'a_pagar' => 'A pagar',
      _ => 'Sin anotar el pago',
    };
    return '$lugar · $pago · cerrá el teclado para ver las opciones';
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
                : _isTransfer
                ? (_marked.isEmpty
                      ? 'MARCÁ LO QUE ${_kind == StockFormKind.load ? 'SUBÍS' : 'BAJÁS'}'
                      : '${_kind == StockFormKind.load ? 'SUBIR' : 'BAJAR'} ${_marked.length} '
                            '${_marked.length == 1 ? 'PRODUCTO' : 'PRODUCTOS'} · ${formatQty(_markedUnits)} U.')
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
    final filled = _items.where((i) => _filled(i.id)).length;
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: DesktopForm(
        child: Column(
          children: [
            _directionBar(),
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
                                ..addAll(_items.where((i) => _hasText(i.id)).map((i) => i.id));
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

  /// Desde → Hacia, con ⇄ para dar vuelta (cargar ↔ bajar), y la hora del stock con el botón de
  /// actualizar: se trabaja siempre con el stock de este momento.
  Widget _directionBar() {
    final load = _kind == StockFormKind.load;
    final t = Tonos.of(context);
    Widget place(String label, String name) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.dorado, width: 1.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(fontSize: 11, color: t.secundario)),
            Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
    String two(int n) => n.toString().padLeft(2, '0');
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 6),
      child: Row(
        children: [
          place('Desde', load ? 'Depósito' : 'Vehículo'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: IconButton(
              key: const Key('dar-vuelta'),
              tooltip: load ? 'Pasar a bajar al depósito' : 'Pasar a cargar el vehículo',
              style: IconButton.styleFrom(
                backgroundColor: AppColors.dorado,
                foregroundColor: AppColors.negro,
              ),
              onPressed: _saving ? null : _swapDirection,
              icon: const Icon(Icons.swap_horiz),
            ),
          ),
          place('Hacia', load ? 'Vehículo' : 'Depósito'),
          if (widget.reload != null)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Actualizar el stock',
                  onPressed: _reloading ? null : _reload,
                  icon: _reloading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                ),
                Text(
                  '${two(_dataAt.hour)}:${two(_dataAt.minute)}',
                  style: TextStyle(fontSize: 11, color: t.secundario),
                ),
              ],
            )
          else
            const SizedBox(width: 8),
        ],
      ),
    );
  }

  /// Si alcanza lo del depósito para lo que se va a cargar (abriendo cajas si hace falta).
  Map<String, SummaryRow> _loadStatus() {
    final lines = <SummaryLine>[];
    for (final item in _items) {
      final q = parseQty(_qty[item.id]?.text ?? '');
      if (q != null && q > 0) lines.add(SummaryLine(item.id, item.name, q));
    }
    if (lines.isEmpty) return const {};
    final origin = {
      for (final i in _items) i.id: _kind == StockFormKind.unload ? i.vehicleOnly() : i.depositOnly(),
    };
    return {for (final r in evaluateSummary(lines, origin)) r.line.productId!: r};
  }

  /// Barra fija: "3 de 9 cargados", "Falta cargar", compartir y "Opciones".
  Widget _loadBar() {
    final filled = _items.where((i) => _filled(i.id)).toList();
    final done = filled.where((i) => _loaded.contains(i.id)).length;
    final complete = filled.isNotEmpty && done == filled.length;
    final t = Tonos.of(context);
    return Container(
      color: t.barra,
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
                    filled.isEmpty
                        ? (_kind == StockFormKind.load ? 'Escribí qué cargar' : 'Escribí qué bajar')
                        : '$done de ${filled.length} ${_kind == StockFormKind.load ? 'cargados' : 'bajados'}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: complete ? t.verde : null,
                    ),
                  ),
                ),
                if (filled.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  LinearProgressIndicator(
                    value: done / filled.length,
                    minHeight: 4,
                    color: complete ? t.verde : t.fluorBorde,
                    backgroundColor: t.oscuro ? Colors.white24 : Colors.black12,
                  ),
                ],
              ],
            ),
          ),
          if (filled.isNotEmpty) ...[
            const SizedBox(width: 6),
            FilterChip(
              visualDensity: VisualDensity.compact,
              label: Text(_kind == StockFormKind.load ? 'Falta cargar' : 'Falta bajar'),
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
        : _items.where((i) => i.id == item.parentId).firstOrNull;
    final loaded = _loaded.contains(item.id);
    final filled = _filled(item.id);
    final zebra = !loaded && index.isOdd;
    final t = Tonos.of(context);
    final textColor = loaded ? t.fluorTexto : (zebra ? t.cebraTexto : t.filaTexto);
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
    final sinStock = _noStock[item.id];
    final info = skipped
        ? (_kind == StockFormKind.load ? 'No se carga' : 'No se baja')
        : sinStock != null && !filled
        ? 'No hay en el depósito · pedidos ${formatQty(sinStock)}'
        : !item.controlled
        ? 'A pedido'
        : _kind == StockFormKind.unload
        ? 'Arriba ${formatQty(item.vehicle)}'
        : [
            'Depósito ${formatQty(item.deposit)}',
            if (closed != null && closed.controlled) '${closed.name}: ${formatQty(closed.deposit)}',
          ].join(' · ');
    return Material(
      color: loaded ? t.fluor : (zebra ? t.cebra : t.fila),
      child: InkWell(
        onTap: filled || loaded ? () => _toggleLoaded(item.id) : null,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: loaded ? t.fluorBorde : Colors.transparent, width: 6),
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
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(Icons.subdirectory_arrow_right, size: 18, color: t.secundario),
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
                          Text(
                            info,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: sinStock != null && !filled ? FontWeight.w600 : null,
                              color: sinStock != null && !filled
                                  ? t.rojo
                                  : (zebra ? t.cebraTexto : t.secundario),
                            ),
                          ),
                        if (changed)
                          Text(
                            'Pedidos: $original',
                            style: TextStyle(fontSize: 12, color: zebra ? t.cebraTexto : t.secundario),
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
                      fillColor: t.campo,
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
            // En la compra no arranca en ninguno: el lugar se elige siempre.
            emptySelectionAllowed: _location.isEmpty,
            selected: _location.isEmpty ? const <String>{} : {_location},
            onSelectionChanged: (v) {
              if (v.isNotEmpty) setState(() => _location = v.first);
            },
          ),
          if (_kind == StockFormKind.purchase) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _supplier,
              focusNode: _supplierFocus,
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
            const Text('¿Cómo pagaste?', style: TextStyle(color: AppColors.gris)),
            const SizedBox(height: 4),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: efectivo, label: Text('Efectivo')),
                ButtonSegment(value: billetera, label: Text('Billetera')),
                ButtonSegment(value: 'a_pagar', label: Text('A pagar')),
                ButtonSegment(value: 'nada', label: Text('No anotar')),
              ],
              selected: {_payWith},
              onSelectionChanged: (v) => setState(() => _payWith = v.first),
            ),
            if (_payWith == 'a_pagar')
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.event),
                  label: Text('Vence el ${diaMes(_due)}'),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _due,
                      firstDate: DateTime.now().subtract(const Duration(days: 1)),
                      lastDate: DateTime.now().add(const Duration(days: 120)),
                    );
                    if (picked != null) setState(() => _due = picked);
                  },
                ),
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
              TextButton.icon(
                icon: const Icon(Icons.restart_alt),
                label: const Text('Empezar de nuevo'),
                onPressed: _startOver,
              ),
            ],
          ),
        ];
      case StockFormKind.unload:
        return [
          OutlinedButton.icon(
            icon: const Icon(Icons.select_all),
            label: const Text('Todo lo del vehículo'),
            onPressed: () => _replaceProposals({
              for (final i in _items)
                if (i.controlled && i.vehicle > 0) i.id: i.vehicle,
            }),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.restart_alt),
              label: const Text('Empezar de nuevo'),
              onPressed: _startOver,
            ),
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
        : _items.where((i) => i.id == item.parentId).firstOrNull;
    final hasLoose = _items.any((i) => i.parentId == item.id);
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
                              '${item.deposit < 0 ? ' · depósito en ${formatQty(item.deposit)}' : ''}'
                        : info,
                    style: TextStyle(
                      fontSize: 13,
                      // Al cerrar el viaje, el rojo es por el vehículo; el depósito se avisa aparte.
                      color: (_kind == StockFormKind.closeTrip ? item.vehicle < 0 : item.negative)
                          ? AppColors.rojo
                          : (_kind == StockFormKind.closeTrip && item.deposit < 0
                                ? AppColors.naranja
                                : AppColors.gris),
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
