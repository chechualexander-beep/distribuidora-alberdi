import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/desktop_records.dart';
import '../../core/desktop_table.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/argentina_date_utils.dart';
import '../orders/credit_notes_page.dart' show ncMoney, ncNumber;

typedef StatisticsLoader =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> params);

class CommissionStatisticsPage extends StatefulWidget {
  final Future<bool> Function()? administratorLoader;
  final Future<List<Map<String, dynamic>>> Function()? usersLoader;
  final String? preventistaId;
  final StatisticsLoader? loader;
  const CommissionStatisticsPage({
    super.key,
    this.administratorLoader,
    this.usersLoader,
    this.preventistaId,
    this.loader,
  });
  @override
  State<CommissionStatisticsPage> createState() =>
      _CommissionStatisticsPageState();
}

class _CommissionStatisticsPageState extends State<CommissionStatisticsPage> {
  late DateTime _desde, _hasta;
  String _periodo = 'hoy', _metrica = 'cantidad', _evolucion = 'comision';
  String? _vendedor;
  Map<String, dynamic>? _datos;
  List<Map<String, dynamic>> _usuarios = [];
  bool _cargando = true;
  bool _administrador = false;
  bool _accesoCargado = false;
  String? _error;
  int _peticion = 0;
  DateTime get _hoy {
    final now = ArgentinaDateUtils.ahoraArgentina();
    return DateTime(now.year, now.month, now.day);
  }

  String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String _fecha(DateTime d) => '${d.day}/${d.month}/${d.year}';
  List<Map<String, dynamic>> _lista(dynamic value) =>
      List<Map<String, dynamic>>.from(value as List? ?? []);

  @override
  void initState() {
    super.initState();
    _desde = _hasta = _hoy;
    _vendedor = widget.preventistaId;
    _cargar();
  }

  Future<void> _cargar() async {
    final request = ++_peticion;
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      if (!_accesoCargado) {
        final admin = widget.administratorLoader != null
            ? await widget.administratorLoader!()
            : await Supabase.instance.client.rpc('es_administrador') == true;
        final users = admin
            ? (widget.usersLoader != null
                  ? await widget.usersLoader!()
                  : _lista(
                      await Supabase.instance.client
                          .from('usuarios')
                          .select('id,nombre,apellido')
                          .order('nombre'),
                    ))
            : <Map<String, dynamic>>[];
        if (!mounted || request != _peticion) return;
        _administrador = admin;
        _usuarios = users;
        _accesoCargado = true;
      }
      final params = <String, dynamic>{
        'p_desde': _iso(_desde),
        'p_hasta': _iso(_hasta),
        'p_preventista_id': _vendedor,
        'p_metrica': _metrica,
      };
      final result = widget.loader != null
          ? await widget.loader!(params)
          : Map<String, dynamic>.from(
              await Supabase.instance.client.rpc(
                'estadisticas_comisiones',
                params: params,
              ),
            );
      if (!mounted || request != _peticion) return;
      setState(() {
        _datos = result;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted || request != _peticion) return;
      setState(() {
        _error =
            'No se pudieron cargar las estadísticas. Revisá la conexión e intentá nuevamente.';
        _cargando = false;
      });
    }
  }

  Future<void> _elegirPeriodo(String value) async {
    DateTime start = _hoy, end = _hoy;
    if (value == 'personalizado') {
      final range = await showDateRangePicker(
        context: context,
        firstDate: DateTime(_hoy.year - 10),
        lastDate: _hoy,
        initialDateRange: DateTimeRange(start: _desde, end: _hasta),
      );
      if (range == null || !mounted) return;
      start = range.start;
      end = range.end;
    } else if (value == 'semana') {
      start = _hoy.subtract(Duration(days: _hoy.weekday - 1));
    }
    setState(() {
      _periodo = value;
      _desde = start;
      _hasta = end;
    });
    await _cargar();
  }

  void _verCliente(Map<String, dynamic> cliente) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(cliente['nombre'].toString()),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Operaciones del ${_fecha(_desde)} al ${_fecha(_hasta)}'),
                ..._lista(cliente['operaciones']).map(
                  (o) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${o['tipo']} · ${_fecha(DateTime.parse(o['dia']))}',
                    ),
                    subtitle: Text(
                      'Pedido ${o['pedido_id'].toString().substring(0, 8).toUpperCase()}\nVenta: ${ncMoney(o['venta'])}\nComisión: ${ncMoney(o['comision'])}',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Widget _tarjeta(String titulo, String valor, String detalle) => SizedBox(
    width: 260,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo),
            const SizedBox(height: 8),
            Text(valor, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(detalle, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    ),
  );

  Widget _ranking(
    String titulo,
    List<Map<String, dynamic>> filas,
    String campo, {
    bool clientes = false,
  }) {
    final maximo = filas.fold<double>(
      0,
      (v, r) => math.max(v, ncNumber(r[campo]).abs()),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo, style: Theme.of(context).textTheme.titleLarge),
            if (!clientes) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: ['cantidad', 'venta', 'comision']
                    .map(
                      (m) => ChoiceChip(
                        label: Text(
                          {
                            'cantidad': 'Cantidad',
                            'venta': 'Venta neta',
                            'comision': 'Comisión neta',
                          }[m]!,
                        ),
                        selected: _metrica == m,
                        onSelected: _cargando
                            ? null
                            : (_) {
                                setState(() => _metrica = m);
                                _cargar();
                              },
                      ),
                    )
                    .toList(),
              ),
              const Text(
                'Cantidades netas por presentación; se descuentan las devoluciones.',
              ),
            ] else
              const Text(
                'Comisión neta. Tocá un cliente para ver sus operaciones.',
              ),
            if (filas.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('Sin movimientos en este período.'),
              ),
            if (useDesktopLayout(context))
              DesktopRecords(
                embedded: true,
                records: filas,
                fields: [
                  DesktopField(
                    clientes ? 'Cliente' : 'Producto',
                    (r) => r['nombre'],
                    width: 230,
                  ),
                  DesktopField(
                    campo == 'cantidad'
                        ? 'Cantidad'
                        : campo == 'venta'
                        ? 'Venta neta'
                        : 'Comisión neta',
                    (r) => campo == 'cantidad'
                        ? ncNumber(r[campo]).toStringAsFixed(2)
                        : ncMoney(r[campo]),
                    numeric: true,
                    width: 135,
                  ),
                ],
                onOpen: clientes ? _verCliente : null,
              )
            else
              ...filas.asMap().entries.map((entry) {
                final r = entry.value, valor = ncNumber(entry.value[campo]);
                return InkWell(
                  onTap: clientes ? () => _verCliente(r) : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${entry.key + 1}. ${r['nombre']}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          campo == 'cantidad'
                              ? '${valor.toStringAsFixed(2)} unidades'
                              : ncMoney(valor),
                        ),
                        const SizedBox(height: 5),
                        LinearProgressIndicator(
                          value: maximo == 0 ? 0 : valor.abs() / maximo,
                          color: valor < 0
                              ? Theme.of(context).colorScheme.error
                              : null,
                          minHeight: 7,
                        ),
                        if (clientes)
                          Text(
                            'Venta neta: ${ncMoney(r['venta'])}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _contenido() {
    final d = _datos!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (d['hay_movimientos'] != true)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text('No hay entregas ni devoluciones en este período.'),
            ),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _tarjeta(
              'Comisión neta generada',
              ncMoney(d['comision_neta']),
              'Bruta ${ncMoney(d['comision_bruta'])} · Ajustes −${ncMoney(d['ajustes'])}',
            ),
            _tarjeta(
              'Venta neta entregada',
              ncMoney(d['venta_neta']),
              'Entregada ${ncMoney(d['venta_bruta'])} · Devoluciones −${ncMoney(d['devoluciones'])}',
            ),
            _tarjeta(
              'Clientes con ventas',
              '${d['clientes']}',
              'Clientes distintos con entregas en el período.',
            ),
            _tarjeta(
              'Promedio por cliente',
              d['promedio'] == null ? '—' : ncMoney(d['promedio']),
              'Venta neta del período / clientes con entregas. Incluye ajustes de ventas anteriores.',
            ),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Evolución ${d['semanal'] == true ? 'semanal' : 'diaria'}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Wrap(
                  spacing: 8,
                  children: ['comision', 'venta']
                      .map(
                        (m) => ChoiceChip(
                          label: Text(
                            m == 'comision' ? 'Comisión neta' : 'Venta neta',
                          ),
                          selected: _evolucion == m,
                          onSelected: (_) => setState(() => _evolucion = m),
                        ),
                      )
                      .toList(),
                ),
                const Text(
                  'Importes en pesos. Tocá una barra para ver el valor. Los negativos aparecen debajo de cero.',
                ),
                StatisticsBars(serie: _lista(d['serie']), campo: _evolucion),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final clients = _ranking(
              '10 clientes con más comisiones',
              _lista(d['ranking_clientes']),
              'comision',
              clientes: true,
            );
            final products = _ranking(
              '10 productos destacados',
              _lista(d['ranking_productos']),
              _metrica,
            );
            if (constraints.maxWidth < 850) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [clients, const SizedBox(height: 12), products],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: clients),
                const SizedBox(width: 12),
                Expanded(child: products),
              ],
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Estadísticas'),
      actions: [
        IconButton(
          tooltip: 'Actualizar',
          onPressed: _cargando ? null : _cargar,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          _administrador ? 'Resultados comerciales' : 'Mis resultados',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const Text(
          'Incluye preventa y venta directa, con comisiones pagadas y pendientes. No representa el importe pendiente de cobrar.',
        ),
        const SizedBox(height: 16),
        if (_administrador && _usuarios.isNotEmpty) ...[
          DropdownButtonFormField<String>(
            initialValue: _vendedor ?? '',
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Preventista'),
            items: [
              const DropdownMenuItem(value: '', child: Text('Todos')),
              ..._usuarios.map(
                (u) => DropdownMenuItem(
                  value: u['id'].toString(),
                  child: Text('${u['nombre']} ${u['apellido'] ?? ''}'),
                ),
              ),
            ],
            onChanged: _cargando
                ? null
                : (v) {
                    setState(() => _vendedor = v == '' ? null : v);
                    _cargar();
                  },
          ),
          const SizedBox(height: 16),
        ],
        Wrap(
          spacing: 8,
          children:
              {
                    'hoy': 'Hoy',
                    'semana': 'Esta semana',
                    'personalizado': 'Personalizado',
                  }.entries
                  .map(
                    (e) => ChoiceChip(
                      label: Text(e.value),
                      selected: _periodo == e.key,
                      onSelected: (_) => _elegirPeriodo(e.key),
                    ),
                  )
                  .toList(),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            '${_fecha(_desde)} al ${_fecha(_hasta)} · Hora argentina',
          ),
        ),
        const Text(
          'Entregas por fecha de finalización (o entrega histórica). Devoluciones por fecha de la nota de crédito.',
        ),
        const SizedBox(height: 16),
        if (_cargando)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_error != null)
          Column(
            children: [
              Text(_error!),
              TextButton(onPressed: _cargar, child: const Text('Reintentar')),
            ],
          )
        else if (_datos != null)
          _contenido(),
      ],
    ),
  );
}

/// Barras con cero central: los ajustes negativos nunca se ocultan.
class StatisticsBars extends StatelessWidget {
  final List<Map<String, dynamic>> serie;
  final String campo;
  const StatisticsBars({super.key, required this.serie, required this.campo});
  @override
  Widget build(BuildContext context) {
    final maximo = serie.fold<double>(
      0,
      (v, r) => math.max(v, ncNumber(r[campo]).abs()),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Escala: ±${ncMoney(maximo)}'),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: serie.map((r) {
              final value = ncNumber(r[campo]);
              final height = maximo == 0 ? 0.0 : value.abs() / maximo * 80;
              final date = DateTime.parse(r['dia']);
              return Tooltip(
                triggerMode: TooltipTriggerMode.tap,
                message:
                    '${date.day}/${date.month}/${date.year}: ${ncMoney(value)}',
                child: Semantics(
                  label:
                      '${date.day}/${date.month}/${date.year}: ${ncMoney(value)}',
                  child: SizedBox(
                    width: 52,
                    child: Column(
                      children: [
                        SizedBox(
                          height: 85,
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: Container(
                              width: 22,
                              height: value > 0 ? height : 0,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                        const Divider(height: 1),
                        SizedBox(
                          height: 85,
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: Container(
                              width: 22,
                              height: value < 0 ? height : 0,
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                        Text(
                          '${date.day}/${date.month}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}
