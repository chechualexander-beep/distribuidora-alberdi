import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/argentina_date_utils.dart';
import '../balances/balance_repository.dart';
import '../balances/balances_page.dart';
import 'widgets/commercial_summary_card.dart';

typedef CommercialPeriodReader =
    Future<Map<String, dynamic>> Function(DateTime start, DateTime end);

const _amountKeys = [
  'venta_preventa',
  'entrega_total',
  'entrega_preventa',
  'entrega_directa',
  'entrega_sin_clasificar',
  'recaudacion_total',
  'recaudacion_preventa',
  'recaudacion_directa',
  'recaudacion_sin_clasificar',
  'recaudacion_neta',
  'costo_mercaderia',
  'comisiones',
  'ganancia',
  'notas_credito',
  'mercaderia_neta',
  'reintegros',
  'costo_recuperado',
  'comisiones_revertidas',
];

double _readAmount(Object? value) {
  final amount = double.tryParse(value?.toString() ?? '');
  if (amount == null || !amount.isFinite) {
    throw const FormatException('Importe comercial inválido');
  }
  return amount;
}

class CommercialSummaryPage extends StatefulWidget {
  const CommercialSummaryPage({
    super.key,
    this.readPeriod,
    this.balanceRepository,
    this.nowArgentina = ArgentinaDateUtils.ahoraArgentina,
  });

  final CommercialPeriodReader? readPeriod;
  final BalanceRepository? balanceRepository;
  final DateTime Function() nowArgentina;

  @override
  State<CommercialSummaryPage> createState() => _CommercialSummaryPageState();
}

class _CommercialSummaryPageState extends State<CommercialSummaryPage> {
  int _period = 0;
  DateTimeRange? _custom;
  int _periodRequest = 0;
  int _debtRequest = 0;
  bool _periodLoading = true;
  bool _debtLoading = true;
  bool _periodError = false;
  bool _debtError = false;
  int? _debtCents;
  Map<String, double>? _amounts;
  List<MapEntry<String, double>> _commissions = [];

  late final BalanceRepository _balances =
      widget.balanceRepository ?? BalanceRepository(Supabase.instance.client);

  @override
  void initState() {
    super.initState();
    _loadPeriod();
    _loadDebt();
  }

  Future<Map<String, dynamic>> _readPeriod(DateTime start, DateTime end) async {
    final client = Supabase.instance.client;
    final response = await client.rpc(
      'resumen_comercial',
      params: {
        'p_inicio': start.toIso8601String(),
        'p_fin': end.toIso8601String(),
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<void> _loadPeriod() async {
    final request = ++_periodRequest;
    setState(() {
      _periodLoading = true;
      _periodError = false;
      _amounts = null;
    });
    try {
      final now = widget.nowArgentina();
      final today = DateTime.utc(now.year, now.month, now.day);
      var start = today;
      var last = today;
      if (_period == 1) {
        start = today.subtract(Duration(days: today.weekday - DateTime.monday));
        last = start.add(const Duration(days: 6));
      } else if (_period == 2) {
        start = _custom!.start;
        last = _custom!.end;
      }
      final data = await (widget.readPeriod ?? _readPeriod)(
        ArgentinaDateUtils.inicioDiaUtc(start),
        ArgentinaDateUtils.finDiaExclusivoUtc(last),
      );
      final amounts = {
        for (final key in _amountKeys) key: _readAmount(data[key]),
      };
      final commissions = Map<String, dynamic>.from(
        data['comisiones_por_preventista'] as Map,
      ).map((id, value) => MapEntry(id, _readAmount(value)));
      final names = <String, String>{};
      if (commissions.isNotEmpty && widget.readPeriod == null) {
        final users = await Supabase.instance.client
            .from('usuarios')
            .select('id,nombre,apellido')
            .inFilter('id', commissions.keys.toList());
        for (final user in users) {
          final name = "${user['nombre'] ?? ''} ${user['apellido'] ?? ''}"
              .trim();
          if (name.isNotEmpty) names[user['id'] as String] = name;
        }
      }
      if (!mounted || request != _periodRequest) return;
      setState(() {
        _amounts = amounts;
        _commissions = [
          for (final entry in commissions.entries)
            if (entry.value != 0)
              MapEntry(
                names[entry.key] ?? 'Preventista (${entry.key})',
                entry.value,
              ),
        ];
        _periodLoading = false;
      });
    } catch (_) {
      if (!mounted || request != _periodRequest) return;
      setState(() {
        _periodError = true;
        _periodLoading = false;
      });
    }
  }

  Future<void> _loadDebt() async {
    final request = ++_debtRequest;
    setState(() {
      _debtLoading = true;
      _debtError = false;
      _debtCents = null;
    });
    try {
      await _balances.requireAdmin();
      final total = debtorTotal(await _balances.debtors());
      if (!mounted || request != _debtRequest) return;
      setState(() {
        _debtCents = total;
        _debtLoading = false;
      });
    } catch (_) {
      if (!mounted || request != _debtRequest) return;
      setState(() {
        _debtError = true;
        _debtLoading = false;
      });
    }
  }

  Future<void> _openBalances() async {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => const BalancesPage()));
    if (!mounted) return;
    _loadDebt();
    _loadPeriod();
  }

  Future<void> _selectPeriod(BuildContext context, int period) async {
    if (period == 2) {
      final now = widget.nowArgentina();
      final range = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime(now.year, now.month, now.day),
        initialDateRange: _custom,
      );
      if (!mounted || range == null) return;
      _custom = range;
    }
    setState(() => _period = period);
    _loadPeriod();
  }

  @override
  Widget build(BuildContext context) {
    final inherited = Theme.of(context);
    // The Android route opens this page directly under the app's light theme.
    final theme = inherited.brightness == Brightness.dark
        ? inherited
        : ThemeData(
            useMaterial3: inherited.useMaterial3,
            platform: inherited.platform,
            colorScheme: ColorScheme.fromSeed(
              seedColor: inherited.colorScheme.primary,
              brightness: Brightness.dark,
            ),
          );
    return Theme(
      data: theme,
      child: Material(
        color: theme.colorScheme.surface,
        child: Builder(builder: _buildContent),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final amounts = _amounts;
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Resumen comercial', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Hoy')),
              ButtonSegment(value: 1, label: Text('Semana')),
              ButtonSegment(value: 2, label: Text('Personalizado')),
            ],
            selected: {_period},
            onSelectionChanged: (selection) =>
                _selectPeriod(context, selection.single),
          ),
        ),
        if (_period == 2)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => _selectPeriod(context, 2),
              child: Text(
                '${MaterialLocalizations.of(context).formatCompactDate(_custom!.start)}'
                ' – ${MaterialLocalizations.of(context).formatCompactDate(_custom!.end)}',
              ),
            ),
          ),
        const SizedBox(height: 16),
        if (_periodLoading) const LinearProgressIndicator(),
        if (_periodError)
          Row(
            children: [
              const Expanded(
                child: Text('No se pudo cargar el resumen del período.'),
              ),
              TextButton(
                onPressed: _loadPeriod,
                child: const Text('Reintentar'),
              ),
            ],
          ),
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = 12.0;
            final columns = constraints.maxWidth >= 1040
                ? 4
                : constraints.maxWidth >= 540
                ? 2
                : 1;
            final width =
                (constraints.maxWidth - (columns - 1) * gap) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                _indicator(
                  context,
                  width,
                  'VENTAS EFECTIVAS',
                  Icons.inventory_2_outlined,
                  amounts?['entrega_total'],
                  'Valor de lo entregado en el período.',
                ),
                _indicator(
                  context,
                  width,
                  'RECAUDACIÓN',
                  Icons.payments_outlined,
                  amounts?['recaudacion_total'],
                  'Cobros del período, incluso de deudas anteriores.',
                ),
                _indicator(
                  context,
                  width,
                  'TOTAL POR COBRAR',
                  Icons.account_balance_wallet_outlined,
                  _debtCents == null ? null : _debtCents! / 100,
                  _debtError
                      ? 'No se pudo consultar la deuda acumulada.'
                      : 'Todos los clientes y períodos.',
                  loading: _debtLoading,
                  debt: true,
                ),
                _indicator(
                  context,
                  width,
                  'RESULTADO COMERCIAL',
                  Icons.trending_up,
                  amounts?['ganancia'],
                  'Después de costos, comisiones y ajustes. Excluye gastos generales.',
                ),
              ],
            );
          },
        ),
        if (amounts != null) ...[
          const SizedBox(height: 16),
          ..._details(context, amounts),
        ],
      ],
    );
  }

  Widget _indicator(
    BuildContext context,
    double width,
    String title,
    IconData icon,
    double? value,
    String detail, {
    bool? loading,
    bool debt = false,
  }) {
    final pending = loading ?? _periodLoading;
    return SizedBox(
      width: width,
      child: Card(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        margin: EdgeInsets.zero,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 178),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value != null
                        ? CommercialSummaryCard.money(value)
                        : pending
                        ? 'Consultando…'
                        : 'No disponible',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                const SizedBox(height: 4),
                Text(detail, style: Theme.of(context).textTheme.bodySmall),
                if (debt)
                  Wrap(
                    children: [
                      TextButton(
                        onPressed: _openBalances,
                        child: const Text('Ir a Saldos'),
                      ),
                      if (_debtError)
                        TextButton(
                          onPressed: _loadDebt,
                          child: const Text('Reintentar deuda'),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _details(BuildContext context, Map<String, double> data) {
    double amount(String key) => data[key]!;
    final hasAdjustments = [
      'notas_credito',
      'reintegros',
      'costo_recuperado',
      'comisiones_revertidas',
    ].any((key) => amount(key) != 0);
    return [
      _section(
        context,
        'Ventas',
        [
          MapEntry('Preventa entregada', amount('entrega_preventa')),
          MapEntry('Venta directa entregada', amount('entrega_directa')),
          MapEntry('Entregas sin clasificar', amount('entrega_sin_clasificar')),
          MapEntry('Mercadería entregada', amount('entrega_total')),
          MapEntry('Preventa facturada', amount('venta_preventa')),
        ],
        'La mercadería se cuenta al finalizar la entrega e incluye productos agregados. La facturación es un dato aparte, por fecha de boleta.',
      ),
      _section(
        context,
        'Cobros',
        [
          MapEntry('Aplicado a preventas', amount('recaudacion_preventa')),
          MapEntry('Aplicado a ventas directas', amount('recaudacion_directa')),
          MapEntry(
            'Cobros sin clasificar',
            amount('recaudacion_sin_clasificar'),
          ),
          MapEntry('Recaudación total', amount('recaudacion_total')),
          if (amount('reintegros') != 0)
            MapEntry('Cobros menos reintegros', amount('recaudacion_neta')),
        ],
        'Se usa la fecha del cobro. Puede corresponder a deudas anteriores. Aplicar crédito existente no genera un cobro nuevo.',
      ),
      _section(
        context,
        'Costos y rentabilidad',
        [
          MapEntry('Costo de mercadería entregada', amount('costo_mercaderia')),
          MapEntry('Comisiones de lo entregado', amount('comisiones')),
          ..._commissions,
          MapEntry('Resultado comercial', amount('ganancia')),
        ],
        'El resultado incluye notas de crédito, costo recuperado y comisiones revertidas. Excluye gastos generales y no mide dinero disponible en caja.',
      ),
      if (hasAdjustments)
        _section(
          context,
          'Ajustes y devoluciones',
          [
            MapEntry('Notas de crédito internas', amount('notas_credito')),
            MapEntry('Reintegros', amount('reintegros')),
            MapEntry('Costo recuperado', amount('costo_recuperado')),
            MapEntry('Comisiones revertidas', amount('comisiones_revertidas')),
            MapEntry(
              'Entregado neto de notas de crédito',
              amount('mercaderia_neta'),
            ),
          ],
          'Las notas se cuentan en su fecha y pueden corresponder a ventas anteriores. El costo se recupera al recibir mercadería apta.',
        ),
    ];
  }

  Widget _section(
    BuildContext context,
    String title,
    List<MapEntry<String, double>> rows,
    String note,
  ) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: ExpansionTile(
        key: PageStorageKey(title),
        title: Text(title),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          for (final row in rows)
            if (row.value != 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(child: Text(row.key)),
                    const SizedBox(width: 12),
                    Text(CommercialSummaryCard.money(row.value)),
                  ],
                ),
              ),
          Align(alignment: Alignment.centerLeft, child: Text(note)),
        ],
      ),
    );
  }
}
