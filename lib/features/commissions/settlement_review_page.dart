import '../../core/desktop_records.dart';
import '../../core/desktop_table.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../orders/credit_notes_page.dart' show ncMoney;

class SettlementReviewPage extends StatefulWidget {
  const SettlementReviewPage({
    super.key,
    required this.preventistaId,
    required this.nombre,
    required this.desde,
    required this.hasta,
    required this.detalleIds,
  });
  final String preventistaId, nombre;
  final DateTime desde, hasta;
  final List<String> detalleIds;
  @override
  State<SettlementReviewPage> createState() => _SettlementReviewPageState();
}

class _SettlementReviewPageState extends State<SettlementReviewPage> {
  final db = Supabase.instance.client;
  Map<String, dynamic>? vista;
  String? error, registrada;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = await db.rpc(
        'previsualizar_liquidacion_nc',
        params: {
          'p_preventista_id': widget.preventistaId,
          'p_detalle_ids': widget.detalleIds,
        },
      );
      if (mounted) {
        setState(() {
          vista = Map<String, dynamic>.from(r);
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> registrar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar liquidación'),
        content: Text(
          'Se registrará como pagada por ${ncMoney(vista!['neto'])}. Los ajustes aplicados quedarán vinculados a esta liquidación.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar pago'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => busy = true);
    try {
      final id = await db.rpc(
        'registrar_liquidacion_con_nc',
        params: {
          'p_preventista_id': widget.preventistaId,
          'p_fecha_desde': widget.desde.toIso8601String().split('T').first,
          'p_fecha_hasta': widget.hasta.toIso8601String().split('T').first,
          'p_detalle_ids': widget.detalleIds,
          'p_token': vista!['token'],
        },
      );
      if (mounted) setState(() => registrada = id.toString());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
        await load();
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Revisar liquidación neta')),
    body: DesktopForm(
      child: error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.info_outline, size: 32),
                    const SizedBox(height: 12),
                    Text(
                      error!.contains('Los detalles cambiaron')
                          ? 'Esta selección contiene pedidos que ya no están disponibles para liquidar. Volvé a Comisiones y calculá nuevamente el período.'
                          : 'No se pudo revisar la liquidación. Intentá nuevamente.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Volver y recalcular'),
                    ),
                    TextButton(
                      onPressed: load,
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            )
          : vista == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  widget.nombre,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text(
                  'Comisiones brutas: ${ncMoney(vista!['bruto'])}\nDescuentos por notas: ${ncMoney(vista!['descuento'])}\nTotal a pagar: ${ncMoney(vista!['neto'])}\nAjustes que quedan pendientes: ${ncMoney(vista!['remanente'])}',
                  style: const TextStyle(fontSize: 20),
                ),
                const SizedBox(height: 16),
                if (registrada == null)
                  FilledButton(
                    onPressed: busy ? null : registrar,
                    child: Text(
                      busy ? 'Registrando…' : 'Confirmar liquidación neta',
                    ),
                  )
                else ...[
                  Text('Liquidación registrada: $registrada'),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.share_outlined),
                    label: const Text('Compartir comprobante interno'),
                    onPressed: () => SharePlus.instance.share(
                      ShareParams(
                        text:
                            'Distribuidora Alberdi\nLiquidación $registrada\n${widget.nombre}\nComisión bruta: ${ncMoney(vista!['bruto'])}\nAjustes: ${ncMoney(vista!['descuento'])}\nPagado: ${ncMoney(vista!['neto'])}\nRemanente de ajustes: ${ncMoney(vista!['remanente'])}',
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                const Text(
                  'Ajustes considerados (se aplican los más antiguos hasta cubrir las comisiones)',
                ),
                if (useDesktopLayout(context))
                  DesktopRecords(
                    embedded: true,
                    records: List<Map<String, dynamic>>.from(
                      vista!['ajustes'] as List,
                    ),
                    fields: [
                      DesktopField('Nota', (r) => r['numero'], width: 100),
                      DesktopField(
                        'Cliente',
                        (r) => r['nombre_comercio'],
                        width: 230,
                      ),
                      DesktopField('Motivo', (r) => r['motivo'], width: 250),
                      DesktopField(
                        'Pendiente',
                        (r) => ncMoney(r['pendiente']),
                        numeric: true,
                        width: 130,
                      ),
                    ],
                  )
                else
                  for (final a in vista!['ajustes'] as List)
                    ListTile(
                      title: Text(
                        'NCI ${a['numero']} · ${a['nombre_comercio']}',
                      ),
                      subtitle: Text(
                        '${a['motivo']}\nPedido: ${a['pedido_id']}',
                      ),
                      trailing: Text(ncMoney(a['pendiente'])),
                    ),
              ],
            ),
    ),
  );
}

class CommissionAdjustmentsPage extends StatelessWidget {
  const CommissionAdjustmentsPage({
    super.key,
    this.preventistaId,
    this.liquidacionId,
  });
  final String? preventistaId, liquidacionId;
  Future<List<Map<String, dynamic>>> load() async {
    final db = Supabase.instance.client;
    if (liquidacionId != null) {
      return await db
          .from('ajustes_comision_aplicados')
          .select(
            'importe, nota_credito_detalles(notas_credito(numero,motivo,pedido_id,clientes(nombre_comercio)))',
          )
          .eq('liquidacion_id', liquidacionId!);
    }
    var q = db.from('ajustes_comision_nc').select();
    if (preventistaId != null) q = q.eq('preventista_id', preventistaId!);
    return await q.order('fecha', ascending: false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Ajustes por notas de crédito')),
    body: DesktopForm(
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: load(),
        builder: (context, s) {
          if (s.hasError) {
            return Center(child: Text('No se pudieron cargar: ${s.error}'));
          }
          if (!s.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (s.data!.isEmpty) {
            return const Center(child: Text('Sin ajustes registrados.'));
          }
          if (useDesktopLayout(context)) {
            Map note(Map a) => liquidacionId == null
                ? a
                : a['nota_credito_detalles']['notas_credito'] as Map;
            return DesktopRecords(
              records: s.data!,
              fields: [
                DesktopField('Nota', (r) => note(r)['numero'], width: 100),
                DesktopField(
                  'Cliente',
                  (r) =>
                      note(r)['nombre_comercio'] ??
                      note(r)['clientes']?['nombre_comercio'],
                  width: 230,
                ),
                DesktopField('Motivo', (r) => note(r)['motivo'], width: 230),
                DesktopField(
                  liquidacionId == null ? 'Pendiente' : 'Aplicado',
                  (r) => ncMoney(
                    liquidacionId == null ? r['pendiente'] : r['importe'],
                  ),
                  numeric: true,
                  width: 130,
                ),
              ],
            );
          }
          return ListView(
            children: s.data!.map((a) {
              final n = liquidacionId == null
                  ? a
                  : a['nota_credito_detalles']['notas_credito'] as Map;
              return ListTile(
                title: Text(
                  'NCI ${n['numero']} · ${n['nombre_comercio'] ?? n['clientes']?['nombre_comercio'] ?? ''}',
                ),
                subtitle: Text(
                  '${n['motivo']}\nPedido: ${n['pedido_id']}\n${liquidacionId == null ? 'Ajuste total: ${ncMoney(a['comision'])} · Pendiente: ${ncMoney(a['pendiente'])}' : 'Aplicado: ${ncMoney(a['importe'])}'}',
                ),
              );
            }).toList(),
          );
        },
      ),
    ),
  );
}
