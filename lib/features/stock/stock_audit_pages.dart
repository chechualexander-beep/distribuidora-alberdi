import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_theme.dart';
import '../../core/desktop_records.dart';
import 'stock_audit_data.dart';
import 'stock_data.dart';

String _two(int n) => n.toString().padLeft(2, '0');
String _when(DateTime d) => '${_two(d.day)}/${_two(d.month)} ${_two(d.hour)}:${_two(d.minute)}';
String _signed(double v) => v > 0 ? '+${formatQty(v)}' : formatQty(v);

/// Historial de un producto: cada movimiento con lugar, quién, contra quién y cómo quedó.
class ProductHistoryPage extends StatefulWidget {
  const ProductHistoryPage({super.key, required this.item, this.client, this.loader});
  final StockItem item;
  final SupabaseClient? client;

  /// Solo para pruebas.
  final Future<List<ProductMovement>> Function()? loader;

  @override
  State<ProductHistoryPage> createState() => _ProductHistoryPageState();
}

class _ProductHistoryPageState extends State<ProductHistoryPage> {
  List<ProductMovement>? _rows;
  String? _error;
  String _place = '';
  int _days = 90;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _rows = null;
      _error = null;
    });
    try {
      final loader = widget.loader;
      final rows = loader != null
          ? await loader()
          : await fetchProductHistory(widget.client ?? Supabase.instance.client, widget.item.id, days: _days);
      if (mounted) setState(() => _rows = rows);
    } catch (error) {
      if (mounted) setState(() => _error = stockErrorText(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Tonos.of(context);
    final rows = _rows?.where((r) => _place.isEmpty || r.place == _place).toList();
    return Scaffold(
      appBar: AppBar(title: Text(widget.item.name)),
      body: DesktopForm(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
              child: Text(
                'Depósito ${formatQty(widget.item.deposit)} · Vehículo ${formatQty(widget.item.vehicle)}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: '', label: Text('Todo')),
                  ButtonSegment(value: depositoCodigo, label: Text('Depósito')),
                  ButtonSegment(value: vehiculoCodigo, label: Text('Vehículo')),
                ],
                selected: {_place},
                onSelectionChanged: (s) => setState(() => _place = s.first),
              ),
            ),
            Expanded(
              child: _error != null
                  ? Center(child: Text(_error!))
                  : rows == null
                  ? const Center(child: CircularProgressIndicator())
                  : rows.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'No hubo movimientos en los últimos $_days días.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                      children: [
                        for (final m in rows)
                          Card(
                            margin: const EdgeInsets.only(bottom: 6),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(
                                color: m.wentNegative ? AppColors.rojo : (t.oscuro ? Colors.white24 : AppColors.borde),
                                width: m.wentNegative ? 1.5 : 1,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '${_when(m.at)} · ${m.label}',
                                          style: const TextStyle(fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      Text(
                                        '${_signed(m.delta)} → ${formatQty(m.after)}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: m.after < 0 ? t.rojo : (m.delta < 0 ? null : t.verde),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    [
                                      placeLabel(m.place),
                                      if (m.user != null) m.user!,
                                      if (m.counterpart != null && m.counterpart!.isNotEmpty) m.counterpart!,
                                      if (m.wentNegative) 'quedó en negativo',
                                    ].join(' · '),
                                    style: TextStyle(fontSize: 12.5, color: m.wentNegative ? t.rojo : t.secundario),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (_days < 365)
                          TextButton(
                            onPressed: () {
                              _days = 365;
                              _load();
                            },
                            child: const Text('Ver hasta un año atrás'),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Movimientos del día: todo lo que movió stock, agrupado por lo que lo generó.
class DayMovementsPage extends StatefulWidget {
  const DayMovementsPage({super.key, this.client, this.loader});
  final SupabaseClient? client;

  /// Solo para pruebas.
  final Future<List<DayMovement>> Function(DateTime day)? loader;

  @override
  State<DayMovementsPage> createState() => _DayMovementsPageState();
}

class _DayMovementsPageState extends State<DayMovementsPage> {
  DateTime _day = DateTime.now();
  List<DayMovement>? _rows;
  String? _error;
  String _place = '';
  final _open = <int>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool get _isToday {
    final n = DateTime.now();
    return _day.year == n.year && _day.month == n.month && _day.day == n.day;
  }

  Future<void> _load() async {
    setState(() {
      _rows = null;
      _error = null;
      _open.clear();
    });
    try {
      final loader = widget.loader;
      final rows = loader != null
          ? await loader(_day)
          : await fetchDayMovements(widget.client ?? Supabase.instance.client, _day);
      if (mounted) setState(() => _rows = rows);
    } catch (error) {
      if (mounted) setState(() => _error = stockErrorText(error));
    }
  }

  void _move(int days) {
    _day = _day.add(Duration(days: days));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = Tonos.of(context);
    const dias = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
    final title = _isToday ? 'hoy' : '${dias[_day.weekday - 1]} ${_two(_day.day)}/${_two(_day.month)}';
    final rows = _rows?.where((r) => _place.isEmpty || r.places.contains(_place)).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text('Movimientos · $title'),
        actions: [
          IconButton(tooltip: 'Día anterior', onPressed: () => _move(-1), icon: const Icon(Icons.chevron_left)),
          IconButton(
            tooltip: 'Día siguiente',
            onPressed: _isToday ? null : () => _move(1),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
      body: DesktopForm(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: '', label: Text('Todo')),
                  ButtonSegment(value: depositoCodigo, label: Text('Depósito')),
                  ButtonSegment(value: vehiculoCodigo, label: Text('Vehículo')),
                ],
                selected: {_place},
                onSelectionChanged: (s) => setState(() => _place = s.first),
              ),
            ),
            Expanded(
              child: _error != null
                  ? Center(child: Text(_error!))
                  : rows == null
                  ? const Center(child: CircularProgressIndicator())
                  : rows.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Ese día no se movió stock.\nUsá las flechas de arriba para ver otro día.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                      children: [
                        for (final (i, m) in rows.indexed)
                          Card(
                            margin: const EdgeInsets.only(bottom: 6),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => setState(() {
                                if (!_open.remove(i)) _open.add(i);
                              }),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            '${_two(m.at.hour)}:${_two(m.at.minute)} · ${m.label}',
                                            style: const TextStyle(fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                        Text('${m.products} ${m.products == 1 ? 'producto' : 'productos'}'),
                                        Icon(_open.contains(i) ? Icons.expand_less : Icons.expand_more, size: 20),
                                      ],
                                    ),
                                    Text(
                                      [
                                        if (m.user != null) m.user!,
                                        if (m.counterpart != null && m.counterpart!.isNotEmpty) m.counterpart!,
                                        m.places.map(placeLabel).join(' y '),
                                      ].join(' · '),
                                      style: TextStyle(fontSize: 12.5, color: t.secundario),
                                    ),
                                    if (_open.contains(i))
                                      for (final l in m.lines)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 4),
                                          child: Row(
                                            children: [
                                              Expanded(child: Text('${l.product} · ${placeLabel(l.place)}')),
                                              Text(
                                                '${_signed(l.delta)} → ${formatQty(l.after)}',
                                                style: TextStyle(color: l.after < 0 ? t.rojo : null),
                                              ),
                                            ],
                                          ),
                                        ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
