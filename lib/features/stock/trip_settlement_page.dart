import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_theme.dart';
import '../../core/desktop_records.dart';
import '../../core/money_format.dart';
import 'stock_audit_data.dart';
import 'stock_data.dart';

String _two(int n) => n.toString().padLeft(2, '0');
String _when(DateTime? d) => d == null ? '' : '${_two(d.day)}/${_two(d.month)} ${_two(d.hour)}:${_two(d.minute)}';
String _q(double v) => formatQty(v);

/// Liquidación del viaje: la cuenta de cada producto, con motivo para cada diferencia.
/// Se puede dejar sin terminar: lo que queda sin motivo aparece en "Stock a revisar".
class TripSettlementPage extends StatefulWidget {
  const TripSettlementPage({super.key, required this.tripId, this.client, this.loader, this.saver});
  final String tripId;
  final SupabaseClient? client;

  /// Solo para pruebas.
  final Future<TripSettlement> Function()? loader;
  final Future<void> Function(List<({String productId, String? reason, String? note})>)? saver;

  @override
  State<TripSettlementPage> createState() => _TripSettlementPageState();
}

class _TripSettlementPageState extends State<TripSettlementPage> {
  SupabaseClient get _client => widget.client ?? Supabase.instance.client;
  TripSettlement? _data;
  String? _error;
  bool _saving = false;
  bool _showMatching = false;

  /// Motivos y notas elegidos acá (todavía sin guardar).
  final _reasons = <String, String?>{};
  final _notes = <String, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _notes.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final loader = widget.loader;
      final data = loader != null ? await loader() : await fetchTripSettlement(_client, widget.tripId);
      if (!mounted) return;
      setState(() {
        _data = data;
        _reasons.clear();
        for (final r in data.withDifference) {
          _reasons[r.productId] = r.reason;
          _notes.putIfAbsent(r.productId, TextEditingController.new).text = r.note ?? '';
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = stockErrorText(error));
    }
  }

  List<({String productId, String? reason, String? note})> get _changes {
    final data = _data;
    if (data == null) return const [];
    return [
      for (final r in data.withDifference)
        if (_reasons[r.productId] != r.reason || (_notes[r.productId]?.text.trim() ?? '') != (r.note ?? ''))
          (
            productId: r.productId,
            reason: _reasons[r.productId],
            note: _notes[r.productId]?.text.trim().isEmpty ?? true ? null : _notes[r.productId]!.text.trim(),
          ),
    ];
  }

  Future<void> _save() async {
    final changes = _changes;
    if (changes.isEmpty) {
      _snack('No hay cambios para guardar.');
      return;
    }
    if (changes.any((c) => c.reason == 'otro' && c.note == null)) {
      _snack('Con "Otro", escribí qué pasó.');
      return;
    }
    setState(() => _saving = true);
    try {
      final saver = widget.saver;
      if (saver != null) {
        await saver(changes);
      } else {
        await saveSettlementReasons(_client, widget.tripId, changes);
      }
      final left = _data!.withDifference.where((r) => _reasons[r.productId] == null).length;
      _snack(left == 0
          ? 'Liquidación completa.'
          : 'Guardado. ${left == 1 ? 'Queda 1 diferencia' : 'Quedan $left diferencias'} sin motivo (en "Stock a revisar").');
      if (widget.loader == null) await _load();
    } catch (error) {
      _snack(stockErrorText(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _sharePdf() async {
    final data = _data;
    if (data == null) return;
    try {
      final bytes = await _pdf(data);
      final name = 'Liquidacion_viaje_${data.openedAt == null ? data.tripId.substring(0, 8) : isoDay(data.openedAt!)}.pdf';
      final file = File('${Directory.systemTemp.path}${Platform.pathSeparator}$name');
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/pdf', name: name)],
          subject: 'Liquidación del viaje',
          text: 'Liquidación del viaje ${_when(data.openedAt)}',
        ),
      );
    } catch (error) {
      _snack('No se pudo armar el PDF: $error');
    }
  }

  Future<Uint8List> _pdf(TripSettlement d) async {
    final doc = pw.Document();
    String reasonOf(SettlementRow r) {
      final code = _reasons[r.productId] ?? r.reason;
      if (code == null) return r.hasDifference ? 'Sin motivo' : '';
      final note = _notes[r.productId]?.text.trim() ?? r.note ?? '';
      return '${settlementReasons[code] ?? code}${note.isEmpty ? '' : ': $note'}';
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => [
          pw.Text('DISTRIBUIDORA ALBERDI · Liquidación del viaje',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text('Salió ${_when(d.openedAt)} · cerró ${_when(d.closedAt)}'
              '${d.seller == null ? '' : ' · con ${d.seller}'}${d.closedBy == null ? '' : ' · cerró ${d.closedBy}'}'),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers: ['Producto', 'Tenía', 'Cargó', 'Del dep.', 'Vendió', 'Devol.', 'Bajó', 'Otros', 'Debía', 'Contado', 'Dif.', 'Motivo'],
            data: [
              for (final r in d.rows)
                [
                  r.name,
                  _q(r.had),
                  _q(r.loaded),
                  _q(r.fromDeposit),
                  _q(r.sold),
                  _q(r.returned),
                  _q(r.unloaded),
                  _q(r.other),
                  _q(r.expected),
                  r.counted == null ? '-' : _q(r.counted!),
                  _q(r.difference),
                  reasonOf(r),
                ],
            ],
            cellStyle: const pw.TextStyle(fontSize: 8),
            headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
            cellAlignment: pw.Alignment.centerRight,
            cellAlignments: {0: pw.Alignment.centerLeft, 11: pw.Alignment.centerLeft},
          ),
          pw.SizedBox(height: 12),
          pw.Text('Ventas y entregas: ${d.salesCount} · ${formatoPesos(d.salesTotal)}'),
          for (final e in d.payments.entries) pw.Text('${e.key}: ${formatoPesos(e.value)}'),
          pw.Text('Cobrado: ${formatoPesos(d.collected)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
    return doc.save();
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final t = Tonos.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(data?.openedAt == null ? 'Liquidación' : 'Liquidación · ${_when(data!.openedAt)}'),
        actions: [
          IconButton(
            tooltip: 'Compartir PDF',
            onPressed: data == null ? null : _sharePdf,
            icon: const Icon(Icons.picture_as_pdf_outlined),
          ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!, textAlign: TextAlign.center),
                  TextButton(onPressed: _load, child: const Text('Reintentar')),
                ],
              ),
            )
          : data == null
          ? const Center(child: CircularProgressIndicator())
          : DesktopForm(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
                children: [
                  Text(
                    [
                      'Salió ${_when(data.openedAt)}',
                      if (data.closedAt != null) 'cerró ${_when(data.closedAt)}',
                      if (data.seller != null) 'con ${data.seller}',
                    ].join(' · '),
                    style: TextStyle(color: t.secundario),
                  ),
                  if (data.open)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text('El viaje sigue abierto: los números son hasta este momento.'),
                    )
                  else if (!data.counted)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text('Se cerró sin contar lo que volvió: no hay diferencias para revisar.'),
                    ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _pill('${data.matching.length} cuadran', const Color(0xFFE1F5EE), const Color(0xFF085041)),
                      if (data.withDifference.isNotEmpty)
                        _pill('${data.withDifference.length} con diferencia', const Color(0xFFFCEBEB), const Color(0xFF791F1F)),
                      if (data.fromDepositCount > 0)
                        _pill('${data.fromDepositCount} tomado del depósito', const Color(0xFFFAEEDA), const Color(0xFF633806)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  for (final r in data.withDifference) _row(r, withReason: true),
                  for (final r in data.matching.where((r) => r.fromDeposit > 0)) _row(r),
                  TextButton.icon(
                    onPressed: () => setState(() => _showMatching = !_showMatching),
                    icon: Icon(_showMatching ? Icons.expand_less : Icons.expand_more),
                    label: Text('${data.matching.where((r) => r.fromDeposit <= 0).length} productos que cuadran'),
                  ),
                  if (_showMatching)
                    for (final r in data.matching.where((r) => r.fromDeposit <= 0)) _row(r),
                  const Divider(height: 24),
                  _money('Ventas y entregas (${data.salesCount})', data.salesTotal),
                  for (final e in data.payments.entries) _money(e.key, e.value),
                  _money('Cobrado', data.collected, bold: true),
                  const SizedBox(height: 16),
                  if (data.withDifference.isNotEmpty && !data.open)
                    FilledButton.icon(
                      key: const Key('guardar-liquidacion'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.dorado,
                        foregroundColor: AppColors.negro,
                      ),
                      onPressed: _saving ? null : _save,
                      icon: const Icon(Icons.check),
                      label: const Text('GUARDAR MOTIVOS'),
                    ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _sharePdf,
                    icon: const Icon(Icons.share_outlined),
                    label: const Text('COMPARTIR PDF'),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _pill(String text, Color bg, Color fg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
    child: Text(text, style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 12)),
  );

  Widget _money(String label, double value, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(child: Text(label, style: TextStyle(fontWeight: bold ? FontWeight.bold : null))),
        Text(formatoPesos(value), style: TextStyle(fontWeight: bold ? FontWeight.bold : null)),
      ],
    ),
  );

  Widget _row(SettlementRow r, {bool withReason = false}) {
    final t = Tonos.of(context);
    final borde = r.hasDifference
        ? AppColors.rojo
        : r.fromDeposit > 0
        ? AppColors.naranja
        : (t.oscuro ? Colors.white24 : AppColors.borde);
    final cols = <(String, double)>[
      ('Tenía', r.had),
      ('Cargó', r.loaded),
      if (r.fromDeposit != 0) ('Del dep.', r.fromDeposit),
      ('Vendió', r.sold),
      if (r.returned != 0) ('Devol.', r.returned),
      if (r.unloaded != 0) ('Bajó', r.unloaded),
      if (r.other != 0) ('Otros', r.other),
      ('Debía', r.expected),
      if (r.counted != null) ('Contado', r.counted!),
    ];
    final reason = _reasons[r.productId];
    return Card(
      key: ValueKey('liq-${r.productId}'),
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borde, width: r.hasDifference || r.fromDeposit > 0 ? 1.5 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(r.name, style: const TextStyle(fontWeight: FontWeight.bold))),
                if (r.hasDifference)
                  Text(
                    r.difference > 0 ? '+${_q(r.difference)}' : _q(r.difference),
                    style: TextStyle(color: t.rojo, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final c in cols)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: c.$1 == 'Del dep.'
                          ? (t.oscuro ? const Color(0xFF412402) : const Color(0xFFFAEEDA))
                          : (t.oscuro ? Colors.white10 : const Color(0xFFF1EFE8)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('${c.$1} ${_q(c.$2)}', style: const TextStyle(fontSize: 12.5)),
                  ),
              ],
            ),
            if (r.fromDeposit > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Se tomó ${_q(r.fromDeposit)} del depósito porque no alcanzaba arriba.',
                  style: TextStyle(fontSize: 12, color: t.secundario),
                ),
              ),
            if (withReason) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: ValueKey('motivo-${r.productId}'),
                initialValue: reason,
                isExpanded: true,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Motivo',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<String>(value: null, child: Text('Sin motivo todavía')),
                  for (final e in settlementReasons.entries)
                    DropdownMenuItem<String>(value: e.key, child: Text(e.value)),
                ],
                onChanged: _data!.open ? null : (v) => setState(() => _reasons[r.productId] = v),
              ),
              if (reason != null) ...[
                const SizedBox(height: 6),
                TextField(
                  controller: _notes.putIfAbsent(r.productId, TextEditingController.new),
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: reason == 'otro' ? 'Qué pasó (obligatorio)' : 'Nota (opcional)',
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// Viajes recientes: abre la liquidación de cada uno.
class TripListPage extends StatefulWidget {
  const TripListPage({super.key, this.client});
  final SupabaseClient? client;

  @override
  State<TripListPage> createState() => _TripListPageState();
}

class _TripListPageState extends State<TripListPage> {
  SupabaseClient get _client => widget.client ?? Supabase.instance.client;
  List<TripSummary>? _trips;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final trips = await fetchRecentTrips(_client);
      if (mounted) setState(() => _trips = trips);
    } catch (error) {
      if (mounted) setState(() => _error = stockErrorText(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final trips = _trips;
    return Scaffold(
      appBar: AppBar(title: const Text('Liquidaciones')),
      body: _error != null
          ? Center(child: Text(_error!))
          : trips == null
          ? const Center(child: CircularProgressIndicator())
          : trips.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Todavía no hay viajes.\nSe abren al cargar el vehículo.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : DesktopForm(
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  for (final v in trips)
                    Card(
                      child: ListTile(
                        title: Text('Viaje ${_when(v.openedAt)}${v.seller == null ? '' : ' · ${v.seller}'}'),
                        subtitle: Text(
                          v.open
                              ? 'Abierto'
                              : v.differences == 0
                              ? 'Cuadró todo'
                              : '${v.differences} con diferencia'
                                    '${v.withoutReason == 0 ? ' · motivos completos' : ' · ${v.withoutReason} sin motivo'}',
                        ),
                        trailing: v.withoutReason > 0
                            ? const Icon(Icons.error_outline, color: AppColors.rojo)
                            : const Icon(Icons.chevron_right),
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => TripSettlementPage(tripId: v.id, client: widget.client),
                            ),
                          );
                          _load();
                        },
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
