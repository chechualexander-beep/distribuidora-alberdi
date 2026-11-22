import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_theme.dart';
import '../../core/desktop_records.dart';
import '../../core/network_status.dart';
import '../invoicing/atomic_invoice.dart' show newInvoiceRequestId;
import '../stock/stock_data.dart';
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
                          _envelopeCard(state),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _title('Plata hoy'),
            for (final c in s.cuentas) _line(c.nombre, c.saldo),
            const Divider(),
            _line('Total', s.plata, bold: true),
            _line('− Apartado para gastos fijos', -s.sobre, color: t.secundario),
            if (s.deben > 0) _line('− Proveedores a pagar', -s.deben, color: t.secundario),
            const Divider(),
            _line('Disponible para mercadería', s.disponible, bold: true, size: 18, color: short ? t.rojo : t.verde),
            if (short)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'No alcanza para lo apartado: cobrá saldos o frená compras y retiros.',
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
          label: const Text('Dejé plata en casa'),
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
          label: const Text('Ingreso extra'),
        ),
      ],
    ),
  );

  Widget _envelopeCard(FinState s) {
    final t = Tonos.of(context);
    final total = s.gastosFijosMes;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _title(
              'Sobre de gastos fijos',
              trailing: TextButton.icon(
                onPressed: () => _editFixed(),
                icon: const Icon(Icons.add),
                label: const Text('Agregar'),
              ),
            ),
            if (s.gastosFijos.isEmpty)
              const Text(
                'Cargá tus gastos fijos (luz, cuota del vehículo, tarjeta…) y la app te dice cuánto '
                'apartar cada semana para que el día de pago la plata ya esté.',
              )
            else ...[
              Text(
                'Apartá ${pesos(s.apartarPorSemana)} por semana',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: total <= 0 ? 0 : (s.sobre / total).clamp(0, 1).toDouble(),
                minHeight: 8,
              ),
              const SizedBox(height: 4),
              Text('Apartado hoy ${pesos(s.sobre)} de ${pesos(total)}', style: TextStyle(color: t.secundario)),
              const SizedBox(height: 8),
              for (final g in s.gastosFijos) _fixedRow(g),
            ],
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
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      onTap: () => _editFixed(g),
      title: Wrap(
        spacing: 6,
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
            child: Text(
              switch (g.ambito) {
                'hogar' => 'hogar',
                'mixto' => 'mixto',
                _ => 'negocio',
              },
              style: TextStyle(fontSize: 11, color: fg, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      subtitle: Text(
        !g.activo
            ? 'Apagado'
            : g.vencido
            ? 'VENCIDO el ${diaMes(g.vence)}'
            : 'Vence el ${diaMes(g.vence)} · apartado ${pesos(g.reservado)}',
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
            _line('Compras de mercadería', -m['compras']),
            _line('Gastos del negocio', -m['gastos_negocio']),
            _line('Comisiones', -m['comisiones']),
            if (m['devoluciones'] > 0) _line('Devoluciones a clientes', -m['devoluciones']),
            _line('Para la casa', -m['hogar'], bold: true),
            if (m['ajustes'] != 0) _line('Diferencias de arqueo', m['ajustes']),
            const SizedBox(height: 6),
            Text(
              '"Para la casa" incluye lo que dejaste en casa y la parte de la casa de los gastos fijos. '
              'La ganancia del mes (ventas − costo − gastos) va a estar en el tablero.',
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
            finMovementTile(context, m, onCancel: m.anulable ? () => _cancel(m.id, m.titulo) : null),
          if (s.ultimos.any((m) => m.anulable))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Para anular un error, mantené apretado el movimiento.',
                style: TextStyle(fontSize: 12, color: Tonos.of(context).secundario),
              ),
            ),
        ],
      ),
    ),
  );
}

IconData _icon(String tipo) => switch (tipo) {
  'cobro' => Icons.call_received,
  'gasto' || 'gasto_fijo' => Icons.receipt_long_outlined,
  'hogar' => Icons.home_outlined,
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
    leading: Icon(_icon(m.tipo)),
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
                        for (final m in rows) finMovementTile(context, m, onCancel: m.anulable ? () => _cancel(m) : null),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
