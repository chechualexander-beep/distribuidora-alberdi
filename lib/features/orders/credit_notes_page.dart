import '../../core/desktop_records.dart';
import '../../core/desktop_table.dart';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

double ncNumber(Object? v) => double.tryParse(v?.toString() ?? '') ?? 0;
String ncMoney(Object? v) => '\$${ncNumber(v).toStringAsFixed(2)}';
String ncKey() =>
    base64Url.encode(List.generate(24, (_) => Random.secure().nextInt(256)));

class CreditNotesPage extends StatefulWidget {
  const CreditNotesPage({
    super.key,
    required this.pedidoId,
    required this.esAdministrador,
  });
  final String pedidoId;
  final bool esAdministrador;
  @override
  State<CreditNotesPage> createState() => _CreditNotesPageState();
}

class _CreditNotesPageState extends State<CreditNotesPage> {
  final db = Supabase.instance.client;
  final motivo = TextEditingController();
  final cantidades = <String, TextEditingController>{};
  List<Map<String, dynamic>> detalles = [],
      notas = [],
      devoluciones = [],
      recepciones = [];
  Map<String, dynamic>? saldo;
  bool loading = true, saving = false;
  String? error;
  String clave = ncKey();
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    motivo.dispose();
    for (final c in cantidades.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> load() async {
    try {
      final d = await db
          .from('pedido_detalles')
          .select(
            'id,producto_id,cantidad,cantidad_entregada,precio_unitario,importe_comision,productos(nombre)',
          )
          .eq('pedido_id', widget.pedidoId);
      final n = await db
          .from('notas_credito')
          .select()
          .eq('pedido_id', widget.pedidoId)
          .order('fecha', ascending: false);
      final ids = n.map((e) => e['id'].toString()).toList();
      final nd = ids.isEmpty
          ? <Map<String, dynamic>>[]
          : await db
                .from('nota_credito_detalles')
                .select(
                  'id,nota_id,pedido_detalle_id,cantidad,precio_unitario,importe,comision',
                )
                .inFilter('nota_id', ids);
      final di = nd.map((e) => e['id'].toString()).toList();
      final rc = di.isEmpty
          ? <Map<String, dynamic>>[]
          : await db
                .from('recepciones_nota_credito')
                .select()
                .inFilter('detalle_id', di);
      final s = await db
          .from('saldos_pendientes_pedidos')
          .select()
          .eq('pedido_id', widget.pedidoId)
          .maybeSingle();
      if (!mounted) return;
      for (final fila in d) {
        cantidades.putIfAbsent(
          fila['id'].toString(),
          () => TextEditingController(),
        );
      }
      setState(() {
        detalles = List<Map<String, dynamic>>.from(d);
        notas = List<Map<String, dynamic>>.from(n);
        devoluciones = List<Map<String, dynamic>>.from(nd);
        recepciones = List<Map<String, dynamic>>.from(rc);
        saldo = s;
        loading = false;
        error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          error = 'No se pudieron cargar las notas: $e';
          loading = false;
        });
      }
    }
  }

  double disponible(Map<String, dynamic> d) =>
      ncNumber(d['cantidad_entregada']) -
      devoluciones
          .where((n) => n['pedido_detalle_id'] == d['id'])
          .fold<double>(0, (s, n) => s + ncNumber(n['cantidad']));
  Future<void> emitir() async {
    final lineas = <Map<String, dynamic>>[];
    double total = 0;
    double ajuste = 0;
    for (final d in detalles) {
      final texto = cantidades[d['id']]!.text.trim().replaceAll(',', '.');
      if (texto.isEmpty) continue;
      final cantidad = double.tryParse(texto);
      if (cantidad == null ||
          !cantidad.isFinite ||
          cantidad < 0 ||
          cantidad > disponible(d)) {
        mensaje('Revisá las cantidades. No pueden superar lo disponible.');
        return;
      }
      if (cantidad == 0) continue;
      lineas.add({'detalle_id': d['id'], 'cantidad': cantidad});
      total += cantidad * ncNumber(d['precio_unitario']);
      final anteriores = devoluciones.where(
        (n) => n['pedido_detalle_id'] == d['id'],
      );
      final cantidadAnterior = anteriores.fold<double>(
        0,
        (s, n) => s + ncNumber(n['cantidad']),
      );
      final comisionAnterior = anteriores.fold<double>(
        0,
        (s, n) => s + ncNumber(n['comision']),
      );
      ajuste +=
          double.parse(
            (ncNumber(d['importe_comision']) *
                    (cantidad + cantidadAnterior) /
                    ncNumber(d['cantidad_entregada']))
                .toStringAsFixed(2),
          ) -
          comisionAnterior;
    }
    if (lineas.isEmpty || motivo.text.trim().isEmpty) {
      mensaje('Indicá cantidades y motivo.');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar nota de crédito interna'),
        content: Text(
          'Crédito: ${ncMoney(total)}. Se reducirá la deuda o quedará saldo a favor, aplicado a otras deudas si existen. Ajuste de comisión estimado: ${ncMoney(ajuste)}. Se descontará al liquidar. La recepción física se registra después. No se modifica el pedido original.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => saving = true);
    try {
      await db.rpc(
        'crear_nota_credito',
        params: {
          'p_pedido_id': widget.pedidoId,
          'p_motivo': motivo.text.trim(),
          'p_detalles': lineas,
          'p_clave': clave,
        },
      );
      clave = ncKey();
      motivo.clear();
      for (final c in cantidades.values) {
        c.clear();
      }
      await load();
      mensaje('Nota de crédito registrada.');
    } catch (e) {
      mensaje('No se pudo confirmar: $e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  void mensaje(String s) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
    }
  }

  Future<void> recibir(String id, bool apta) async {
    setState(() => saving = true);
    try {
      await db.rpc(
        'recibir_nota_credito',
        params: {'p_detalle_id': id, 'p_apta_venta': apta},
      );
      await load();
    } catch (e) {
      mensaje('No se pudo registrar la recepción: $e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Notas de crédito internas')),
    body: DesktopForm(
      child: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
          ? Center(child: Text(error!))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'No válida como comprobante fiscal',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  'Entregado original: ${ncMoney(saldo?['total_entregado'])}\nNotas de crédito: ${ncMoney(saldo?['total_notas_credito'])}\nNeto: ${ncMoney(saldo?['total_neto'])}\nPendiente: ${ncMoney(saldo?['saldo_pendiente'])}\nSaldo a favor disponible: ${ncMoney(saldo?['saldo_a_favor'])}',
                ),
                if (widget.esAdministrador && saldo != null) ...[
                  const Divider(height: 32),
                  const Text(
                    'Nueva devolución',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  if (useDesktopLayout(context))
                    DesktopRecords(
                      embedded: true,
                      records: detalles
                          .where((d) => disponible(d) > 0)
                          .toList(),
                      fields: [
                        DesktopField(
                          'Producto',
                          (r) => (r['productos'] as Map?)?['nombre'],
                          width: 260,
                        ),
                        DesktopField(
                          'Disponible',
                          disponible,
                          numeric: true,
                          width: 100,
                        ),
                        DesktopField(
                          'Precio original',
                          (r) => ncMoney(r['precio_unitario']),
                          numeric: true,
                          width: 140,
                        ),
                        DesktopField(
                          'Devolver',
                          (r) => SizedBox(
                            width: 120,
                            child: TextField(
                              key: ValueKey('devolver-${r['id']}'),
                              controller: cantidades[r['id']],
                              enabled: !saving,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Cantidad',
                                isDense: true,
                              ),
                            ),
                          ),
                          width: 120,
                        ),
                      ],
                    )
                  else
                    for (final d in detalles.where((d) => disponible(d) > 0))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: TextField(
                          controller: cantidades[d['id']],
                          enabled: !saving,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            border: const OutlineInputBorder(),
                            labelText:
                                d['productos']?['nombre']?.toString() ??
                                'Producto',
                            helperText:
                                'Disponible: ${disponible(d)} · Precio original: ${ncMoney(d['precio_unitario'])}',
                          ),
                        ),
                      ),
                  TextField(
                    controller: motivo,
                    enabled: !saving,
                    decoration: const InputDecoration(
                      labelText: 'Motivo de la devolución',
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: saving ? null : emitir,
                    child: Text(
                      saving ? 'Guardando…' : 'Revisar y confirmar nota',
                    ),
                  ),
                ],
                const Divider(height: 32),
                const Text(
                  'Historial',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                if (notas.isEmpty) const Text('Sin notas de crédito.'),
                for (final n in notas)
                  Card(
                    child: ExpansionTile(
                      title: Text(
                        'NCI ${n['numero']} · ${ncMoney(n['total'])}',
                      ),
                      subtitle: Text('${n['fecha']}\n${n['motivo']}'),
                      children: [
                        for (final d in devoluciones.where(
                          (d) => d['nota_id'] == n['id'],
                        ))
                          Builder(
                            builder: (context) {
                              final original = detalles.firstWhere(
                                (o) => o['id'] == d['pedido_detalle_id'],
                              );
                              final recibidas = recepciones.where(
                                (r) => r['detalle_id'] == d['id'],
                              );
                              return ListTile(
                                title: Text(
                                  '${original['productos']?['nombre']} · ${d['cantidad']} unidades',
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Crédito: ${ncMoney(d['importe'])} · Ajuste comisión: ${ncMoney(d['comision'])}',
                                    ),
                                    Text(
                                      recibidas.isEmpty
                                          ? 'Recepción pendiente'
                                          : recibidas.first['apta_venta'] ==
                                                true
                                          ? 'Recibida, apta para venta'
                                          : 'Recibida, no apta para venta',
                                    ),
                                    if (widget.esAdministrador &&
                                        recibidas.isEmpty)
                                      Wrap(
                                        spacing: 8,
                                        children: [
                                          TextButton(
                                            onPressed: saving
                                                ? null
                                                : () => recibir(d['id'], true),
                                            child: const Text(
                                              'Recibí: apta para venta',
                                            ),
                                          ),
                                          TextButton(
                                            onPressed: saving
                                                ? null
                                                : () => recibir(d['id'], false),
                                            child: const Text('Recibí: dañada'),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
              ],
            ),
    ),
  );
}
