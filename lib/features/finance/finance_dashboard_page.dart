import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_theme.dart';
import '../../core/desktop_records.dart';
import '../../core/network_status.dart';
import '../stock/stock_data.dart';
import 'business_health.dart';
import 'finance_data.dart';
import 'finance_forms.dart' show isoDate;

/// Foto del capital del negocio (hoy o guardada un día).
class CapitalSnapshot {
  const CapitalSnapshot({
    required this.fecha,
    required this.plata,
    required this.mercaderia,
    required this.clientes,
    required this.aFavor,
    required this.proveedores,
    required this.total,
    this.productosConStock,
    this.productosSinCosto = 0,
    this.plataIniciada = true,
  });

  final DateTime fecha;
  final double plata;
  final double mercaderia;
  final double clientes;
  final double aFavor;
  final double proveedores;
  final double total;
  final int? productosConStock;
  final int productosSinCosto;
  final bool plataIniciada;

  static CapitalSnapshot? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final j = Map<String, dynamic>.from(raw);
    return CapitalSnapshot(
      fecha: DateTime.tryParse(j['fecha']?.toString() ?? '') ?? DateTime.now(),
      plata: stockNum(j['plata']),
      mercaderia: stockNum(j['mercaderia']),
      clientes: stockNum(j['clientes']),
      aFavor: stockNum(j['a_favor']),
      proveedores: stockNum(j['proveedores']),
      total: stockNum(j['total']),
      productosConStock: j.containsKey('productos_con_stock') ? stockNum(j['productos_con_stock']).round() : null,
      productosSinCosto: stockNum(j['productos_sin_costo']).round(),
      plataIniciada: j['plata_iniciada'] != false,
    );
  }
}

class Dashboard {
  const Dashboard({
    required this.mes,
    required this.actual,
    required this.dia,
    required this.dias,
    required this.ventas,
    required this.costo,
    required this.comisiones,
    required this.notasCredito,
    required this.gananciaComercial,
    required this.margen,
    required this.gastosNegocio,
    required this.gananciaNegocio,
    required this.hogar,
    required this.quedo,
    required this.plataDesde,
    required this.plataParcial,
    required this.ventasNecesarias,
    required this.ventas12,
    required this.capital,
    required this.capitalInicio,
    required this.capitalCierre,
    this.sueldo = 0,
    this.casa = 0,
    this.personal = 0,
    this.aportes = 0,
    this.gastosPorCategoria = const {},
  });

  final DateTime mes;
  final bool actual;
  final int dia;
  final int dias;
  final double ventas;
  final double costo;
  final double comisiones;
  final double notasCredito;
  final double gananciaComercial;
  final double? margen;
  final double gastosNegocio;
  final double gananciaNegocio;
  final double hogar;
  final double quedo;
  final DateTime? plataDesde;
  final bool plataParcial;
  final double? ventasNecesarias;
  final double ventas12;
  final CapitalSnapshot? capital;
  final CapitalSnapshot? capitalInicio;
  final CapitalSnapshot? capitalCierre;

  /// Retiros por separado (suman [hogar]).
  final double sueldo;
  final double casa;
  final double personal;

  /// Plata tuya que entró al negocio (no es ganancia).
  final double aportes;
  final Map<String, double> gastosPorCategoria;

  static Dashboard fromJson(Map<String, dynamic> j) {
    double? opt(String k) => j[k] == null ? null : stockNum(j[k]);
    return Dashboard(
      mes: DateTime.tryParse(j['mes']?.toString() ?? '') ?? DateTime.now(),
      actual: j['actual'] == true,
      dia: stockNum(j['dia']).round(),
      dias: stockNum(j['dias']).round(),
      ventas: stockNum(j['ventas']),
      costo: stockNum(j['costo']),
      comisiones: stockNum(j['comisiones']),
      notasCredito: stockNum(j['notas_credito']),
      gananciaComercial: stockNum(j['ganancia_comercial']),
      margen: opt('margen'),
      gastosNegocio: stockNum(j['gastos_negocio']),
      gananciaNegocio: stockNum(j['ganancia_negocio']),
      hogar: stockNum(j['hogar']),
      quedo: stockNum(j['quedo']),
      plataDesde: DateTime.tryParse(j['plata_desde']?.toString() ?? ''),
      plataParcial: j['plata_parcial'] == true,
      ventasNecesarias: opt('ventas_necesarias'),
      ventas12: stockNum(j['ventas_12_meses']),
      capital: CapitalSnapshot.fromJson(j['capital']),
      capitalInicio: CapitalSnapshot.fromJson(j['capital_inicio']),
      capitalCierre: CapitalSnapshot.fromJson(j['capital_cierre']),
      sueldo: stockNum(j['sueldo']),
      casa: stockNum(j['casa']),
      personal: stockNum(j['personal']),
      aportes: stockNum(j['aportes']),
      gastosPorCategoria: {
        for (final e in Map<String, dynamic>.from(j['gastos_por_categoria'] as Map? ?? const {}).entries)
          e.key: stockNum(e.value),
      },
    );
  }
}

Future<Dashboard> fetchDashboard(SupabaseClient client, DateTime month) async {
  final result = await client.rpc('fin_tablero', params: {'p_mes': isoDate(month)}, get: true);
  return Dashboard.fromJson(Map<String, dynamic>.from(result as Map));
}

/// Guarda la foto del capital de hoy (para comparar mes a mes). Si falla, no pasa nada.
Future<void> saveCapitalSnapshot(SupabaseClient client) async {
  try {
    await client.rpc('fin_guardar_capital').timeout(const Duration(seconds: 15));
  } catch (_) {}
}

const _monthNames = [
  'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
  'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
];

String _pct(double v) => '${(v * 100).toStringAsFixed(1).replaceAll('.', ',')}%';

/// Tablero del mes: ganancia real, cuánto fue a la casa, cuánto hay que vender y el capital.
class FinanceDashboardPage extends StatefulWidget {
  const FinanceDashboardPage({super.key, this.client, this.initial, this.initialHealth});
  final SupabaseClient? client;

  /// Solo para pruebas.
  final Dashboard? initial;
  final BusinessHealth? initialHealth;

  @override
  State<FinanceDashboardPage> createState() => _FinanceDashboardPageState();
}

class _FinanceDashboardPageState extends State<FinanceDashboardPage> {
  SupabaseClient get _client => widget.client ?? Supabase.instance.client;
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  Dashboard? _data;
  BusinessHealth? _health;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _data = widget.initial;
    _health = widget.initialHealth;
    if (_data == null) _first();
  }

  /// La salud no frena el tablero: si falla, la tarjeta no aparece.
  Future<void> _loadHealth() async {
    try {
      final h = await fetchBusinessHealth(_client);
      if (mounted) setState(() => _health = h);
    } catch (_) {}
  }

  Future<void> _first() async {
    await saveCapitalSnapshot(_client);
    await _load();
  }

  Future<void> _refresh() async {
    await Future.wait([_load(), if (widget.initial == null) _loadHealth()]);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_health == null && widget.initial == null) _loadHealth();
      final data = await fetchDashboard(_client, _month);
      if (!mounted) return;
      setState(() {
        _data = data;
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

  void _move(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      _data = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final now = DateTime.now();
    final isCurrent = _month.year == now.year && _month.month == now.month;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tablero del mes'),
        actions: [IconButton(tooltip: 'Actualizar', icon: const Icon(Icons.refresh), onPressed: _loading ? null : _refresh)],
      ),
      body: DesktopForm(
        maxWidth: 900,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(onPressed: () => _move(-1), icon: const Icon(Icons.chevron_left)),
                Text(
                  '${_monthNames[_month.month - 1]} ${_month.year}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(onPressed: isCurrent ? null : () => _move(1), icon: const Icon(Icons.chevron_right)),
              ],
            ),
            Expanded(
              child: data == null
                  ? Center(
                      child: _error == null
                          ? const CircularProgressIndicator()
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_error!, textAlign: TextAlign.center),
                                const SizedBox(height: 12),
                                FilledButton(onPressed: _load, child: const Text('Reintentar')),
                              ],
                            ),
                    )
                  : RefreshIndicator(
                      onRefresh: _refresh,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 32),
                        children: [
                          if (isCurrent && _health != null) HealthCard(health: _health!),
                          _result(data),
                          if (data.gastosPorCategoria.isNotEmpty) _expenses(data),
                          _breakEven(data),
                          _capital(data),
                          _yearSales(data),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _line(String label, double value, {bool bold = false, Color? color, double size = 15, String? hint}) {
    final t = Tonos.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                text: label,
                style: TextStyle(fontSize: size, fontWeight: bold ? FontWeight.bold : null),
                children: [
                  if (hint != null)
                    TextSpan(text: '  $hint', style: TextStyle(fontSize: 12, color: t.secundario, fontWeight: FontWeight.normal)),
                ],
              ),
            ),
          ),
          Text(
            pesos(value),
            style: TextStyle(fontSize: size, fontWeight: bold ? FontWeight.bold : FontWeight.w500, color: color),
          ),
        ],
      ),
    );
  }

  Widget _card(String title, List<Widget> children) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    ),
  );

  Widget _note(String text, {Color? color}) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(text, style: TextStyle(fontSize: 13, color: color ?? Tonos.of(context).secundario)),
  );

  Widget _box(String text, {required bool good}) {
    final t = Tonos.of(context);
    final (bg, fg) = good ? t.etiquetaVerde : t.etiquetaRoja;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(text, style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
    );
  }

  Widget _result(Dashboard d) {
    final t = Tonos.of(context);
    return _card(
      d.actual ? 'Resultado · al día ${d.dia} de ${d.dias}' : 'Resultado del mes',
      [
        _line('Ventas entregadas', d.ventas),
        _line('− Costo de la mercadería', -d.costo, color: t.secundario),
        _line('− Comisiones', -d.comisiones, color: t.secundario),
        if (d.notasCredito.abs() >= 1) _line('± Notas de crédito', d.notasCredito, color: t.secundario),
        const Divider(),
        _line(
          '= Ganancia comercial',
          d.gananciaComercial,
          bold: true,
          hint: d.margen == null ? null : 'margen ${_pct(d.margen!)}',
        ),
        _line('− Gastos del negocio', -d.gastosNegocio, color: t.secundario),
        _line('= Ganancia del negocio', d.gananciaNegocio, bold: true, color: d.gananciaNegocio < 0 ? t.rojo : t.verde),
        _line('− Retiros (sueldo, casa y personal)', -d.hogar, color: t.secundario),
        if (d.sueldo > 0) _line('      Mi sueldo', -d.sueldo, color: t.secundario, size: 13),
        if (d.casa > 0) _line('      Casa', -d.casa, color: t.secundario, size: 13),
        if (d.personal > 0) _line('      Personal', -d.personal, color: t.secundario, size: 13),
        const Divider(),
        _line('= Quedó para el negocio', d.quedo, bold: true, size: 18, color: d.quedo < 0 ? t.rojo : t.verde),
        if (d.quedo < 0)
          _box('Salió del capital: te llevaste ${pesos(-d.quedo)} más de lo que ganó el negocio.', good: false)
        else if (d.gananciaComercial > 0)
          _box('Quedaron ${pesos(d.quedo)} para reponer mercadería, ahorrar o crecer.', good: true),
        if (d.aportes > 0)
          _note('Además pusiste ${pesos(d.aportes)} de tu bolsillo: entra a la caja pero no es ganancia.'),
        if (d.plataParcial)
          _note(
            d.plataDesde == null
                ? 'Falta la foto inicial en "Plata del negocio": los gastos y lo de la casa todavía no se cuentan.'
                : 'Los gastos y los retiros se cuentan desde el ${diaMes(d.plataDesde!.toLocal())} (foto inicial); '
                      'las ventas, desde el 1: este mes la ganancia del negocio se ve más alta de lo que es. '
                      'La salud del negocio lo mide bien.',
          ),
        if (d.actual && d.dia > 0 && d.dia < d.dias && d.ventas > 0)
          _note(
            'Ritmo: ${pesos(d.ventas / d.dia)} por día; si sigue así, el mes cierra con '
            '${pesos(d.ventas / d.dia * d.dias)} en ventas.',
          ),
      ],
    );
  }

  Widget _expenses(Dashboard d) {
    final rows = d.gastosPorCategoria.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final total = rows.fold(0.0, (s, e) => s + e.value);
    return _card('Gastos del negocio por categoría', [
      for (final e in rows)
        _line(e.key, e.value, hint: total <= 0 ? null : porcentaje(e.value / total)),
      const Divider(),
      _line('Total', total, bold: true),
    ]);
  }

  Widget _breakEven(Dashboard d) {
    final t = Tonos.of(context);
    final need = d.ventasNecesarias;
    if (need == null || need <= 0 || d.margen == null) {
      return _card('¿Cuánto hay que vender?', [
        const Text('Aparece cuando haya gastos o plata para la casa anotados en el mes.'),
      ]);
    }
    final ratio = d.ventas / need;
    return _card('¿Cuánto hay que vender?', [
      Text(
        'Con tu margen de ${_pct(d.margen!)}, para cubrir los gastos del negocio y los retiros '
        '${d.actual ? 'anotados hasta hoy ' : ''}hay que vender ${pesos(need)}.',
      ),
      const SizedBox(height: 10),
      LinearProgressIndicator(
        value: ratio.clamp(0, 1).toDouble(),
        minHeight: 10,
        color: ratio >= 1 ? t.verde : t.rojo,
      ),
      const SizedBox(height: 4),
      Text(
        'Vendido ${pesos(d.ventas)} (${_pct(ratio)})',
        style: TextStyle(color: ratio >= 1 ? t.verde : t.rojo, fontWeight: FontWeight.w600),
      ),
      _note('Para ganar más: subir el margen (precios o mejores compras), vender más o bajar gastos.'),
    ]);
  }

  Widget _capital(Dashboard d) {
    final t = Tonos.of(context);
    final c = d.actual ? d.capital : d.capitalCierre;
    if (c == null) {
      return _card('Capital del negocio', [
        const Text('No hay foto del capital de ese mes. Se guarda sola cada vez que abrís el tablero.'),
      ]);
    }
    final before = d.capitalInicio;
    return _card(d.actual ? 'Capital del negocio hoy' : 'Capital del negocio al cierre (${diaMes(c.fecha)})', [
      _line('Plata (efectivo y billetera)', c.plata),
      _line('Mercadería al costo', c.mercaderia),
      _line('Te deben los clientes', c.clientes),
      if (c.aFavor > 0) _line('− Saldo a favor de clientes', -c.aFavor, color: t.secundario),
      if (c.proveedores > 0) _line('− Proveedores a pagar', -c.proveedores, color: t.secundario),
      const Divider(),
      _line('= Capital', c.total, bold: true, size: 18),
      if (before != null) ...[
        const SizedBox(height: 4),
        _line('Al empezar el mes (foto del ${diaMes(before.fecha)})', before.total, color: t.secundario),
        _box(
          c.total >= before.total
              ? 'El negocio creció ${pesos(c.total - before.total)}.'
              : 'El negocio se achicó ${pesos(before.total - c.total)}.',
          good: c.total >= before.total,
        ),
      ] else
        _note('La comparación aparece cuando haya una foto del mes anterior (se guarda sola al abrir el tablero).'),
      if (!c.plataIniciada) _note('Falta la foto inicial de la plata.'),
      if (c.productosConStock == 0)
        _note('La mercadería se valúa cuando cuentes el stock: hoy no hay productos contados.')
      else if (c.productosSinCosto > 0)
        _note('${c.productosSinCosto} productos con stock no tienen costo cargado: no suman a la mercadería.'),
    ]);
  }

  Widget _yearSales(Dashboard d) => _card('Ventas de los últimos 12 meses', [
    Text(pesos(d.ventas12), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
    _note(
      'Es lo que se usa para elegir la categoría del monotributo. Los topes los publica ARCA y cambian: '
      'confirmalo con tu contador. Cuenta desde que hay ventas cargadas en la app.',
    ),
  ]);
}
