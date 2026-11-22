import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_config.dart';
import '../../core/app_theme.dart';
import '../../core/money_format.dart';

/// Lo vendido hoy: preventa entregada o venta directa, con cómo se cobró.
class DaySales {
  const DaySales({
    this.total = 0,
    this.delivered = 0,
    this.partial = 0,
    this.notDelivered = 0,
    this.units = 0,
    this.byMethod = const {},
    this.owed = 0,
    this.topProduct,
    this.topUnits = 0,
  });

  /// Entregado (preventa) o vendido (venta directa), a precio de venta.
  final double total;
  final int delivered;
  final int partial;
  final int notDelivered;
  final double units;

  /// Cobrado en esas entregas o ventas, por medio ("Efectivo", "Transferencia"...).
  final Map<String, double> byMethod;

  /// Lo que quedó a cuenta (entregado y todavía sin cobrar).
  final double owed;
  final String? topProduct;
  final double topUnits;

  int get count => delivered + partial;

  /// Arma el resumen con las filas de pedidos finalizados hoy (con detalles y pagos).
  factory DaySales.fromRows(List<Map<String, dynamic>> rows) {
    double n(Object? v) => v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
    var total = 0.0, units = 0.0, owed = 0.0;
    var delivered = 0, partial = 0, notDelivered = 0;
    final byMethod = <String, double>{};
    final byProduct = <String, double>{};
    for (final p in rows) {
      switch (p['resultado_entrega']?.toString()) {
        case 'entregado':
          delivered++;
        case 'parcial':
          partial++;
        case 'no_entregado':
          notDelivered++;
      }
      var amount = 0.0;
      for (final d in (p['pedido_detalles'] as List? ?? const [])) {
        final row = d as Map;
        final q = n(row['cantidad_entregada']);
        amount += q * n(row['precio_unitario']);
        units += q;
        final name = (row['productos'] as Map?)?['nombre']?.toString();
        if (name != null && q > 0) byProduct[name] = (byProduct[name] ?? 0) + q;
      }
      var paid = 0.0;
      for (final pago in (p['pedido_pagos'] as List? ?? const [])) {
        final row = pago as Map;
        final medio = (row['medio_pago']?.toString().trim().isNotEmpty ?? false) ? row['medio_pago'].toString() : 'Otro';
        byMethod[medio] = (byMethod[medio] ?? 0) + n(row['importe']);
        paid += n(row['importe']);
      }
      total += amount;
      if (amount > paid) owed += amount - paid;
    }
    String? top;
    var topUnits = 0.0;
    for (final e in byProduct.entries) {
      if (e.value > topUnits) {
        top = e.key;
        topUnits = e.value;
      }
    }
    return DaySales(
      total: total,
      delivered: delivered,
      partial: partial,
      notDelivered: notDelivered,
      units: units,
      byMethod: byMethod,
      owed: owed,
      topProduct: top,
      topUnits: topUnits,
    );
  }
}

/// Lee lo finalizado hoy (preventa o venta directa) para la tarjeta "Venta del día".
Future<DaySales> fetchDaySales(SupabaseClient client, {required bool direct, DateTime? now}) async {
  final today = now ?? DateTime.now();
  final start = DateTime(today.year, today.month, today.day);
  final rows = await client
      .from('pedidos')
      .select('''
        id, resultado_entrega,
        pedido_detalles ( cantidad_entregada, precio_unitario, productos ( nombre ) ),
        pedido_pagos ( importe, medio_pago )
      ''')
      .eq('tipo_operacion', direct ? 'venta_directa' : 'pedido')
      .not('estado', 'in', '(cancelado,anulado)')
      .gte('fecha_finalizacion', start.toUtc().toIso8601String())
      .lt('fecha_finalizacion', start.add(const Duration(days: 1)).toUtc().toIso8601String());
  return DaySales.fromRows(List<Map<String, dynamic>>.from(rows));
}

/// Tarjeta desplegable "Venta del día" arriba de Reparto. Se recuerda si quedó abierta o cerrada.
class DaySalesCard extends StatefulWidget {
  const DaySalesCard({
    super.key,
    required this.direct,
    required this.sales,
    this.pendingCount = 0,
    this.pendingTotal = 0,
    this.error,
  });

  final bool direct;

  /// null mientras se lee.
  final DaySales? sales;

  /// Preventa: lo que falta entregar (lo que muestra la lista).
  final int pendingCount;
  final double pendingTotal;
  final String? error;

  @override
  State<DaySalesCard> createState() => _DaySalesCardState();
}

class _DaySalesCardState extends State<DaySalesCard> {
  bool _open = true;
  String get _key => appConfig.localPreferenceKey('reparto_venta_del_dia_abierta');

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      final saved = prefs.getBool(_key);
      if (saved != null && mounted) setState(() => _open = saved);
    }).catchError((_) {});
  }

  void _toggle() {
    setState(() => _open = !_open);
    SharedPreferences.getInstance().then((prefs) => prefs.setBool(_key, _open)).catchError((_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final oscuro = Tonos.of(context).oscuro;
    final fondo = oscuro ? const Color(0xFF083A2F) : const Color(0xFFE1F5EE);
    final texto = oscuro ? const Color(0xFF9FE1CB) : const Color(0xFF085041);
    final fuerte = oscuro ? const Color(0xFF1D9E75) : const Color(0xFF0F6E56);
    final s = widget.sales;
    final title = widget.direct ? 'Venta del día · directa' : 'Venta del día · preventa';
    final amount = s == null ? '…' : formatoPesos(s.total);
    TextStyle style([bool bold = false]) =>
        TextStyle(color: texto, fontSize: 14, fontWeight: bold ? FontWeight.bold : FontWeight.normal);
    Widget row(String left, String right, {bool bold = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(left, style: style())),
          Text(right, style: style(bold)),
        ],
      ),
    );
    Widget line() => Divider(height: 12, color: texto.withValues(alpha: 0.3));
    final expected = (s?.total ?? 0) + widget.pendingTotal;
    final progress = expected <= 0 ? 0.0 : (s?.total ?? 0) / expected;
    final details = <Widget>[
      if (widget.error != null)
        Text(widget.error!, style: style())
      else if (s == null)
        Text('Leyendo…', style: style())
      else if (!widget.direct) ...[
        row('Entregado', formatoPesos(s.total), bold: true),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 7,
              color: fuerte,
              backgroundColor: texto.withValues(alpha: 0.2),
            ),
          ),
        ),
        row(
          'de ${formatoPesos(expected)} esperado',
          '${(progress * 100).round()} %',
        ),
        row(
          'Pedidos',
          [
            '${s.delivered} entregados',
            if (s.partial > 0) '${s.partial} parcial${s.partial == 1 ? '' : 'es'}',
            if (s.notDelivered > 0) '${s.notDelivered} no',
            '${widget.pendingCount} faltan',
          ].join(' · '),
        ),
      ] else ...[
        row('Vendido', formatoPesos(s.total), bold: true),
        row('Ventas', '${s.count} · ${formatoNumero(s.units)} unidades'),
      ],
      if (s != null && widget.error == null) ...[
        line(),
        for (final e in (s.byMethod.entries.toList()..sort((a, b) => b.value.compareTo(a.value))))
          row(e.key, formatoPesos(e.value)),
        if (s.byMethod.isEmpty) row('Cobrado', formatoPesos(0)),
        row('Quedó a cuenta', formatoPesos(s.owed)),
        if (widget.direct && s.topProduct != null) ...[
          line(),
          row('Lo más vendido', '${s.topProduct} × ${formatoNumero(s.topUnits)}'),
        ],
      ],
    ];
    return Material(
      key: const Key('venta-del-dia'),
      color: fondo,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _toggle,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(widget.direct ? Icons.point_of_sale_outlined : Icons.local_shipping_outlined, color: texto),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _open ? title : '$title  $amount',
                      style: TextStyle(color: texto, fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                  Icon(_open ? Icons.expand_less : Icons.expand_more, color: texto),
                ],
              ),
              if (_open) ...[const SizedBox(height: 6), ...details],
            ],
          ),
        ),
      ),
    );
  }
}
