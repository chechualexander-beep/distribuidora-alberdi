import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_theme.dart';
import '../../core/desktop_records.dart';
import '../../core/money_format.dart';
import '../../core/network_status.dart';
import '../orders/order_whatsapp_button.dart';
import '../orders/payment_choice.dart';
import '../stock/stock_data.dart';
import 'special_sale_data.dart';

/// Venta especial del administrador: precio a mano, margen en vivo, stock del depósito o del
/// vehículo, sin comisión; se cobra en el momento (o queda fiado al cliente). Base del mostrador.
class SpecialSalePage extends StatefulWidget {
  const SpecialSalePage({super.key, this.client, this.runner, this.products, this.clients});
  final SupabaseClient? client;

  /// Solo para pruebas.
  final StockOpRunner? runner;
  final List<SaleProduct>? products;
  final List<SaleClient>? clients;

  @override
  State<SpecialSalePage> createState() => _SpecialSalePageState();
}

class _SpecialSalePageState extends State<SpecialSalePage> {
  SupabaseClient get _client => widget.client ?? Supabase.instance.client;
  List<SaleProduct>? _products;
  List<SaleClient> _clients = const [];
  String? _error;
  bool _saving = false;
  SaleClient _buyer = SaleClient.finalConsumer;
  String _location = depositoCodigo;
  final _lines = <SaleLine>[];
  final _qty = <SaleLine, TextEditingController>{};
  final _price = <SaleLine, TextEditingController>{};
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _products = widget.products;
    _clients = widget.clients ?? const [];
    if (_products == null) _load();
  }

  @override
  void dispose() {
    for (final c in [..._qty.values, ..._price.values, _search]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final products = await fetchSaleProducts(_client);
      final clients = await fetchSaleClients(_client);
      if (!mounted) return;
      setState(() {
        _products = products;
        _clients = clients;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = isUncertainRequestError(error)
          ? 'Sin conexión. Probá de nuevo cuando haya señal.'
          : 'No se pudo cargar: ${stockErrorText(error)}');
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  static String _normalize(String t) => t
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ñ', 'n')
      .trim();

  List<SaleProduct> get _matches {
    final text = _normalize(_search.text);
    if (text.isEmpty) return const [];
    return (_products ?? const <SaleProduct>[])
        .where((p) => _normalize(p.name).contains(text) || p.code.toLowerCase().contains(text))
        .take(8)
        .toList();
  }

  void _add(SaleProduct p) {
    setState(() {
      final existing = _lines.where((l) => l.product.id == p.id).firstOrNull;
      if (existing != null) {
        existing.quantity += 1;
        _qty[existing]!.text = formatQty(existing.quantity);
      } else {
        final line = SaleLine(p, price: p.priceFor(_buyer.priceList));
        _lines.add(line);
        _qty[line] = TextEditingController(text: '1');
        _price[line] = TextEditingController(text: importeEditable(line.price));
      }
      _search.clear();
    });
  }

  void _remove(SaleLine line) => setState(() {
    _lines.remove(line);
    _qty.remove(line)?.dispose();
    _price.remove(line)?.dispose();
  });

  Future<void> _pickBuyer() async {
    final picked = await showDialog<SaleClient>(
      context: context,
      builder: (context) {
        final filter = TextEditingController();
        return StatefulBuilder(
          builder: (context, set) {
            final text = _normalize(filter.text);
            final list = [
              SaleClient.finalConsumer,
              ..._clients.where((c) => text.isEmpty || _normalize(c.name).contains(text)),
            ];
            return AlertDialog(
              title: const Text('¿A quién le vendés?'),
              content: SizedBox(
                width: 420,
                height: 420,
                child: Column(
                  children: [
                    TextField(
                      controller: filter,
                      autofocus: true,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Buscar cliente...',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => set(() {}),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView(
                        children: [
                          for (final c in list.take(60))
                            ListTile(
                              dense: true,
                              leading: Icon(c.isFinalConsumer ? Icons.person_outline : Icons.store_outlined),
                              title: Text(c.name),
                              onTap: () => Navigator.pop(context, c),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar'))],
            );
          },
        );
      },
    );
    if (picked != null) setState(() => _buyer = picked);
  }

  Future<void> _editLineTotal(SaleLine line) async {
    final controller = TextEditingController(text: importeEditable(line.total));
    final total = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Total de ${formatQty(line.quantity)} × ${line.product.name}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: const [ImporteInputFormatter()],
          decoration: const InputDecoration(prefixText: '\$', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, leerImporte(controller.text)), child: const Text('Listo')),
        ],
      ),
    );
    if (total == null || line.quantity <= 0) return;
    setState(() {
      line.price = (total / line.quantity * 100).round() / 100;
      _price[line]!.text = importeEditable(line.price);
    });
  }

  Future<void> _confirm() async {
    if (_lines.isEmpty) {
      _snack('Agregá al menos un producto.');
      return;
    }
    if (_lines.any((l) => l.quantity <= 0)) {
      _snack('Revisá las cantidades: tienen que ser mayores que 0.');
      return;
    }
    final total = saleTotal(_lines);
    final choice = await showPaymentChoice(context, aCobrar: total, detalle: 'Venta especial · ${_buyer.name}');
    if (choice == null || !mounted) return;
    final payments = <String, double>{
      if (choice.todo != null) choice.todo!: total,
      if (choice.todo == null && choice.efectivo > 0) 'Efectivo': choice.efectivo,
      if (choice.todo == null && choice.transferencia > 0) 'Transferencia': choice.transferencia,
    };
    final paid = payments.values.fold<double>(0, (s, v) => s + v);
    if (_buyer.isFinalConsumer && (total - paid).abs() > 0.005) {
      _snack('A "Consumidor final" no se le puede fiar: cobrá el total.');
      return;
    }
    final args = <String, dynamic>{
      'p_cliente_id': _buyer.isFinalConsumer ? null : _buyer.id,
      'p_ubicacion': _location,
      'p_items': [
        for (final l in _lines) {'producto_id': l.product.id, 'cantidad': l.quantity, 'precio_unitario': l.price},
      ],
      'p_pagos': [
        for (final e in payments.entries) {'medio': e.key, 'importe': e.value},
      ],
      'p_observacion': null,
    };
    setState(() => _saving = true);
    final StockOpOutcome outcome;
    try {
      final runner = widget.runner;
      outcome = runner != null
          ? await runner('venta_especial', args)
          : await runStockOp(
              _client,
              rpc: 'venta_especial',
              args: args,
              description: 'Venta especial · ${_buyer.name}',
              total: total,
            );
    } catch (error) {
      if (mounted) setState(() => _saving = false);
      _snack(stockErrorText(error));
      return;
    }
    if (!mounted) return;
    setState(() => _saving = false);
    final message = saleMessage(lines: _lines, payments: payments);
    await _showDone(outcome, total, paid, message);
    if (!mounted) return;
    setState(() {
      for (final c in [..._qty.values, ..._price.values]) {
        c.dispose();
      }
      _qty.clear();
      _price.clear();
      _lines.clear();
    });
    if (widget.runner == null && !outcome.savedOffline) _load();
  }

  Future<void> _showDone(StockOpOutcome outcome, double total, double paid, String message) async {
    final result = outcome.result;
    final t = Tonos.of(context);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(result == null ? Icons.cloud_upload_outlined : Icons.check_circle_outline, size: 44),
        title: Text(result == null ? 'Guardada en el teléfono' : 'Venta registrada'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (result == null)
              const Text('No hay señal: se envía sola cuando vuelva la conexión (en "Pendientes de enviar").'),
            Text('Total ${formatoPesos(total)} · cobrado ${formatoPesos(paid)}'),
            if (result != null)
              Text(
                'Ganancia ${formatoPesos(stockNum(result['ganancia']))}',
                style: TextStyle(color: t.verde, fontWeight: FontWeight.w600),
              ),
            if (total - paid > 0.005)
              Text('Quedan ${formatoPesos(total - paid)} en la cuenta de ${_buyer.name}.', style: TextStyle(color: t.rojo)),
            const SizedBox(height: 12),
            if (widget.runner == null)
              _buyer.isFinalConsumer
                  ? OutlinedButton.icon(
                      icon: const Icon(Icons.share),
                      label: const Text('Mandar el detalle'),
                      onPressed: () async {
                        try {
                          await SharePlus.instance.share(ShareParams(text: message));
                        } catch (_) {}
                      },
                    )
                  : OrderWhatsAppButton(clientId: _buyer.id, message: () => message, client: widget.client),
          ],
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('NUEVA VENTA'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final products = _products;
    return Scaffold(
      appBar: AppBar(title: const Text('Venta especial')),
      body: products == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          FilledButton(onPressed: _load, child: const Text('Reintentar')),
                        ],
                      ),
                    ),
            )
          : DesktopForm(
              maxWidth: 900,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _pickBuyer,
                          icon: Icon(_buyer.isFinalConsumer ? Icons.person_outline : Icons.store_outlined),
                          label: Text(_buyer.name),
                        ),
                        SegmentedButton<String>(
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(value: depositoCodigo, label: Text('Depósito')),
                            ButtonSegment(value: vehiculoCodigo, label: Text('Vehículo')),
                          ],
                          selected: {_location},
                          onSelectionChanged: (v) => setState(() => _location = v.first),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                    child: TextField(
                      controller: _search,
                      decoration: const InputDecoration(
                        isDense: true,
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Buscar producto para agregar...',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  if (_matches.isNotEmpty)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 260),
                      child: Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12),
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            for (final p in _matches)
                              ListTile(
                                dense: true,
                                title: Text(p.name),
                                subtitle: Text(
                                  '${formatoPesos(p.priceFor(_buyer.priceList))}'
                                  '${p.controlled ? ' · hay ${formatQty(p.stockAt(_location))}' : ' · a pedido'}',
                                ),
                                trailing: const Icon(Icons.add_circle_outline),
                                onTap: () => _add(p),
                              ),
                          ],
                        ),
                      ),
                    ),
                  Expanded(
                    child: _lines.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text('Buscá productos para agregar a la venta.', textAlign: TextAlign.center),
                            ),
                          )
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                            children: [for (final l in _lines) _lineCard(l)],
                          ),
                  ),
                ],
              ),
            ),
      bottomNavigationBar: products == null ? null : _footer(),
    );
  }

  Widget _lineCard(SaleLine l) {
    final t = Tonos.of(context);
    final p = l.product;
    final stock = p.stockAt(_location);
    final (bg, fg) = p.cost <= 0
        ? t.etiquetaGris
        : l.belowCost
        ? t.etiquetaRoja
        : t.etiquetaVerde;
    final badge = p.cost <= 0
        ? 'Sin costo cargado'
        : l.belowCost
        ? 'Debajo del costo: perdés ${formatoPesos(-l.profit)}'
        : 'Ganás ${formatoPesos(l.profit)} · ${((l.margin ?? 0) * 100).toStringAsFixed(1).replaceAll('.', ',')}%';
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(p.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
                InkWell(
                  onTap: () => _editLineTotal(l),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Text(formatoPesos(l.total), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
                IconButton(tooltip: 'Quitar', icon: const Icon(Icons.close), onPressed: () => _remove(l)),
              ],
            ),
            Row(
              children: [
                SizedBox(
                  width: 72,
                  child: TextField(
                    key: ValueKey('cant-${p.id}'),
                    controller: _qty[l],
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.end,
                    decoration: const InputDecoration(isDense: true, labelText: 'Cant.', border: OutlineInputBorder()),
                    onChanged: (v) => setState(() => l.quantity = parseQty(v) ?? 0),
                  ),
                ),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('×')),
                SizedBox(
                  width: 120,
                  child: TextField(
                    key: ValueKey('precio-${p.id}'),
                    controller: _price[l],
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: const [ImporteInputFormatter()],
                    textAlign: TextAlign.end,
                    style: TextStyle(fontWeight: FontWeight.bold, color: l.belowCost ? t.rojo : null),
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Precio c/u',
                      prefixText: '\$',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => setState(() => l.price = leerImporte(v) ?? 0),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'lista ${formatoPesos(p.priceFor(_buyer.priceList))}'
                    '${p.cost > 0 ? ' · costo ${formatoPesos(p.cost)}' : ''}',
                    style: TextStyle(fontSize: 12, color: t.secundario),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
                  child: Text(badge, style: TextStyle(fontSize: 12, color: fg, fontWeight: FontWeight.w600)),
                ),
                Text(
                  p.controlled
                      ? 'hay ${formatQty(stock)} en ${_location == vehiculoCodigo ? 'el vehículo' : 'el depósito'}'
                      : 'a pedido (no descuenta stock)',
                  style: TextStyle(fontSize: 12, color: p.controlled && stock < l.quantity ? t.rojo : t.secundario),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _footer() {
    final t = Tonos.of(context);
    final total = saleTotal(_lines);
    final profit = total - saleCost(_lines);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(child: Text('Total', style: TextStyle(fontSize: 16))),
                Text(formatoPesos(total), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              ],
            ),
            Row(
              children: [
                Expanded(child: Text('Ganancia (sin comisión)', style: TextStyle(color: t.secundario))),
                Text(
                  '${formatoPesos(profit)}'
                  '${total > 0 ? ' · ${(profit / total * 100).toStringAsFixed(1).replaceAll('.', ',')}%' : ''}',
                  style: TextStyle(fontWeight: FontWeight.w600, color: profit < 0 ? t.rojo : t.verde),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _saving || _lines.isEmpty ? null : _confirm,
              icon: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.point_of_sale),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('COBRAR Y CONFIRMAR'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
