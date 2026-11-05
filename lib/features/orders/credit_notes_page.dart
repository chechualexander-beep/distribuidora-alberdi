import '../../core/desktop_records.dart';
import '../../core/desktop_table.dart';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/app_config.dart';
import '../../core/return_outbox.dart';

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
  ReturnOutbox? outbox;
  ReturnRequest? pending;
  bool queueBlocked = false;
  late final String scope =
      '${appConfig.environment.name}:${appConfig.project}';
  late final String actor = db.auth.currentUser?.id ?? '';

  bool get sessionMatches =>
      actor.isNotEmpty &&
      db.auth.currentUser?.id == actor &&
      db.rest.url.replaceFirst(RegExp(r'/$'), '') ==
          '${appConfig.supabaseUrl}/rest/v1';
  bool get canWrite =>
      widget.esAdministrador &&
      sessionMatches &&
      outbox != null &&
      !queueBlocked &&
      pending == null &&
      !saving &&
      !loading &&
      error == null;

  @override
  void initState() {
    super.initState();
    if (widget.esAdministrador) openQueue();
    load();
  }

  Future<void> openQueue() async {
    try {
      if (!sessionMatches) throw const ReturnReview();
      final support = await getApplicationSupportDirectory();
      if (!mounted) return;
      outbox = ReturnOutbox.open(
        p.join(support.path, 'devoluciones_contextuales'),
      );
      refreshQueue();
    } catch (_) {
      if (mounted) setState(() => queueBlocked = true);
    }
  }

  void refreshQueue() {
    if (!mounted) return;
    try {
      final next = outbox?.active(scope, actor, widget.pedidoId);
      setState(() => pending = next);
    } catch (_) {
      setState(() => queueBlocked = true);
    }
  }

  @override
  void dispose() {
    if (!saving) outbox?.close();
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
            'id,producto_id,cantidad,cantidad_entregada,precio_unitario,importe_comision,agregado_en_entrega,productos(nombre)',
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
    if (!canWrite) return;
    final lineas = <Map<String, dynamic>>[];
    double total = 0;
    double ajuste = 0;
    for (final d in detalles) {
      final texto = cantidades[d['id']]!.text.trim().replaceAll(',', '.');
      if (texto.isEmpty) continue;
      final centavos = returnQuantityUnits(texto);
      if (centavos == null || centavos > (disponible(d) * 100).round()) {
        mensaje('Revisá las cantidades. No pueden superar lo disponible.');
        return;
      }
      final cantidad = centavos / 100;
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
    final razon = motivo.text.trim();
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
    if (ok != true || !mounted || !canWrite) return;
    await submit(ReturnOperation.issue, {
      'p_pedido_id': widget.pedidoId,
      'p_motivo': razon,
      'p_detalles': lineas,
    });
  }

  void mensaje(String s) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
    }
  }

  Future<void> submit([
    ReturnOperation? operation,
    Map<String, dynamic>? params,
  ]) async {
    if (!sessionMatches || saving || queueBlocked || outbox == null) return;
    final store = outbox!;
    setState(() => saving = true);
    try {
      final request = operation == null
          ? store.active(scope, actor, widget.pedidoId)
          : store.prepare(scope, actor, widget.pedidoId, operation, params!);
      if (request == null) return;
      refreshQueue();
      final result = await store.send(
        scope: scope,
        actor: actor,
        order: widget.pedidoId,
        id: request.id,
        sessionMatches: () => sessionMatches,
        rpc: (name, payload) async {
          final session = db.auth.currentSession;
          if (!sessionMatches || session == null || session.user.id != actor) {
            throw const ReturnReview();
          }
          return await db
              .rpc(name, params: payload)
              .setHeader('Authorization', 'Bearer ${session.accessToken}');
        },
        requiresReview: (error) =>
            error is PostgrestException &&
                const {
                  'PT403',
                  'PT404',
                  'PT410',
                  'PT412',
                  'PT422',
                  '42501',
                  'P0001',
                }.contains(error.code) ||
            error is PostgrestException &&
                error.code == 'PT409' &&
                error.message != 'stock_en_mantenimiento',
      );
      if (!mounted || !sessionMatches) return;
      await load();
      if (!mounted || !sessionMatches) return;
      final visible = request.operation == ReturnOperation.issue
          ? notas.any((n) => n['id'] == result['nota_id'])
          : recepciones.any((r) => r['id'] == result['recepcion_id']);
      if (error == null && visible) {
        store.seen(scope, actor, widget.pedidoId, request.id);
        if (request.operation == ReturnOperation.issue) {
          motivo.clear();
          for (final c in cantidades.values) {
            c.clear();
          }
        }
        mensaje(
          request.operation == ReturnOperation.issue
              ? 'Nota interna NCI ${result['numero']} confirmada.'
              : 'Recepción confirmada. Ingresó al stock: ${result['cantidad_ingresada']}.',
        );
      }
    } on PostgrestException catch (exception) {
      refreshQueue();
      if (exception.code == 'PGRST202') {
        mensaje(
          'El servidor aún no ofrece devoluciones contextuales. La solicitud se conserva para recuperación.',
        );
      } else {
        reportUnconfirmed();
      }
    } catch (_) {
      refreshQueue();
      reportUnconfirmed();
    } finally {
      if (mounted) {
        refreshQueue();
        setState(() => saving = false);
      } else {
        store.close();
      }
    }
  }

  void reportUnconfirmed() {
    mensaje(
      pending?.state == 'review' || queueBlocked
          ? 'La solicitud requiere revisión. Se conserva en la cola.'
          : 'No se pudo confirmar la operación. Revisá la cola antes de continuar.',
    );
  }

  Future<void> recibir(Map<String, dynamic> detail) async {
    if (!canWrite) return;
    final total = returnQuantityUnits(detail['cantidad'].toString());
    if (total == null || total == 0) return;
    final amounts = await showDialog<(int, int)>(
      context: context,
      builder: (_) => ReturnReceiptDialog(total: total),
    );
    if (amounts == null || !mounted || !canWrite) return;
    await submit(ReturnOperation.receive, {
      'p_detalle_id': detail['id'],
      'p_cantidad_apta': amounts.$1 / 100,
      'p_cantidad_no_apta': amounts.$2 / 100,
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Notas de crédito internas')),
    body: DesktopForm(
      child: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'No válida como comprobante fiscal',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                if (error != null) Text(error!),
                if (queueBlocked)
                  const Text('La cola de devoluciones requiere revisión.'),
                if (pending case final request?)
                  ListTile(
                    title: Text(switch (request.state) {
                      'review' => 'Solicitud de devolución en revisión',
                      'confirmed' =>
                        'Confirmada · falta actualizar el historial',
                      _ => 'Solicitud guardada · pendiente de confirmación',
                    }),
                    trailing: request.state == 'review'
                        ? null
                        : TextButton(
                            onPressed: saving ? null : () => submit(),
                            child: const Text('Recuperar solicitud'),
                          ),
                  ),
                Text(
                  'Entregado original: ${ncMoney(saldo?['total_entregado'])}\nNotas de crédito: ${ncMoney(saldo?['total_notas_credito'])}\nNeto: ${ncMoney(saldo?['total_neto'])}\nPendiente: ${ncMoney(saldo?['saldo_pendiente'])}\nSaldo a favor disponible: ${ncMoney(saldo?['saldo_a_favor'])}',
                ),
                if (widget.esAdministrador &&
                    saldo != null &&
                    error == null) ...[
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
                        DesktopField('Producto', returnLineLabel, width: 260),
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
                              enabled: canWrite,
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
                          enabled: canWrite,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            border: const OutlineInputBorder(),
                            labelText: returnLineLabel(d),
                            helperText:
                                'Disponible: ${disponible(d)} · Precio original: ${ncMoney(d['precio_unitario'])}',
                          ),
                        ),
                      ),
                  TextField(
                    controller: motivo,
                    enabled: canWrite,
                    decoration: const InputDecoration(
                      labelText: 'Motivo de la devolución',
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: canWrite ? emitir : null,
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
                                orElse: () => {},
                              );
                              final recibidas = recepciones.where(
                                (r) => r['detalle_id'] == d['id'],
                              );
                              return ListTile(
                                title: Text(
                                  '${returnLineLabel(original)} · ${d['cantidad']} unidades · ${ncMoney(d['precio_unitario'])}',
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Crédito: ${ncMoney(d['importe'])} · Ajuste comisión: ${ncMoney(d['comision'])}',
                                    ),
                                    Text(
                                      returnReceiptLabel(recibidas.firstOrNull),
                                    ),
                                    if (widget.esAdministrador &&
                                        recibidas.isEmpty)
                                      TextButton(
                                        onPressed: canWrite && error == null
                                            ? () => recibir(d)
                                            : null,
                                        child: const Text(
                                          'Registrar recepción',
                                        ),
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

String returnLineLabel(Map<String, dynamic> row) {
  final name = (row['productos'] as Map?)?['nombre'] ?? 'Producto';
  final kind = row['agregado_en_entrega'] == true ? 'Adicional' : 'Original';
  return '$name · $kind';
}

String returnReceiptLabel(Map<String, dynamic>? row) {
  if (row == null) return 'Pendiente de recepción';
  final good = ncNumber(row['cantidad_apta']);
  final bad = ncNumber(row['cantidad_no_apta']);
  if (good > 0 && bad > 0) {
    return 'Recibido mixto · $good aptas · $bad no aptas';
  }
  if (good > 0 || row['apta_venta'] == true) return 'Recibido apto';
  return 'Recibido no apto';
}

/// Uses integer hundredths to avoid binary rounding in the completeness check.
int? returnQuantityUnits(String text) {
  final normalized = text.trim().replaceAll(',', '.');
  if (!RegExp(r'^\d{1,10}(\.\d{1,2})?$').hasMatch(normalized)) return null;
  final parts = normalized.split('.');
  return int.parse(parts.first) * 100 +
      (parts.length == 1 ? 0 : int.parse(parts.last.padRight(2, '0')));
}

(int, int)? returnReceiptAmounts(String good, String bad, int total) {
  final apt = returnQuantityUnits(good);
  final damaged = returnQuantityUnits(bad);
  if (total <= 0 || apt == null || damaged == null || apt + damaged != total) {
    return null;
  }
  return (apt, damaged);
}

class ReturnReceiptDialog extends StatefulWidget {
  const ReturnReceiptDialog({super.key, required this.total});
  final int total;

  @override
  State<ReturnReceiptDialog> createState() => _ReceiptDialogState();
}

class _ReceiptDialogState extends State<ReturnReceiptDialog> {
  final good = TextEditingController(text: '0');
  final bad = TextEditingController(text: '0');

  @override
  void dispose() {
    good.dispose();
    bad.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final amounts = returnReceiptAmounts(good.text, bad.text, widget.total);
    return AlertDialog(
      title: const Text('Registrar recepción de mercadería'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Total a recibir: ${widget.total / 100}'),
          TextField(
            controller: good,
            decoration: const InputDecoration(labelText: 'Cantidad apta'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
          ),
          TextField(
            controller: bad,
            decoration: const InputDecoration(
              labelText: 'Cantidad dañada o no apta',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Text(
            amounts == null
                ? 'Las cantidades deben completar el total del renglón.'
                : 'Total recibido: ${widget.total / 100}\nIngresará con Stock ON: ${amounts.$1 / 100}\nNo ingresará al stock: ${amounts.$2 / 100}',
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Volver'),
        ),
        FilledButton(
          onPressed: amounts == null
              ? null
              : () => Navigator.pop(context, amounts),
          child: const Text('Confirmar recepción'),
        ),
      ],
    );
  }
}
