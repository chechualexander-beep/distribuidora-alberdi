import '../../core/desktop_records.dart';
import '../../core/desktop_table.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../orders/credit_notes_page.dart' show ncKey, ncMoney;

class CreditAccountPage extends StatefulWidget {
  const CreditAccountPage({
    super.key,
    required this.clienteId,
    required this.esAdministrador,
  });
  final String clienteId;
  final bool esAdministrador;
  @override
  State<CreditAccountPage> createState() => _CreditAccountPageState();
}

class _CreditAccountPageState extends State<CreditAccountPage> {
  final db = Supabase.instance.client;
  final importe = TextEditingController(), medio = TextEditingController();
  Map<String, dynamic>? saldo;
  List<Map<String, dynamic>> movimientos = [];
  String? error;
  bool busy = false;
  String clave = ncKey();
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    importe.dispose();
    medio.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final s = await db
          .from('saldos_pendientes_clientes')
          .select()
          .eq('cliente_id', widget.clienteId)
          .single();
      final m = await db
          .from('movimientos_credito_cliente')
          .select('*, pedidos!pedido_origen_id!inner(cliente_id)')
          .eq('pedidos.cliente_id', widget.clienteId)
          .order('fecha', ascending: false);
      if (mounted) {
        setState(() {
          saldo = s;
          movimientos = List<Map<String, dynamic>>.from(m);
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> operar(bool reintegro) async {
    final monto = double.tryParse(importe.text.replaceAll(',', '.'));
    if (reintegro &&
        (monto == null ||
            !monto.isFinite ||
            monto <= 0 ||
            medio.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Indicá importe y medio de pago.')),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          reintegro
              ? 'Confirmar devolución de dinero'
              : 'Aplicar saldo a favor',
        ),
        content: Text(
          reintegro
              ? 'Registrar salida de ${ncMoney(monto)} por ${medio.text}.'
              : 'Se aplicará a las deudas más antiguas del cliente.',
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
    setState(() => busy = true);
    try {
      if (reintegro) {
        await db.rpc(
          'reintegrar_credito_cliente',
          params: {
            'p_cliente_id': widget.clienteId,
            'p_importe': monto,
            'p_medio': medio.text.trim(),
            'p_clave': clave,
          },
        );
        clave = ncKey();
        importe.clear();
      } else {
        await db.rpc(
          'aplicar_credito_cliente',
          params: {'p_cliente_id': widget.clienteId},
        );
      }
      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('No se pudo registrar: $e')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Créditos y reintegros')),
    body: DesktopForm(
      child: error != null
          ? Center(child: Text(error!))
          : saldo == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'Notas de crédito: ${ncMoney(saldo!['total_notas_credito'])}\nDeuda pendiente: ${ncMoney(saldo!['saldo_pendiente'])}\nSaldo a favor disponible: ${ncMoney(saldo!['saldo_a_favor'])}',
                  style: const TextStyle(fontSize: 18),
                ),
                if (widget.esAdministrador) ...[
                  const SizedBox(height: 20),
                  OutlinedButton(
                    onPressed: busy ? null : () => operar(false),
                    child: const Text('Aplicar saldo a otras deudas'),
                  ),
                  const Divider(),
                  const Text('Devolución de dinero'),
                  TextField(
                    controller: importe,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Importe'),
                  ),
                  TextField(
                    controller: medio,
                    decoration: const InputDecoration(
                      labelText: 'Medio: efectivo, transferencia…',
                    ),
                  ),
                  FilledButton(
                    onPressed: busy ? null : () => operar(true),
                    child: const Text('Registrar reintegro'),
                  ),
                ],
                const Divider(),
                const Text('Movimientos de crédito'),
                if (useDesktopLayout(context))
                  DesktopRecords(
                    embedded: true,
                    records: movimientos,
                    fields: [
                      DesktopField(
                        'Movimiento',
                        (r) => r['pedido_destino_id'] == null
                            ? 'Reintegro'
                            : 'Aplicación a pedido',
                        width: 200,
                      ),
                      DesktopField('Fecha', (r) => r['fecha'], width: 200),
                      DesktopField('Medio', (r) => r['medio_pago']),
                      DesktopField(
                        'Importe',
                        (r) => ncMoney(r['importe']),
                        numeric: true,
                        width: 140,
                      ),
                    ],
                  )
                else
                  for (final m in movimientos)
                    ListTile(
                      title: Text(
                        '${m['pedido_destino_id'] == null ? 'Reintegro' : 'Aplicación a otro pedido'} · ${ncMoney(m['importe'])}',
                      ),
                      subtitle: Text('${m['fecha']}\n${m['medio_pago'] ?? ''}'),
                    ),
              ],
            ),
    ),
  );
}
