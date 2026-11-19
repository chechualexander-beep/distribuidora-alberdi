import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_theme.dart';
import 'stock_data.dart';

/// Un producto del resumen: cuánto piden los pedidos elegidos.
class SummaryLine {
  const SummaryLine(this.productId, this.name, this.quantity);
  final String? productId;
  final String name;
  final double quantity;
}

enum SummaryState { enough, missing, open, onDemand, unknown }

class SummaryRow {
  const SummaryRow({
    required this.line,
    required this.state,
    this.have,
    this.missing = 0,
    this.openParents = 0,
    this.parentName,
    this.buyName,
    this.buyQuantity = 0,
    this.closedName,
    this.closedStock,
  });

  final SummaryLine line;
  final SummaryState state;

  /// Lo que hay (depósito + vehículo); null si no lleva stock o no se sabe.
  final double? have;
  final double missing;

  /// Unidades del producto de origen para abrir (fraccionados).
  final double openParents;
  final String? parentName;

  /// Qué comprar y cuánto (en unidades del origen si es fraccionado).
  final String? buyName;
  final double buyQuantity;

  /// Suelto que sale de un cerrado: cuántos cerrados hay (para mostrar "2 sueltas · 10 cajas").
  final String? closedName;
  final double? closedStock;
}

/// Compara lo pedido con el stock. Sin [stock] (preventista o sin señal) solo lista cantidades.
List<SummaryRow> evaluateSummary(List<SummaryLine> lines, Map<String, StockItem>? stock) {
  final rows = <SummaryRow>[];
  // Unidades de origen que se pueden abrir: lo que hay menos lo que piden los pedidos de ese
  // mismo producto (primero se entrega lo pedido entero). Se descuentan a medida que se abren.
  final demand = <String, double>{};
  for (final line in lines) {
    if (line.productId != null) {
      demand[line.productId!] = (demand[line.productId!] ?? 0) + line.quantity;
    }
  }
  final parentLeft = <String, double>{};
  for (final line in lines) {
    final item = line.productId == null ? null : stock?[line.productId];
    if (item == null) {
      rows.add(SummaryRow(line: line, state: SummaryState.unknown));
      continue;
    }
    final parent = item.parentId == null ? null : stock![item.parentId];
    final units = item.unitsPerParent ?? 0;
    final parentId = item.parentId;
    if (parent != null && parent.controlled && units > 0 && parentId != null) {
      parentLeft.putIfAbsent(parentId, () {
        final left = parent.total - (demand[parentId] ?? 0);
        return left > 0 ? left : 0;
      });
    }
    final parentHave = parentId == null ? 0.0 : (parentLeft[parentId] ?? 0.0);
    final closedName = parent?.name;
    final closedStock = parent != null && parent.controlled ? parent.total : null;
    final have = item.controlled ? item.total : 0.0;
    final q = line.quantity;
    if (item.controlled && have >= q) {
      rows.add(SummaryRow(
        line: line,
        state: SummaryState.enough,
        have: have,
        closedName: closedName,
        closedStock: closedStock,
      ));
      continue;
    }
    final short = q - (have > 0 ? have : 0);
    var open = 0.0;
    if (parentHave >= 1) {
      open = (short / units).ceilToDouble();
      if (open > parentHave.floorToDouble()) open = parentHave.floorToDouble();
    }
    if (open > 0) parentLeft[parentId!] = parentHave - open;
    final left = short - open * units;
    if (left <= 0) {
      rows.add(SummaryRow(
        line: line,
        state: SummaryState.open,
        have: item.controlled ? have : null,
        openParents: open,
        parentName: parent?.name,
        closedName: closedName,
        closedStock: closedStock,
      ));
      continue;
    }
    final parentName = parent?.name;
    final buyParent = parentName != null && units > 0;
    rows.add(SummaryRow(
      line: line,
      state: item.controlled || open > 0 ? SummaryState.missing : SummaryState.onDemand,
      have: item.controlled ? have : null,
      missing: left,
      openParents: open,
      parentName: parent?.name,
      buyName: buyParent ? parentName : item.name,
      buyQuantity: buyParent ? (left / units).ceilToDouble() : left,
      closedName: closedName,
      closedStock: closedStock,
    ));
  }
  return rows;
}

/// "Comprar:\n2 × Aceite de coco x 360 ml\n1 × Copos 3A x 4 kg"
String shoppingList(List<SummaryRow> rows) {
  final totals = <String, double>{};
  for (final r in rows) {
    if (r.buyName == null || r.buyQuantity <= 0) continue;
    totals[r.buyName!] = (totals[r.buyName!] ?? 0) + r.buyQuantity;
  }
  final opens = <String, double>{};
  for (final r in rows) {
    if (r.openParents > 0 && r.parentName != null) {
      opens[r.parentName!] = (opens[r.parentName!] ?? 0) + r.openParents;
    }
  }
  final b = StringBuffer();
  if (totals.isEmpty) {
    b.writeln('No hay que comprar nada: alcanza con lo que hay.');
  } else {
    b.writeln('Comprar:');
    for (final e in totals.entries) {
      b.writeln('${formatQty(e.value)} × ${e.key}');
    }
  }
  if (opens.isNotEmpty) {
    b.writeln();
    b.writeln('Fraccionar:');
    for (final e in opens.entries) {
      b.writeln('Abrir ${formatQty(e.value)} × ${e.key}');
    }
  }
  return b.toString().trim();
}

/// Resumen de productos fácil de leer: filas alternadas, lo que hay al lado y qué falta.
class ProductSummaryTable extends StatefulWidget {
  const ProductSummaryTable({super.key, required this.lines, this.client, this.stock});
  final List<SummaryLine> lines;
  final SupabaseClient? client;

  /// Para pruebas: stock ya cargado (si no, se consulta; si no se puede, se muestra sin stock).
  final Map<String, StockItem>? stock;

  @override
  State<ProductSummaryTable> createState() => _ProductSummaryTableState();
}

class _ProductSummaryTableState extends State<ProductSummaryTable> {
  Map<String, StockItem>? _stock;
  bool _onlyMissing = false;

  static const _zebra = Color(0xFFE6F1FB);
  static const _zebraText = Color(0xFF0C447C);

  @override
  void initState() {
    super.initState();
    _stock = widget.stock;
    if (_stock == null) _load();
  }

  Future<void> _load() async {
    try {
      final items = await fetchStockItems(widget.client ?? Supabase.instance.client);
      if (!mounted) return;
      setState(() => _stock = {for (final i in items) i.id: i});
    } catch (_) {
      // Sin permiso (preventista) o sin señal: el resumen queda sin la columna de stock.
    }
  }

  Future<void> _showShoppingList(List<SummaryRow> rows) async {
    final text = shoppingList(rows);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Lista de compras'),
        content: SingleChildScrollView(child: SelectableText(text)),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy),
            label: const Text('Copiar'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (context.mounted) Navigator.pop(context);
            },
          ),
          FilledButton.icon(
            icon: const Icon(Icons.share),
            label: const Text('Compartir'),
            onPressed: () async {
              try {
                await SharePlus.instance.share(ShareParams(text: text));
              } catch (_) {
                await Clipboard.setData(ClipboardData(text: text));
              }
              if (context.mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final all = evaluateSummary(widget.lines, _stock);
    final withStock = _stock != null;
    int count(SummaryState s) => all.where((r) => r.state == s).length;
    final rows = _onlyMissing ? all.where((r) => r.state != SummaryState.enough).toList() : all;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (withStock) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _badge('${count(SummaryState.enough)} alcanzan', SummaryState.enough),
              if (count(SummaryState.missing) > 0)
                _badge('${count(SummaryState.missing)} faltan', SummaryState.missing),
              if (count(SummaryState.open) > 0)
                _badge('${count(SummaryState.open)} fraccionar', SummaryState.open),
              if (count(SummaryState.onDemand) > 0)
                _badge('${count(SummaryState.onDemand)} a pedido', SummaryState.onDemand),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              FilterChip(
                label: const Text('Solo lo que falta'),
                selected: _onlyMissing,
                onSelected: (v) => setState(() => _onlyMissing = v),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.shopping_cart_outlined, size: 18),
                label: const Text('Lista de compras'),
                onPressed: () => _showShoppingList(all),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        _header(withStock),
        for (var i = 0; i < rows.length; i++) _row(rows[i], i.isOdd, withStock),
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Alcanza todo con lo que hay.', textAlign: TextAlign.center),
          ),
      ],
    );
  }

  Widget _header(bool withStock) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    child: Row(
      children: [
        const Expanded(child: Text('Producto', style: TextStyle(fontSize: 12, color: AppColors.gris))),
        const SizedBox(
          width: 52,
          child: Text('Pedido', textAlign: TextAlign.end, style: TextStyle(fontSize: 12, color: AppColors.gris)),
        ),
        if (withStock)
          const SizedBox(
            width: 52,
            child: Text('Hay', textAlign: TextAlign.end, style: TextStyle(fontSize: 12, color: AppColors.gris)),
          ),
      ],
    ),
  );

  Widget _row(SummaryRow r, bool zebra, bool withStock) {
    final textColor = zebra ? _zebraText : null;
    final badge = switch (r.state) {
      SummaryState.missing => r.openParents > 0
          ? 'Abrir ${formatQty(r.openParents)} × ${r.parentName} · faltan ${formatQty(r.missing)}'
          : 'Faltan ${formatQty(r.missing)}',
      SummaryState.open => 'Abrir ${formatQty(r.openParents)} × ${r.parentName}',
      SummaryState.onDemand => 'A pedido · comprar ${formatQty(r.missing)}',
      _ => null,
    };
    return Container(
      color: zebra ? _zebra : null,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.line.name, style: TextStyle(fontWeight: FontWeight.w600, color: textColor)),
                if (withStock && r.closedName != null)
                  Text(
                    'Sueltos ${r.have == null ? '—' : formatQty(r.have!)} · '
                    '${r.closedName}: ${r.closedStock == null ? '—' : formatQty(r.closedStock!)}',
                    style: TextStyle(fontSize: 12, color: textColor ?? AppColors.gris),
                  ),
                if (badge != null) ...[
                  const SizedBox(height: 3),
                  _badge(badge, r.state),
                ],
              ],
            ),
          ),
          SizedBox(
            width: 52,
            child: Text(
              formatQty(r.line.quantity),
              textAlign: TextAlign.end,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textColor),
            ),
          ),
          if (withStock)
            SizedBox(
              width: 52,
              child: Text(
                r.have == null ? '—' : formatQty(r.have!),
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontSize: 16,
                  color: r.state == SummaryState.enough
                      ? AppColors.verde
                      : r.have == null
                      ? (textColor ?? AppColors.gris)
                      : AppColors.rojo,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _badge(String text, SummaryState state) {
    final (bg, fg) = switch (state) {
      SummaryState.enough => (const Color(0xFFEAF3DE), const Color(0xFF27500A)),
      SummaryState.missing => (const Color(0xFFFCEBEB), const Color(0xFF791F1F)),
      SummaryState.open => (const Color(0xFFEEEDFE), const Color(0xFF3C3489)),
      _ => (const Color(0xFFF1EFE8), const Color(0xFF444441)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(fontSize: 12, color: fg, fontWeight: FontWeight.w600)),
    );
  }
}
