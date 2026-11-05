import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../core/payment_outbox.dart';
import '../../core/payment_money.dart';
import 'balance_repository.dart';
import 'client_payment_dialog.dart';

class BalancesPage extends StatefulWidget {
  const BalancesPage({super.key, this.repository, this.paymentStore});
  final BalanceRepository? repository;
  final PaymentOutbox? paymentStore;
  @override
  State<BalancesPage> createState() => _BalancesPageState();
}

class _BalancesPageState extends State<BalancesPage> {
  BalanceRepository? repository;
  List<BalanceRow>? rows;
  String? error;
  String search = '';
  PaymentOutbox? paymentStore;
  List<BalanceRow> recoveries = [];

  @override
  void dispose() {
    if (widget.paymentStore == null) paymentStore?.close();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load({bool propagate = false}) async {
    setState(() {
      rows = null;
      error = null;
    });
    try {
      final repo = repository ??=
          widget.repository ?? BalanceRepository(Supabase.instance.client);
      await repo.requireAdmin();
      final support = paymentStore == null && widget.paymentStore == null
          ? await getApplicationSupportDirectory()
          : null;
      if (!mounted) return;
      paymentStore ??=
          widget.paymentStore ??
          PaymentOutbox.open(p.join(support!.path, 'cobros_contextuales'));
      final data = await repo.debtors();
      debtorTotal(data); // Validate every monetary value before showing totals.
      final pending = <BalanceRow>[];
      for (final id in paymentStore!.pendingClients(repo.scope, repo.actor)) {
        pending.add(await repo.account(id));
      }
      if (mounted) {
        setState(() {
          rows = data;
          recoveries = pending;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'No se pudieron consultar los saldos. Verificá sesión y permisos.',
        );
      }
      if (propagate) rethrow;
    }
  }

  Future<void> open(BalanceRow row) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ClientBalancePage(
          clientId: row['cliente_id'] as String,
          repository: repository,
        ),
      ),
    );
    if (mounted) await load();
  }

  @override
  Widget build(BuildContext context) {
    final visible = rows
        ?.where(
          (r) => r['nombre_comercio'].toString().toLowerCase().contains(
            search.toLowerCase(),
          ),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saldos'),
        actions: [
          IconButton(
            onPressed: load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar saldos',
          ),
        ],
      ),
      body: error != null
          ? Center(child: Text(error!, key: const ValueKey('balances-error')))
          : rows == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'Total general por cobrar: ${centsMoney(debtorTotal(rows!))}',
                  key: const ValueKey('balances-total'),
                ),
                Text('${rows!.length} clientes con deuda · Todos los períodos'),
                for (final row in recoveries)
                  ListTile(
                    title: Text('Pago guardado · ${row['nombre_comercio']}'),
                    trailing: TextButton(
                      onPressed: () => showClientPayment(
                        context,
                        repository!,
                        row['cliente_id'] as String,
                        row['nombre_comercio'].toString(),
                        () => load(propagate: true),
                      ),
                      child: const Text('Recuperar pago pendiente'),
                    ),
                  ),
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Buscar cliente',
                  ),
                  onChanged: (value) => setState(() => search = value),
                ),
                if (rows!.isEmpty) const Text('Sin clientes con deuda.'),
                if (rows!.isNotEmpty && visible!.isEmpty)
                  const Text('Sin coincidencias.'),
                for (final row in visible!)
                  ListTile(
                    title: Text(row['nombre_comercio'].toString()),
                    subtitle: Text(
                      '${paymentMoney(row['saldo_pendiente'])} · ${row['cantidad_pedidos_con_saldo']} pedidos',
                    ),
                    trailing: TextButton(
                      onPressed: () => showClientPayment(
                        context,
                        repository!,
                        row['cliente_id'] as String,
                        row['nombre_comercio'].toString(),
                        () => load(propagate: true),
                      ),
                      child: const Text('Registrar pago'),
                    ),
                    onTap: () => open(row),
                  ),
              ],
            ),
    );
  }
}

class ClientBalancePage extends StatefulWidget {
  const ClientBalancePage({
    super.key,
    required this.clientId,
    this.repository,
    this.readOnly = false,
  });
  final String clientId;
  final BalanceRepository? repository;
  final bool readOnly;
  @override
  State<ClientBalancePage> createState() => _ClientBalancePageState();
}

class _ClientBalancePageState extends State<ClientBalancePage> {
  BalanceRepository? repository;
  BalanceRow? account;
  List<BalanceRow> debts = [], history = [];
  String? error;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load({bool propagate = false}) async {
    if (mounted) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      final repo = repository ??=
          widget.repository ?? BalanceRepository(Supabase.instance.client);
      await repo.requireAdmin();
      final values = await Future.wait([
        repo.account(widget.clientId),
        repo.debts(widget.clientId),
        repo.history(widget.clientId),
      ]);
      final nextAccount = values[0] as BalanceRow;
      paymentCents(nextAccount['saldo_pendiente']);
      final nextDebts = values[1] as List<BalanceRow>;
      for (final row in nextDebts) {
        for (final key in [
          'total_entregado',
          'total_pagado',
          'total_notas_credito',
          'credito_aplicado',
          'saldo_pendiente',
        ]) {
          paymentCents(row[key]);
        }
      }
      final nextHistory = values[2] as List<BalanceRow>;
      for (final row in nextHistory) {
        paymentCents(row['importe']);
      }
      if (mounted) {
        setState(() {
          account = nextAccount;
          debts = nextDebts;
          history = nextHistory;
          loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          error =
              'No se pudo cargar la cuenta completa o el historial de cobros.';
        });
      }
      if (propagate) rethrow;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Saldo del cliente'),
      actions: [
        IconButton(
          onPressed: load,
          icon: const Icon(Icons.refresh),
          tooltip: 'Actualizar cuenta',
        ),
      ],
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : error != null
        ? Center(child: Text(error!, key: const ValueKey('account-error')))
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(account!['nombre_comercio'].toString()),
              Text(
                'Saldo pendiente: ${paymentMoney(account!['saldo_pendiente'])}',
              ),
              if (paymentCents(account!['saldo_a_favor']) > 0)
                Text(
                  'Saldo a favor: ${paymentMoney(account!['saldo_a_favor'])}',
                ),
              const Text(
                'Deudas de operaciones finalizadas · Todos los períodos',
              ),
              if (widget.readOnly)
                const Text(
                  'Solo consulta mientras la finalización está guardada o en curso.',
                ),
              if (!widget.readOnly)
                FilledButton.icon(
                  onPressed: () => showClientPayment(
                    context,
                    repository!,
                    widget.clientId,
                    account!['nombre_comercio'].toString(),
                    () => load(propagate: true),
                  ),
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('Registrar pago'),
                ),
              if (debts.isEmpty) const Text('Sin pedidos con saldo pendiente.'),
              for (final row in debts)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pedido ${row['pedido_id']} · ${balanceDate(row['fecha_finalizacion'] ?? row['created_at'])}',
                        ),
                        Text(
                          'Entregado: ${paymentMoney(row['total_entregado'])} · Pagado: ${paymentMoney(row['total_pagado'])}',
                        ),
                        if (paymentCents(row['total_notas_credito']) > 0)
                          Text(
                            'Notas internas: ${paymentMoney(row['total_notas_credito'])}',
                          ),
                        if (paymentCents(row['credito_aplicado']) > 0)
                          Text(
                            'Crédito aplicado: ${paymentMoney(row['credito_aplicado'])}',
                          ),
                        Text('Saldo: ${paymentMoney(row['saldo_pendiente'])}'),
                      ],
                    ),
                  ),
                ),
              const Divider(),
              const Text('Historial de cobros'),
              if (history.isEmpty) const Text('Sin cobros registrados.'),
              for (final row in history)
                ListTile(
                  title: Text(
                    '${paymentMoney(row['importe'])} · ${row['medio_pago']}',
                  ),
                  subtitle: Text(
                    '${balanceDate(row['fecha_pago'])} · ${row['observacion'] ?? ''}',
                  ),
                ),
            ],
          ),
  );
}
