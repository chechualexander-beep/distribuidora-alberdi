import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_theme.dart';
import '../../core/desktop_records.dart';
import '../../core/network_status.dart';
import '../invoicing/atomic_invoice.dart' show newInvoiceRequestId;
import '../stock/stock_data.dart';
import 'business_health.dart';
import 'finance_data.dart';
import 'finance_forms.dart';
import 'finance_dashboard_page.dart';

/// "Plata del negocio": cuánto hay, cuánto está apartado para los gastos fijos, qué se debe a
/// proveedores y cuánto queda para mercadería. Solo administración.
/// "Anotar gasto" directo desde el inicio (teléfono o Windows), sin pasar por Plata del negocio.
Future<void> quickExpense(BuildContext context, {SupabaseClient? client, StockOpRunner? runner}) async {
  final request = await showMovementForm(context, tipo: 'gasto');
  if (request == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final outcome = await runFinOp(
      client,
      rpc: request.rpc,
      args: request.args,
      description: request.description,
      total: request.total,
      runner: runner,
    );
    messenger.showSnackBar(
      SnackBar(
        content: Text(outcome.savedOffline ? 'Sin señal: el gasto quedó guardado y se envía solo.' : 'Gasto anotado.'),
      ),
    );
  } catch (error) {
    messenger.showSnackBar(SnackBar(content: Text(stockErrorText(error))));
  }
}

class FinanceHomePage extends StatefulWidget {
  const FinanceHomePage({super.key, this.client, this.runner, this.initial});
  final SupabaseClient? client;

  /// Solo para pruebas.
  final StockOpRunner? runner;
  final FinState? initial;

  @override
  State<FinanceHomePage> createState() => _FinanceHomePageState();
}

class _FinanceHomePageState extends State<FinanceHomePage> {
  SupabaseClient get _client => widget.client ?? Supabase.instance.client;
  FinState? _state;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  final _startCash = TextEditingController();
  final _startWallet = TextEditingController();

  @override
  void initState() {
    super.initState();
    _state = widget.initial;
    if (_state == null) {
      _load();
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    _startCash.dispose();
    _startWallet.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final state = await fetchFinState(_client);
      // Foto del capital de hoy, para comparar mes a mes en el tablero.
      if (state.started) saveCapitalSnapshot(_client);
      if (!mounted) return;
      setState(() {
        _state = state;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = isUncertainRequestError(error)
            ? 'Sin conexión. Probá de nuevo cuando haya señal.'
            : 'No se pudo cargar: ${stockErrorText(error)}';
        _loading = false;
      });
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<Map<String, dynamic>?> _run(FinRequest request) async {
    if (_busy) return null;
    setState(() => _busy = true);
    try {
      final outcome = await runFinOp(
        widget.client,
        rpc: request.rpc,
        args: request.args,
        description: request.description,
        total: request.total,
        runner: widget.runner,
      );
      if (outcome.savedOffline) {
        _snack('Sin señal: quedó guardado en el teléfono y se envía solo.');
      } else {
        _snack('Listo.');
      }
      if (widget.runner == null) await _load();
      return outcome.result;
    } catch (error) {
      _snack(stockErrorText(error));
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _movement(String tipo) async {
    final request = await showMovementForm(context, tipo: tipo);
    if (request != null) await _run(request);
  }

  Future<void> _count() async {
    final state = _state;
    if (state == null) return;
    final request = await showCountForm(context, state);
    if (request == null) return;
    final result = await _run(request);
    if (result == null || !mounted) return;
    final diff = stockNum(result['diferencia']);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(diff == 0 ? Icons.check_circle_outline : Icons.info_outline, size: 44),
        title: Text(diff == 0 ? 'Coincide' : (diff > 0 ? 'Sobran ${pesos(diff)}' : 'Faltan ${pesos(-diff)}')),
        content: Text(
          'La app decía ${pesos(stockNum(result['sistema']))} y contaste ${pesos(stockNum(result['contado']))}.'
          '${diff == 0 ? '' : '\nLa diferencia quedó anotada.'}',
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('ACEPTAR'))],
      ),
    );
  }

  Future<void> _debt() async {
    final request = await showDebtForm(context);
    if (request != null) await _run(request);
  }

  Future<void> _payDebt(Debt debt) async {
    final request = await showPayDebtForm(context, debt);
    if (request != null) await _run(request);
  }

  Future<void> _payFixed(FixedExpense expense) async {
    final request = await showPayFixedForm(context, expense);
    if (request != null) await _run(request);
  }

  Future<void> _envelope(Envelope e) async {
    final request = await showEnvelopeForm(context, e, suggested: e.ponerSabado);
    if (request != null) await _run(request);
  }

  /// El sábado: sobres y sueldo, uno detrás del otro.
  Future<void> _saturday() async {
    final state = _state;
    if (state == null) return;
    final requests = await showSaturdayForm(context, state);
    if (requests == null || _busy) return;
    setState(() => _busy = true);
    var offline = false;
    try {
      for (final r in requests) {
        final outcome = await runFinOp(
          widget.client,
          rpc: r.rpc,
          args: r.args,
          description: r.description,
          total: r.total,
          runner: widget.runner,
        );
        offline = offline || outcome.savedOffline;
      }
      _snack(offline ? 'Sin señal: quedó guardado y se envía solo.' : 'Listo: sobres llenos.');
    } catch (error) {
      _snack(stockErrorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (widget.runner == null) await _load();
  }

  Future<void> _homePaid(FixedExpense g, bool paid) async {
    final period = paid ? g.vence : (g.periodoMes ?? g.vence);
    final args = {'p_gasto_fijo_id': g.id, 'p_periodo': isoDate(period), 'p_pagado': paid};
    try {
      if (widget.runner != null) {
        await widget.runner!('fin_gasto_casa_pagado', args);
      } else {
        await _client.rpc('fin_gasto_casa_pagado', params: args);
      }
      _snack(paid ? '${g.nombre}: pagado con tu sueldo.' : '${g.nombre}: vuelve a pendiente.');
      if (widget.runner == null) await _load();
    } catch (error) {
      _snack(isUncertainRequestError(error) ? 'Sin señal: se marca con conexión.' : stockErrorText(error));
    }
  }

  Future<void> _editFixed([FixedExpense? current]) async {
    final params = await showFixedExpenseForm(context, current: current);
    if (params == null) return;
    try {
      await _client.rpc('fin_gasto_fijo_guardar', params: {'p_id': current?.id ?? newInvoiceRequestId(), ...params});
      _snack('Gasto fijo guardado.');
      await _load();
    } catch (error) {
      _snack(isUncertainRequestError(error) ? 'Sin señal: los gastos fijos se cargan con conexión.' : stockErrorText(error));
    }
  }

  Future<void> _cancel(String id, String what) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Anular?'),
        content: Text('$what\nQueda anotado como anulado y deja de contar.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Anular')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _client.rpc('fin_anular', params: {'p_id': id});
      _snack('Anulado.');
      await _load();
    } catch (error) {
      _snack(isUncertainRequestError(error) ? 'Sin señal: se anula con conexión.' : stockErrorText(error));
    }
  }

  Future<void> _setSalary() async {
    final current = _state?.sueldo?.semanal;
    double? suggested;
    if (widget.runner == null) {
      try {
        suggested = (await fetchBusinessHealth(_client).timeout(const Duration(seconds: 8))).sueldoSugerido;
      } catch (_) {}
    }
    if (!mounted) return;
    final result = await showSalaryForm(context, current: current, suggested: suggested);
    if (result == null) return;
    try {
      if (widget.runner != null) {
        await widget.runner!('fin_sueldo_guardar', {'p_importe': result.importe});
      } else {
        await _client.rpc('fin_sueldo_guardar', params: {'p_importe': result.importe});
      }
      _snack(result.importe == null ? 'Sueldo fijo quitado.' : 'Sueldo guardado: ${pesos(result.importe!)} por semana.');
      if (widget.runner == null) await _load();
    } catch (error) {
      _snack(isUncertainRequestError(error) ? 'Sin señal: el sueldo se fija con conexión.' : stockErrorText(error));
    }
  }

  Future<void> _paySalary() async {
    final salary = _state?.sueldo;
    if (salary == null || !salary.fijado) return;
    final request = await showPaySalaryForm(context, salary);
    if (request != null) await _run(request);
  }

  /// Mantener apretado un movimiento: cambiar de quién es o anular.
  Future<void> _options(FinMovement m) async {
    if (!m.reclasificable) {
      if (m.anulable) await _cancel(m.id, m.titulo);
      return;
    }
    final choice = await showMovementActions(context, m);
    if (choice == 'anular') {
      await _cancel(m.id, m.titulo);
    } else if (choice == 'reclasificar') {
      await _reclassify(m);
    }
  }

  Future<void> _reclassify(FinMovement m) async {
    final done = await reclassifyMovement(context, m, client: widget.client, runner: widget.runner);
    if (done && widget.runner == null) await _load();
  }

  Future<void> _start() async {
    final cash = parseMoney(_startCash.text);
    final wallet = parseMoney(_startWallet.text);
    if (cash == null || wallet == null) {
      _snack('Escribí cuánto hay en efectivo y en la billetera (0 si no hay nada).');
      return;
    }
    await _run(FinRequest('fin_foto_inicial', {'p_efectivo': cash, 'p_billetera': wallet}, 'Foto inicial'));
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Plata del negocio'),
        actions: [
          if (state != null && state.started)
            IconButton(
              tooltip: 'Tablero del mes',
              icon: const Icon(Icons.insights),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => FinanceDashboardPage(client: widget.client)),
              ),
            ),
          if (state != null && state.started)
            IconButton(
              tooltip: 'Movimientos',
              icon: const Icon(Icons.list_alt),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => FinanceMovementsPage(client: widget.client)),
              ),
            ),
          IconButton(tooltip: 'Actualizar', icon: const Icon(Icons.refresh), onPressed: _loading ? null : _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : state == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error ?? 'No se pudo cargar.', textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _load, child: const Text('Reintentar')),
                  ],
                ),
              ),
            )
          : DesktopForm(
              maxWidth: 900,
              child: RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
                  children: state.started
                      ? [
                          _moneyCard(state),
                          _actions(),
                          _salaryCard(state),
                          _envelopeCard(state),
                          if (state.deLaCasa.isNotEmpty) _homeExpensesCard(state),
                          if (state.deudas.isNotEmpty) _debtsCard(state),
                          _monthCard(state),
                          _recentCard(state),
                        ]
                      : [_firstSnapshot()],
                ),
              ),
            ),
    );
  }

  Widget _firstSnapshot() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Foto inicial', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
            'Para empezar, contá cuánta plata tiene hoy el negocio. Desde ese momento la app suma sola '
            'los cobros y las comisiones pagadas, y vos anotás gastos, compras y lo que va para la casa.',
          ),
          const SizedBox(height: 16),
          moneyField(_startCash, 'Efectivo que hay hoy', autofocus: true),
          const SizedBox(height: 12),
          moneyField(_startWallet, 'Lo que hay en la billetera virtual'),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _start,
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('GUARDAR FOTO INICIAL'),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _line(String label, double value, {bool bold = false, Color? color, double size = 15}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: TextStyle(fontSize: size, fontWeight: bold ? FontWeight.bold : null)),
        ),
        Text(
          pesos(value),
          style: TextStyle(fontSize: size, fontWeight: bold ? FontWeight.bold : FontWeight.w500, color: color),
        ),
      ],
    ),
  );

  Widget _title(String text, {Widget? trailing}) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Expanded(child: Text(text, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
        if (trailing != null) trailing,
      ],
    ),
  );

  Widget _moneyCard(FinState s) {
    final t = Tonos.of(context);
    final short = s.disponible < 0;
    // Servidor sin sobres (versión anterior): se muestra como antes.
    final conSobres = s.libre != null;
    final libres = conSobres ? s.cuentas.where((c) => c.codigo == efectivo || c.codigo == billetera) : s.cuentas;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _title(conSobres ? 'Plata libre' : 'Plata hoy'),
            for (final c in libres) _line(c.nombre, c.saldo),
            const Divider(),
            _line('Total', conSobres ? s.libre! : s.plata, bold: true),
            if (!conSobres) _line('− Apartado para gastos fijos', -s.sobre, color: t.secundario),
            if (s.deben > 0) _line('− Proveedores a pagar', -s.deben, color: t.secundario),
            if (conSobres && s.faltanSobres > 0) _line('− Lo que falta en los sobres', -s.faltanSobres, color: t.secundario),
            const Divider(),
            _line('Disponible para mercadería', s.disponible, bold: true, size: 18, color: short ? t.rojo : t.verde),
            if (conSobres)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Lo de los sobres no está acá: el arqueo de todos los días es solo de esta plata.',
                  style: TextStyle(fontSize: 12, color: t.secundario),
                ),
              ),
            if (short)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'No alcanza: cobrá saldos o frená compras y retiros.',
                  style: TextStyle(color: t.rojo),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _actions() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          onPressed: _busy ? null : () => _movement('gasto'),
          icon: const Icon(Icons.receipt_long_outlined),
          label: const Text('Anotar gasto'),
        ),
        FilledButton.tonalIcon(
          onPressed: _busy ? null : () => _movement('hogar'),
          icon: const Icon(Icons.home_outlined),
          label: const Text('Retiro casa / personal'),
        ),
        OutlinedButton.icon(
          onPressed: _busy ? null : _debt,
          icon: const Icon(Icons.event_note_outlined),
          label: const Text('Proveedor a pagar'),
        ),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _movement('pase'),
          icon: const Icon(Icons.swap_horiz),
          label: const Text('Pase entre cuentas'),
        ),
        OutlinedButton.icon(
          onPressed: _busy ? null : _count,
          icon: const Icon(Icons.calculate_outlined),
          label: const Text('Arqueo'),
        ),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _movement('ingreso'),
          icon: const Icon(Icons.add_card_outlined),
          label: const Text('Ingreso o aporte'),
        ),
      ],
    ),
  );

  Widget _salaryCard(FinState s) {
    final t = Tonos.of(context);
    final salary = s.sueldo;
    if (salary == null || !salary.fijado) {
      return Card(
        key: const Key('mi-sueldo'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _title('Mi sueldo'),
              const Text(
                'Fijate un sueldo semanal y pagátelo cada sábado: así lo de la casa queda separado del negocio '
                'y se ve si el negocio de verdad gana.',
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  onPressed: _busy ? null : _setSalary,
                  icon: const Icon(Icons.badge_outlined),
                  label: const Text('Fijar sueldo'),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final week = salary.semana;
    final paid = salary.pagado != null;
    return Card(
      key: const Key('mi-sueldo'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _title(
              'Mi sueldo',
              trailing: TextButton(onPressed: _busy ? null : _setSalary, child: const Text('Cambiar')),
            ),
            Text(
              '${pesos(salary.semanal!)} por semana',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text('≈ ${pesos(salary.porMes)} por mes', style: TextStyle(color: t.secundario)),
            const SizedBox(height: 8),
            if (week != null)
              Row(
                children: [
                  Icon(
                    salary.pendiente ? Icons.error_outline : (paid ? Icons.check_circle_outline : Icons.event),
                    color: salary.pendiente ? t.rojo : (paid ? t.verde : t.secundario),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      salary.pendiente
                          ? 'Pendiente: el del ${sabado(week)}'
                          : paid
                          ? 'Pagado el del ${sabado(week)}'
                          : 'Próximo: ${sabado(week)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: salary.pendiente ? t.rojo : null,
                      ),
                    ),
                  ),
                  if (salary.pendiente)
                    FilledButton(onPressed: _busy ? null : _paySalary, child: const Text('Pagar'))
                  else if (!paid)
                    TextButton(onPressed: _busy ? null : _paySalary, child: const Text('Adelantar')),
                ],
              ),
            if (salary.ultimoSemana != null && salary.ultimoImporte != null && !(paid && salary.ultimoSemana == week))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Último: ${pesos(salary.ultimoImporte!)} del ${sabado(salary.ultimoSemana!)}',
                  style: TextStyle(fontSize: 13, color: t.secundario),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _envelopeCard(FinState s) {
    final t = Tonos.of(context);
    final negocio = s.delNegocio;
    final sobres = [for (final e in s.sobres) if (e.deberia > 0 || e.saldo > 0 || e.ponerSabado > 0) e];
    return Card(
      key: const Key('sobres'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _title(
              'Sobres de gastos fijos',
              trailing: TextButton.icon(
                onPressed: () => _editFixed(),
                icon: const Icon(Icons.add),
                label: const Text('Agregar'),
              ),
            ),
            if (negocio.isEmpty)
              const Text(
                'Cargá los gastos fijos del negocio (cuota del vehículo, alquiler…) y cómo se pagan. Cada sábado '
                'la app te dice cuánto poner en el frasco (efectivo) y en la reserva de la billetera.',
              )
            else ...[
              if (s.sobres.isEmpty)
                Text('Apartá ${pesos(s.apartarPorSemana)} por semana', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              for (final e in sobres) _envelopeRow(e),
              if (s.sobres.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      FilledButton.tonalIcon(
                        key: const Key('llenar-sobres'),
                        onPressed: _busy ? null : _saturday,
                        icon: const Icon(Icons.event_available_outlined),
                        label: Text(s.ponerSabado > 0 ? 'Llenar sobres · ${pesos(s.ponerSabado)}' : 'Llenar sobres'),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              for (final g in negocio) _fixedRow(g),
            ],
            if (s.sobres.isNotEmpty && negocio.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Los sobres cambian solo cuando ponés plata o pagás desde ahí. "Debería tener" es para hoy; '
                  'lo del sábado cubre hasta el sábado siguiente.',
                  style: TextStyle(fontSize: 12, color: t.secundario),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _envelopeRow(Envelope e) {
    final t = Tonos.of(context);
    final ok = e.faltan <= 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(e.codigo == sobreEfectivo ? Icons.savings_outlined : Icons.account_balance_outlined),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(e.nombre, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
                    Text(pesos(e.saldo), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                Text(
                  'Para hoy debería tener ${pesos(e.deberia)} · ${ok ? 'al día' : 'faltan ${pesos(e.faltan)}'}',
                  style: TextStyle(fontSize: 13, color: ok ? t.verde : t.rojo),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Poner o sacar plata',
            onPressed: _busy ? null : () => _envelope(e),
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
    );
  }

  Widget _homeExpensesCard(FinState s) {
    final t = Tonos.of(context);
    return Card(
      key: const Key('gastos-casa'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _title('Gastos de la casa (con tu sueldo)'),
            Text(
              'No salen del negocio: marcalos cuando los pagues. Suman ${pesos(s.deLaCasa.where((g) => g.activo).fold(0.0, (a, g) => a + g.importe))} por mes.',
              style: TextStyle(fontSize: 13, color: t.secundario),
            ),
            for (final g in s.deLaCasa)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                onTap: () => _editFixed(g),
                title: Text('${g.nombre} · ${pesos(g.importe)}', style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: g.activo ? null : t.secundario,
                  decoration: g.activo ? null : TextDecoration.lineThrough,
                )),
                subtitle: Text(
                  !g.activo
                      ? 'Apagado'
                      : g.pagadoMes
                      ? 'Pagado este mes · próximo ${diaMes(g.vence)}'
                      : g.vencido
                      ? 'VENCIDO el ${diaMes(g.vence)}'
                      : 'Vence el ${diaMes(g.vence)}',
                  style: TextStyle(color: g.vencido && !g.pagadoMes ? t.rojo : t.secundario),
                ),
                trailing: !g.activo
                    ? null
                    : g.pagadoMes
                    ? TextButton(onPressed: _busy ? null : () => _homePaid(g, false), child: const Text('Deshacer'))
                    : TextButton(onPressed: _busy ? null : () => _homePaid(g, true), child: const Text('Ya lo pagué')),
              ),
          ],
        ),
      ),
    );
  }

  Widget _fixedRow(FixedExpense g) {
    final t = Tonos.of(context);
    final (bg, fg) = switch (g.ambito) {
      'hogar' => t.etiquetaVioleta,
      'mixto' => t.etiquetaGris,
      _ => t.etiquetaVerde,
    };
    Widget tag(String text, (Color, Color) colors) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(color: colors.$1, borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(fontSize: 11, color: colors.$2, fontWeight: FontWeight.w600)),
    );
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      onTap: () => _editFixed(g),
      title: Wrap(
        spacing: 6,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '${g.nombre} · ${pesos(g.importe)}',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: g.activo ? null : t.secundario,
              decoration: g.activo ? null : TextDecoration.lineThrough,
            ),
          ),
          tag(g.ambito == 'mixto' ? 'mixto' : 'negocio', (bg, fg)),
          tag(g.medio == efectivo ? 'efectivo' : 'transferencia', t.etiquetaGris),
        ],
      ),
      subtitle: Text(
        !g.activo
            ? 'Apagado'
            : g.vencido
            ? 'VENCIDO el ${diaMes(g.vence)}'
            : 'Vence el ${diaMes(g.vence)}',
        style: TextStyle(color: g.vencido ? t.rojo : t.secundario),
      ),
      trailing: g.activo
          ? TextButton(onPressed: _busy ? null : () => _payFixed(g), child: const Text('Pagar'))
          : null,
    );
  }

  Widget _debtsCard(FinState s) {
    final t = Tonos.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _title('Proveedores a pagar'),
            for (final d in s.deudas)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text('${d.proveedor} · ${pesos(d.resta)}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                subtitle: Text(
                  [
                    d.vencida ? 'VENCIDA el ${diaMes(d.vence)}' : 'Vence el ${diaMes(d.vence)}',
                    if (d.resta < d.importe) 'de ${pesos(d.importe)}',
                    if (d.descripcion != null && d.descripcion!.isNotEmpty) d.descripcion!,
                  ].join(' · '),
                  style: TextStyle(color: d.vencida ? t.rojo : t.secundario),
                ),
                onLongPress: d.resta < d.importe ? null : () => _cancel(d.id, '${d.proveedor} · ${pesos(d.importe)}'),
                trailing: TextButton(onPressed: _busy ? null : () => _payDebt(d), child: const Text('Pagar')),
              ),
          ],
        ),
      ),
    );
  }

  Widget _monthCard(FinState s) {
    final t = Tonos.of(context);
    final m = s.mes;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _title('Este mes'),
            _line('Cobros a clientes', m['cobros'], color: t.verde),
            if (m['ingresos'] > 0) _line('Ingresos extra', m['ingresos'], color: t.verde),
            if (m['aportes'] > 0) _line('Aportes tuyos (de afuera)', m['aportes'], color: t.verde),
            _line('Compras de mercadería', -m['compras']),
            _line('Gastos del negocio', -m['gastos_negocio']),
            _line('Comisiones', -m['comisiones']),
            if (m['devoluciones'] > 0) _line('Devoluciones a clientes', -m['devoluciones']),
            if (m['ajustes'] != 0) _line('Diferencias de arqueo', m['ajustes']),
            const Divider(),
            _line('Retiros (fuera del negocio)', -m['hogar'], bold: true),
            if (m['sueldo'] > 0) _line('   Mi sueldo', -m['sueldo'], color: t.secundario),
            if (m['casa'] > 0) _line('   Casa', -m['casa'], color: t.secundario),
            if (m['personal'] > 0) _line('   Personal', -m['personal'], color: t.secundario),
            const SizedBox(height: 6),
            Text(
              'Los retiros no son gastos del negocio: no bajan la ganancia. "Casa" incluye la parte de la casa '
              'de los gastos fijos. La ganancia del mes y la salud del negocio están en el tablero.',
              style: TextStyle(fontSize: 12, color: t.secundario),
            ),
          ],
        ),
      ),
    );
  }

  Widget _recentCard(FinState s) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _title(
            'Últimos movimientos',
            trailing: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => FinanceMovementsPage(client: widget.client)),
              ),
              child: const Text('Ver todos'),
            ),
          ),
          if (s.ultimos.isEmpty) const Text('Todavía no hay movimientos.'),
          for (final m in s.ultimos.take(12))
            finMovementTile(context, m, onCancel: m.anulable ? () => _options(m) : null),
          if (s.ultimos.any((m) => m.anulable))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Para cambiar de quién es un gasto o anular un error, mantené apretado el movimiento.',
                style: TextStyle(fontSize: 12, color: Tonos.of(context).secundario),
              ),
            ),
        ],
      ),
    ),
  );
}

/// Mantener apretado: "¿De quién es?" o "Anular". Devuelve 'reclasificar', 'anular' o null.
Future<String?> showMovementActions(BuildContext context, FinMovement m) => showModalBottomSheet<String>(
  context: context,
  builder: (context) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(title: Text(m.titulo, style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text(pesos(m.importe))),
        ListTile(
          leading: const Icon(Icons.swap_horiz),
          title: const Text('Cambiar de quién es'),
          subtitle: const Text('Negocio, casa o personal'),
          onTap: () => Navigator.pop(context, 'reclasificar'),
        ),
        ListTile(
          leading: const Icon(Icons.block),
          title: const Text('Anular'),
          onTap: () => Navigator.pop(context, 'anular'),
        ),
      ],
    ),
  ),
);

/// Pide de quién es y lo cambia (con conexión). true si se cambió.
Future<bool> reclassifyMovement(
  BuildContext context,
  FinMovement m, {
  SupabaseClient? client,
  StockOpRunner? runner,
}) async {
  final choice = await showReclassifyForm(context, m);
  if (choice == null || !context.mounted) return false;
  final messenger = ScaffoldMessenger.of(context);
  final args = {'p_id': m.id, 'p_de_quien': choice.deQuien, 'p_categoria': choice.categoria};
  try {
    if (runner != null) {
      await runner('fin_reclasificar', args);
    } else {
      await (client ?? Supabase.instance.client).rpc('fin_reclasificar', params: args);
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(switch (choice.deQuien) {
          'casa' => 'Pasado a Casa: ya no baja la ganancia del negocio.',
          'personal' => 'Pasado a Personal: ya no baja la ganancia del negocio.',
          _ => 'Pasado a gastos del negocio · ${choice.categoria}.',
        }),
      ),
    );
    return true;
  } catch (error) {
    messenger.showSnackBar(
      SnackBar(content: Text(isUncertainRequestError(error) ? 'Sin señal: se cambia con conexión.' : stockErrorText(error))),
    );
    return false;
  }
}

IconData _icon(FinMovement m) => switch (m.tipo) {
  'cobro' => Icons.call_received,
  'gasto' || 'gasto_fijo' => Icons.receipt_long_outlined,
  'hogar' when m.categoria == 'Sueldo' => Icons.badge_outlined,
  'hogar' when m.categoria == 'Personal' => Icons.person_outline,
  'hogar' => Icons.home_outlined,
  'ingreso' when m.esAporte => Icons.savings_outlined,
  'compra' || 'pago_proveedor' => Icons.shopping_bag_outlined,
  'pase' => Icons.swap_horiz,
  'comision' => Icons.payments_outlined,
  'devolucion' => Icons.undo,
  'ajuste' => Icons.calculate_outlined,
  'saldo_inicial' => Icons.photo_camera_outlined,
  _ => Icons.add_card_outlined,
};

Widget finMovementTile(BuildContext context, FinMovement m, {VoidCallback? onCancel}) {
  final t = Tonos.of(context);
  return ListTile(
    contentPadding: EdgeInsets.zero,
    dense: true,
    leading: Icon(_icon(m)),
    title: Text(m.titulo, maxLines: 2, overflow: TextOverflow.ellipsis),
    subtitle: Text(
      '${diaMesHora(m.fecha)} · ${cuentaNombre(m.cuenta)}'
      '${m.parteHogar > 0 && m.tipo != 'hogar' ? ' · casa ${pesos(m.parteHogar)}' : ''}',
      style: TextStyle(color: t.secundario),
    ),
    trailing: Text(
      '${m.importe > 0 ? '+' : ''}${pesos(m.importe)}',
      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: m.importe > 0 ? t.verde : null),
    ),
    onLongPress: onCancel,
  );
}

/// Todos los movimientos de un mes.
class FinanceMovementsPage extends StatefulWidget {
  const FinanceMovementsPage({super.key, this.client});
  final SupabaseClient? client;

  @override
  State<FinanceMovementsPage> createState() => _FinanceMovementsPageState();
}

class _FinanceMovementsPageState extends State<FinanceMovementsPage> {
  SupabaseClient get _client => widget.client ?? Supabase.instance.client;
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  List<FinMovement>? _rows;
  String? _error;

  static const _months = [
    'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
    'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
  ];

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
      final rows = await fetchFinMovements(_client, _month, DateTime(_month.year, _month.month + 1));
      if (mounted) setState(() => _rows = rows);
    } catch (error) {
      if (mounted) {
        setState(() => _error = isUncertainRequestError(error) ? 'Sin conexión.' : stockErrorText(error));
      }
    }
  }

  void _move(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
    _load();
  }

  Future<void> _options(FinMovement m) async {
    if (m.reclasificable) {
      final choice = await showMovementActions(context, m);
      if (!mounted) return;
      if (choice == 'reclasificar') {
        if (await reclassifyMovement(context, m, client: widget.client)) await _load();
        return;
      }
      if (choice != 'anular') return;
    }
    await _cancel(m);
  }

  Future<void> _cancel(FinMovement m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Anular?'),
        content: Text('${m.titulo}\nQueda anotado como anulado y deja de contar.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Anular')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _client.rpc('fin_anular', params: {'p_id': m.id});
      await _load();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(stockErrorText(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final inflow = rows?.where((m) => m.importe > 0 && m.tipo != 'pase').fold<double>(0, (s, m) => s + m.importe) ?? 0;
    final outflow = rows?.where((m) => m.importe < 0 && m.tipo != 'pase').fold<double>(0, (s, m) => s - m.importe) ?? 0;
    final t = Tonos.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Movimientos')),
      body: DesktopForm(
        maxWidth: 900,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(onPressed: () => _move(-1), icon: const Icon(Icons.chevron_left)),
                Text(
                  '${_months[_month.month - 1]} ${_month.year}',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                IconButton(onPressed: () => _move(1), icon: const Icon(Icons.chevron_right)),
              ],
            ),
            if (rows != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Entró ${pesos(inflow)} · salió ${pesos(outflow)} (sin contar pases)',
                  style: TextStyle(color: t.secundario),
                ),
              ),
            Expanded(
              child: rows == null
                  ? Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!))
                  : rows.isEmpty
                  ? const Center(child: Text('No hay movimientos este mes.'))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      children: [
                        for (final m in rows) finMovementTile(context, m, onCancel: m.anulable ? () => _options(m) : null),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
