import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_theme.dart';
import '../../core/desktop_records.dart';
import '../../core/money_format.dart';
import '../../core/network_status.dart';
import 'stock_data.dart';
import 'stock_home_page.dart' show openPurchase;

// "Para reponer": lo que se va a acabar antes de que llegue la próxima compra. Ver stock_reponer.

class ReorderLine {
  const ReorderLine({
    required this.productId,
    required this.name,
    required this.action,
    this.supplier,
    this.delay = 1,
    this.have = 0,
    this.committed = 0,
    this.free = 0,
    this.perWeek = 0,
    this.days,
    this.buy,
    this.parentName,
    this.open,
    this.cost,
    this.minimum,
    this.muted = false,
  });

  final String productId;
  final String name;

  /// comprar, abrir o alcanza.
  final String action;
  final String? supplier;
  final int delay;
  final double have;
  final double committed;
  final double free;
  final double perWeek;

  /// Para cuántos días alcanza lo libre (null si no se vende).
  final double? days;
  final double? buy;
  final String? parentName;
  final double? open;

  /// Costo de lo que hay que comprar (solo administración).
  final double? cost;
  final double? minimum;
  final bool muted;

  bool get alerts => action != 'alcanza';

  static ReorderLine fromJson(Map<String, dynamic> j) {
    double? opt(String k) => j[k] == null ? null : stockNum(j[k]);
    return ReorderLine(
      productId: j['producto_id'].toString(),
      name: j['nombre']?.toString() ?? '',
      action: j['accion']?.toString() ?? 'comprar',
      supplier: (j['proveedor']?.toString().trim().isEmpty ?? true) ? null : j['proveedor'].toString().trim(),
      delay: stockNum(j['demora']).round(),
      have: stockNum(j['hay']),
      committed: stockNum(j['comprometido']),
      free: stockNum(j['libre']),
      perWeek: stockNum(j['por_semana']),
      days: opt('dias'),
      buy: opt('comprar'),
      parentName: j['origen']?.toString(),
      open: opt('abrir'),
      cost: opt('costo_total'),
      minimum: opt('minimo'),
      muted: j['no_avisar'] == true,
    );
  }

  /// "alcanza 1 día", "se acabó".
  String get daysText {
    final d = days;
    if (d == null) return minimum != null ? 'bajo el mínimo' : '';
    if (d <= 0) return 'se acabó';
    if (d < 1.5) return 'alcanza 1 día';
    return 'alcanza ${d.round()} días';
  }

  /// Hint para Anotar compra: "Vende ~40 por semana · alcanza 3 días".
  String get hint => 'Vende ~${formatQty(perWeek.roundToDouble())} por semana'
      '${daysText.isEmpty ? '' : ' · $daysText'}';
}

Future<List<ReorderLine>> fetchReorder(SupabaseClient client, {bool all = false}) async {
  final List<dynamic> rows = await client.rpc('stock_reponer', params: {'p_todos': all}, get: true);
  return [for (final r in rows) ReorderLine.fromJson(Map<String, dynamic>.from(r as Map))];
}

/// Para cada producto que se vende: "Vende ~X por semana · alcanza N días". Si falla, vacío.
Future<Map<String, String>> fetchPurchaseHints(SupabaseClient client) async {
  try {
    return {for (final l in await fetchReorder(client, all: true)) l.productId: l.hint};
  } catch (_) {
    return const {};
  }
}

const sinProveedor = 'Sin proveedor';

/// Agrupa por proveedor, el más urgente primero.
List<MapEntry<String, List<ReorderLine>>> groupBySupplier(List<ReorderLine> lines) {
  final groups = <String, List<ReorderLine>>{};
  for (final l in lines) {
    groups.putIfAbsent(l.supplier ?? sinProveedor, () => []).add(l);
  }
  double urgency(List<ReorderLine> g) => g.map((l) => l.days ?? -1).fold(double.infinity, (a, b) => b < a ? b : a);
  final out = groups.entries.toList()
    ..sort((a, b) {
      if (a.key == sinProveedor) return 1;
      if (b.key == sinProveedor) return -1;
      return urgency(a.value).compareTo(urgency(b.value));
    });
  return out;
}

/// Texto para mandar por WhatsApp.
String reorderShareText(List<ReorderLine> lines) {
  final b = StringBuffer('Para reponer:\n');
  for (final g in groupBySupplier(lines)) {
    b.writeln();
    b.writeln('*${g.key}*');
    for (final l in g.value) {
      if (l.action == 'abrir') {
        b.writeln('Abrir ${formatQty(l.open ?? 1)} × ${l.parentName} (para ${l.name})');
      } else {
        b.writeln('${formatQty(l.buy ?? 0)} × ${l.name} (${l.daysText})');
      }
    }
  }
  return b.toString().trim();
}

class ReorderPage extends StatefulWidget {
  const ReorderPage({super.key, this.client, this.helper = false, this.initial, this.available});
  final SupabaseClient? client;

  /// Ayuda en el depósito: sin costos ni plata, y sin cambiar demoras ni mínimos.
  final bool helper;

  /// Solo para pruebas.
  final List<ReorderLine>? initial;

  /// Disponible para mercadería (de Plata del negocio), si se pudo leer.
  final double? available;

  @override
  State<ReorderPage> createState() => _ReorderPageState();
}

class _ReorderPageState extends State<ReorderPage> {
  SupabaseClient get _client => widget.client ?? Supabase.instance.client;
  List<ReorderLine>? _lines;
  double? _available;
  String? _error;

  @override
  void initState() {
    super.initState();
    _lines = widget.initial;
    _available = widget.available;
    if (_lines == null) _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final lines = await fetchReorder(_client);
      double? available = _available;
      if (!widget.helper) {
        try {
          final Object? r = await _client.rpc('fin_estado', params: const {}, get: true);
          if (r is Map && r['inicio'] != null) available = stockNum(r['disponible']);
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _lines = lines;
          _available = available;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = isUncertainRequestError(error) ? 'Sin conexión.' : stockErrorText(error));
      }
    }
  }

  void _snack(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _share(List<ReorderLine> lines) async {
    final text = reorderShareText(lines);
    try {
      await SharePlus.instance.share(ShareParams(text: text));
    } catch (_) {}
  }

  Future<void> _delay(String supplier, int current) async {
    final value = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('¿Cuántos días tarda en llegar lo de $supplier?'),
        children: [
          for (final d in const [0, 1, 2, 3, 5, 7])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, d),
              child: Text(
                '${d == 0 ? 'El mismo día' : d == 1 ? '1 día' : '$d días'}${d == current ? '  ✓' : ''}',
                style: const TextStyle(fontSize: 16),
              ),
            ),
        ],
      ),
    );
    if (value == null || value == current) return;
    try {
      await _client.rpc('stock_proveedor_demora', params: {'p_proveedor': supplier, 'p_dias': value});
      await _load();
    } catch (error) {
      _snack(isUncertainRequestError(error) ? 'Sin señal: se cambia con conexión.' : stockErrorText(error));
    }
  }

  Future<void> _adjust(ReorderLine l) async {
    final minimum = TextEditingController(text: l.minimum == null ? '' : formatQty(l.minimum!));
    var muted = l.muted;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: Text(l.name),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('No avisar'),
                subtitle: const Text('Por ejemplo, si no lo vas a comprar más.'),
                value: muted,
                onChanged: (v) => set(() => muted = v),
              ),
              TextField(
                controller: minimum,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Mínimo propio (opcional)',
                  helperText: 'Avisa cuando quede esto o menos, además del ritmo de venta.',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Guardar')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final min = minimum.text.trim().isEmpty ? null : parseQty(minimum.text);
    try {
      await _client.rpc(
        'stock_reposicion_ajustar',
        params: {'p_producto': l.productId, 'p_no_avisar': muted, 'p_minimo': min},
      );
      await _load();
    } catch (error) {
      _snack(isUncertainRequestError(error) ? 'Sin señal: se cambia con conexión.' : stockErrorText(error));
    }
  }

  Future<void> _purchase(String supplier, List<ReorderLine> lines) async {
    await openPurchase(
      context,
      client: widget.client,
      initialQuantities: {for (final l in lines) if (l.action == 'comprar' && (l.buy ?? 0) > 0) l.productId: l.buy!},
      initialSupplier: supplier == sinProveedor ? null : supplier,
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final lines = _lines;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Para reponer'),
        actions: [
          if (lines != null && lines.isNotEmpty)
            IconButton(tooltip: 'Compartir lista', icon: const Icon(Icons.share), onPressed: () => _share(lines)),
          IconButton(tooltip: 'Actualizar', icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: DesktopForm(
        maxWidth: 900,
        child: lines == null
            ? Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!))
            : lines.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Por ahora alcanza todo hasta la próxima compra.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              )
            : RefreshIndicator(onRefresh: _load, child: _list(lines)),
      ),
    );
  }

  Widget _list(List<ReorderLine> lines) {
    final t = Tonos.of(context);
    final total = lines.fold<double>(0, (s, l) => s + (l.cost ?? 0));
    final groups = groupBySupplier(lines);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
      children: [
        if (!widget.helper && total > 0)
          Card(
            key: const Key('reponer-total'),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  _pair('Reponer todo', formatoPesos(total), bold: true),
                  if (_available != null)
                    _pair(
                      'Disponible para mercadería',
                      formatoPesos(_available!),
                      color: _available! >= total ? t.verde : t.rojo,
                    ),
                ],
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Text(
            'Avisa lo que alcanza para menos de lo que tarda el proveedor + 2 días, y sugiere comprar para una '
            'semana. Se mide con lo vendido en las últimas 8 semanas y lo libre (sin lo ya facturado).',
            style: TextStyle(fontSize: 12, color: t.secundario),
          ),
        ),
        for (final g in groups) _group(g.key, g.value),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _share(lines),
          icon: const Icon(Icons.share),
          label: Text(widget.helper ? 'Mandar la lista' : 'Compartir lista'),
        ),
        if (!widget.helper)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Tocá el proveedor para cambiar cuánto tarda. Mantené apretado un producto para no avisar o '
              'ponerle un mínimo.',
              style: TextStyle(fontSize: 12, color: t.secundario),
            ),
          ),
      ],
    );
  }

  Widget _pair(String left, String right, {bool bold = false, Color? color}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(child: Text(left, style: TextStyle(fontWeight: bold ? FontWeight.bold : null))),
        Text(right, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
      ],
    ),
  );

  Widget _group(String supplier, List<ReorderLine> lines) {
    final t = Tonos.of(context);
    final cost = lines.fold<double>(0, (s, l) => s + (l.cost ?? 0));
    final delay = lines.first.delay;
    final canEdit = !widget.helper && supplier != sinProveedor;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: canEdit ? () => _delay(supplier, delay) : null,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      supplier == sinProveedor
                          ? 'SIN PROVEEDOR (todavía no se anotó una compra)'
                          : '${supplier.toUpperCase()} · llega en ${delay == 0 ? 'el día' : delay == 1 ? '1 día' : '$delay días'}',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: t.secundario),
                    ),
                  ),
                  if (!widget.helper && cost > 0) Text(formatoPesos(cost), style: const TextStyle(fontWeight: FontWeight.bold)),
                  if (canEdit) Icon(Icons.edit_outlined, size: 16, color: t.secundario),
                ],
              ),
            ),
            for (final l in lines) _row(l),
            if (!widget.helper && lines.any((l) => l.action == 'comprar'))
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _purchase(supplier, lines),
                  icon: const Icon(Icons.add_shopping_cart),
                  label: const Text('Anotar compra'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(ReorderLine l) {
    final t = Tonos.of(context);
    final urgent = (l.days ?? 0) < l.delay + 1;
    final (bg, fg) = l.action == 'abrir' ? t.etiquetaVioleta : (urgent ? t.etiquetaRoja : t.etiquetaAmarilla);
    final details = [
      'Hay ${formatQty(l.free < 0 ? 0 : l.free)}',
      if (l.perWeek > 0) 'vende ~${formatQty(l.perWeek.roundToDouble())}/sem',
      if (l.committed > 0) '${formatQty(l.committed)} en pedidos',
    ].join(' · ');
    return InkWell(
      onLongPress: widget.helper ? null : () => _adjust(l),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: Theme.of(context).dividerColor, width: 0.5))),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  Text(details, style: TextStyle(fontSize: 12.5, color: t.secundario)),
                  const SizedBox(height: 3),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
                    child: Text(
                      l.action == 'abrir' ? 'abrir ${formatQty(l.open ?? 1)} × ${l.parentName}' : l.daysText,
                      style: TextStyle(fontSize: 11.5, color: fg, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            if (l.action == 'comprar')
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    widget.helper ? 'Faltan ${formatQty(l.buy ?? 0)}' : 'Comprar ${formatQty(l.buy ?? 0)}',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  if (!widget.helper && (l.cost ?? 0) > 0)
                    Text(formatoPesos(l.cost!), style: TextStyle(fontSize: 12, color: t.secundario)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
