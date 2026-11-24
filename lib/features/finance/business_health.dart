import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_theme.dart';
import '../stock/stock_data.dart';
import 'finance_data.dart';

// "Salud del negocio": cinco señales con semáforo y el sueldo sugerido. Ventas y margen se miden en
// meses enteros (hay datos de antes); la ganancia del negocio, los gastos y los retiros solo desde que
// se anotan gastos (la foto inicial de "Plata del negocio"), con las ventas de ese mismo tramo.

/// Lo medido de un mes desde que hay gastos anotados.
class HealthMeasured {
  const HealthMeasured({
    required this.desde,
    required this.hasta,
    required this.dias,
    required this.ventas,
    required this.gananciaComercial,
    required this.gananciaNegocio,
    required this.gastosNegocio,
    required this.retiros,
    required this.sueldo,
    required this.casa,
    required this.personal,
    required this.aportes,
  });

  final DateTime desde;
  final DateTime hasta;
  final int dias;
  final double ventas;
  final double gananciaComercial;
  final double gananciaNegocio;
  final double gastosNegocio;
  final double retiros;
  final double sueldo;
  final double casa;
  final double personal;
  final double aportes;

  static HealthMeasured? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final j = Map<String, dynamic>.from(raw);
    return HealthMeasured(
      desde: DateTime.tryParse(j['desde']?.toString() ?? '') ?? DateTime.now(),
      hasta: DateTime.tryParse(j['hasta']?.toString() ?? '') ?? DateTime.now(),
      dias: stockNum(j['dias']).round().clamp(1, 366),
      ventas: stockNum(j['ventas']),
      gananciaComercial: stockNum(j['ganancia_comercial']),
      gananciaNegocio: stockNum(j['ganancia_negocio']),
      gastosNegocio: stockNum(j['gastos_negocio']),
      retiros: stockNum(j['retiros']),
      sueldo: stockNum(j['sueldo']),
      casa: stockNum(j['casa']),
      personal: stockNum(j['personal']),
      aportes: stockNum(j['aportes']),
    );
  }
}

class HealthMonth {
  const HealthMonth({
    required this.mes,
    required this.actual,
    required this.ventas,
    required this.gananciaComercial,
    required this.margen,
    required this.completo,
    this.medido,
    this.capitalInicio,
    this.capitalInicioFecha,
    this.capitalFin,
  });

  final DateTime mes;
  final bool actual;
  final double ventas;
  final double gananciaComercial;
  final double? margen;

  /// Todo el mes tiene gastos anotados.
  final bool completo;
  final HealthMeasured? medido;
  final double? capitalInicio;
  final DateTime? capitalInicioFecha;
  final double? capitalFin;

  static HealthMonth fromJson(Map<String, dynamic> j) => HealthMonth(
    mes: DateTime.tryParse(j['mes']?.toString() ?? '') ?? DateTime.now(),
    actual: j['actual'] == true,
    ventas: stockNum(j['ventas']),
    gananciaComercial: stockNum(j['ganancia_comercial']),
    margen: j['margen'] == null ? null : stockNum(j['margen']),
    completo: j['completo'] == true,
    medido: HealthMeasured.fromJson(j['medido']),
    capitalInicio: j['capital_inicio'] == null ? null : stockNum(j['capital_inicio']),
    capitalInicioFecha: DateTime.tryParse(j['capital_inicio_fecha']?.toString() ?? ''),
    capitalFin: j['capital_fin'] == null ? null : stockNum(j['capital_fin']),
  );
}

enum Semaforo { verde, amarillo, rojo, gris }

class HealthSignal {
  const HealthSignal(this.titulo, this.valor, this.explicacion, this.estado);
  final String titulo;
  final String valor;
  final String explicacion;
  final Semaforo estado;
}

/// Reserva que queda en el negocio antes de calcular el sueldo sugerido.
const reservaSueldo = 0.25;

/// Semanas por mes (52 / 12).
const semanasPorMes = 52 / 12;

String porcentaje(double v) => '${(v * 100).toStringAsFixed(0)}%';
String _puntos(double v) => '${(v * 100).toStringAsFixed(1).replaceAll('.', ',')}%';

const _meses = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];
String nombreMes(DateTime d) => _meses[d.month - 1];

class BusinessHealth {
  const BusinessHealth({required this.inicio, required this.sueldoSemanal, required this.meses});

  /// Desde cuándo se anotan gastos (foto inicial). null = todavía no.
  final DateTime? inicio;
  final double? sueldoSemanal;

  /// Del más viejo al actual.
  final List<HealthMonth> meses;

  static BusinessHealth fromJson(Map<String, dynamic> j) => BusinessHealth(
    inicio: DateTime.tryParse(j['inicio']?.toString() ?? ''),
    sueldoSemanal: j['sueldo_semanal'] == null ? null : stockNum(j['sueldo_semanal']),
    meses: [
      for (final m in (j['meses'] as List? ?? const [])) HealthMonth.fromJson(Map<String, dynamic>.from(m as Map)),
    ],
  );

  /// Meses ya cerrados con todos los gastos anotados.
  List<HealthMonth> get cerrados => [for (final m in meses) if (m.completo && !m.actual) m];

  /// Lo que se mide: los últimos 3 meses cerrados completos; si no hay, todo lo anotado desde la foto inicial.
  List<HealthMeasured> get base {
    final c = cerrados;
    if (c.isNotEmpty) return [for (final m in c.skip(c.length > 3 ? c.length - 3 : 0)) m.medido!];
    return [for (final m in meses) if (m.medido != null) m.medido!];
  }

  bool get firme => cerrados.length >= 3;
  int get dias => base.fold(0, (s, m) => s + m.dias);
  double _sum(double Function(HealthMeasured m) f) => base.fold(0.0, (s, m) => s + f(m));
  double get ganancia => _sum((m) => m.gananciaNegocio);
  double get gananciaComercial => _sum((m) => m.gananciaComercial);
  double get gastos => _sum((m) => m.gastosNegocio);
  double get retiros => _sum((m) => m.retiros);
  double get aportes => _sum((m) => m.aportes);

  /// Ganancia del negocio llevada a un mes de 30 días.
  double get gananciaPorMes => dias == 0 ? 0 : ganancia / dias * 30.4;

  /// "septiembre a noviembre", "desde el 18/11 (6 días)".
  String get periodo {
    final c = cerrados;
    if (c.isNotEmpty) {
      final used = c.skip(c.length > 3 ? c.length - 3 : 0).toList();
      return used.length == 1
          ? nombreMes(used.first.mes)
          : '${nombreMes(used.first.mes)} a ${nombreMes(used.last.mes)}';
    }
    final first = base.isEmpty ? null : base.first.desde.toLocal();
    return first == null ? '' : 'desde el ${diaMes(first)} ($dias ${dias == 1 ? 'día' : 'días'})';
  }

  /// Sueldo semanal sugerido (redondeado a mil para abajo), o null si todavía no hay un mes cerrado.
  double? get sueldoSugerido {
    if (cerrados.isEmpty || gananciaPorMes <= 0) return null;
    final s = gananciaPorMes * (1 - reservaSueldo) / semanasPorMes;
    return (s / 1000).floor() * 1000.0;
  }

  /// El primer mes que va a tener todos los gastos anotados (el siguiente a la foto inicial).
  DateTime? get primerMesCompleto {
    final i = inicio?.toLocal();
    if (i == null) return null;
    final enPunto = i.day == 1 && i.hour == 0 && i.minute == 0;
    return DateTime(i.year, i.month + (enPunto ? 0 : 1));
  }

  List<HealthSignal> get senales {
    final out = <HealthSignal>[];
    final hayMedido = base.isNotEmpty;
    // 1) Ganancia del negocio.
    if (!hayMedido) {
      out.add(const HealthSignal('Ganancia del negocio', '–', 'Aparece cuando empieces a anotar gastos.', Semaforo.gris));
    } else {
      out.add(HealthSignal(
        'Ganancia del negocio',
        pesos(ganancia),
        cerrados.isEmpty
            ? 'Ventas menos costo, comisiones y gastos ${periodo.isEmpty ? '' : periodo}. Si sigue así, ≈ ${pesos(gananciaPorMes)} por mes.'
            : 'En $periodo: ≈ ${pesos(gananciaPorMes)} por mes.',
        ganancia > 0 ? Semaforo.verde : Semaforo.rojo,
      ));
    }
    // 2) Margen: este mes contra el promedio de los 3 anteriores (hay ventas de antes).
    final actual = meses.isEmpty ? null : meses.last;
    final previos = [
      for (final m in meses.take(meses.isEmpty ? 0 : meses.length - 1))
        if (m.margen != null && m.ventas > 0) m,
    ];
    final ultimos3 = previos.skip(previos.length > 3 ? previos.length - 3 : 0).toList();
    if (actual?.margen == null) {
      out.add(const HealthSignal('Margen de la venta', '–', 'Todavía no hay ventas este mes.', Semaforo.gris));
    } else if (ultimos3.isEmpty) {
      out.add(HealthSignal('Margen de la venta', _puntos(actual!.margen!), 'Sin meses anteriores para comparar.', Semaforo.gris));
    } else {
      final ventas = ultimos3.fold(0.0, (s, m) => s + m.ventas);
      final prom = ultimos3.fold(0.0, (s, m) => s + m.gananciaComercial) / ventas;
      final diff = actual!.margen! - prom;
      out.add(HealthSignal(
        'Margen de la venta',
        _puntos(actual.margen!),
        diff >= -0.01
            ? 'Este mes, contra ${_puntos(prom)} de los meses anteriores: se mantiene.'
            : 'Bajó de ${_puntos(prom)}: revisá precios o costos de compra.',
        diff >= -0.01 ? Semaforo.verde : (diff >= -0.03 ? Semaforo.amarillo : Semaforo.rojo),
      ));
    }
    // 3) Gastos sobre lo que deja la venta.
    if (!hayMedido || gananciaComercial <= 0) {
      out.add(HealthSignal(
        'Gastos del negocio',
        hayMedido ? pesos(gastos) : '–',
        hayMedido ? 'La venta todavía no dejó ganancia para comparar.' : 'Aparece cuando empieces a anotar gastos.',
        hayMedido && gastos > 0 ? Semaforo.rojo : Semaforo.gris,
      ));
    } else {
      final r = gastos / gananciaComercial;
      out.add(HealthSignal(
        'Gastos del negocio',
        porcentaje(r),
        'De cada \$100 que deja la venta, \$${(r * 100).round()} se van en gastos del negocio.',
        r < 0.5 ? Semaforo.verde : (r < 0.8 ? Semaforo.amarillo : Semaforo.rojo),
      ));
    }
    // 4) Retiros (sueldo, casa y personal) contra la ganancia del negocio.
    if (!hayMedido) {
      out.add(const HealthSignal('Retiros', '–', 'Aparece cuando empieces a anotar gastos.', Semaforo.gris));
    } else if (retiros <= 0) {
      out.add(const HealthSignal('Retiros', '\$0', 'No sacaste plata del negocio en este tramo.', Semaforo.verde));
    } else if (ganancia <= 0) {
      out.add(HealthSignal('Retiros', pesos(retiros), 'Sacaste plata sin que el negocio ganara: salió del capital.', Semaforo.rojo));
    } else {
      final r = retiros / ganancia;
      out.add(HealthSignal(
        'Retiros',
        porcentaje(r),
        r <= 1 - reservaSueldo + 0.05
            ? 'Te llevás el ${porcentaje(r)} de la ganancia: queda reserva para el negocio.'
            : r <= 1
            ? 'Te llevás casi toda la ganancia: no queda reserva.'
            : 'Te llevás más de lo que gana el negocio: sale del capital.',
        r <= 1 - reservaSueldo + 0.05 ? Semaforo.verde : (r <= 1 ? Semaforo.amarillo : Semaforo.rojo),
      ));
    }
    // 5) Capital: la foto más vieja contra hoy, sin contar lo que pusiste de tu bolsillo.
    final conInicio = [for (final m in meses) if (m.capitalInicio != null) m];
    final hoy = actual?.capitalFin;
    if (conInicio.isEmpty || hoy == null) {
      out.add(const HealthSignal(
        'Capital',
        '–',
        'Se compara cuando haya una foto del capital de un mes anterior (se guarda sola al abrir el tablero).',
        Semaforo.gris,
      ));
    } else {
      final ref = conInicio.first;
      final aportesDesde = [
        for (final m in meses) if (!m.mes.isBefore(ref.mes) && m.medido != null) m.medido!.aportes,
      ].fold(0.0, (s, v) => s + v);
      final cambio = hoy - ref.capitalInicio! - aportesDesde;
      final rel = ref.capitalInicio! == 0 ? 0 : cambio / ref.capitalInicio!.abs();
      final desde = ref.capitalInicioFecha == null ? '' : ' desde el ${diaMes(ref.capitalInicioFecha!)}';
      out.add(HealthSignal(
        'Capital',
        '${cambio >= 0 ? '+' : ''}${pesos(cambio)}',
        '${cambio >= 0 ? 'Creció' : 'Se achicó'}$desde${aportesDesde > 0 ? ' (sin contar tus aportes)' : ''}.',
        cambio >= 0 ? Semaforo.verde : (rel > -0.03 ? Semaforo.amarillo : Semaforo.rojo),
      ));
    }
    return out;
  }
}

Future<BusinessHealth> fetchBusinessHealth(SupabaseClient client, {int months = 6}) async {
  final result = await client.rpc('fin_salud', params: {'p_meses': months}, get: true);
  return BusinessHealth.fromJson(Map<String, dynamic>.from(result as Map));
}

/// Tarjeta "Salud del negocio".
class HealthCard extends StatelessWidget {
  const HealthCard({super.key, required this.health});
  final BusinessHealth health;

  @override
  Widget build(BuildContext context) {
    final t = Tonos.of(context);
    final h = health;
    final signals = h.senales;
    final verdes = signals.where((s) => s.estado == Semaforo.verde).length;
    final medibles = signals.where((s) => s.estado != Semaforo.gris).length;
    final suggested = h.sueldoSugerido;
    final firstFull = h.primerMesCompleto;
    String aviso;
    if (h.inicio == null) {
      aviso = 'Hacé la foto inicial en "Plata del negocio" y anotá los gastos: con eso se mide la ganancia real.';
    } else if (h.cerrados.isEmpty) {
      aviso = 'Llevás ${h.dias} ${h.dias == 1 ? 'día' : 'días'} anotando gastos: tomalo como referencia. '
          '${firstFull == null ? '' : 'El primer mes completo es ${nombreMes(firstFull)}; '}'
          'con 3 meses completos los números son firmes.';
    } else if (!h.firme) {
      aviso = 'Medido en ${h.periodo}: con ${h.cerrados.length} ${h.cerrados.length == 1 ? 'mes completo' : 'meses completos'} '
          'todavía es provisorio (firme con 3).';
    } else {
      aviso = 'Medido en ${h.periodo} (los últimos 3 meses completos).';
    }
    Color dot(Semaforo s) => switch (s) {
      Semaforo.verde => t.verde,
      Semaforo.amarillo => const Color(0xFFE0A100),
      Semaforo.rojo => t.rojo,
      Semaforo.gris => t.secundario,
    };
    return Card(
      key: const Key('salud-del-negocio'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Salud del negocio', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                ),
                if (medibles > 0)
                  Text('$verdes de $medibles en verde', style: TextStyle(color: t.secundario, fontWeight: FontWeight.w600)),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Text(aviso, style: TextStyle(fontSize: 13, color: t.secundario)),
            ),
            for (final s in signals)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 4, right: 10),
                      child: Icon(Icons.circle, size: 14, color: dot(s.estado)),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(s.titulo, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                              ),
                              Text(s.valor, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: dot(s.estado))),
                            ],
                          ),
                          Text(s.explicacion, style: TextStyle(fontSize: 13, color: t.secundario)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(),
            const Text('Sueldo', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(
              suggested == null
                  ? 'El sueldo sugerido se calcula cuando cierre el primer mes completo con gastos anotados. '
                        'Mientras tanto fijate uno provisorio con lo que necesita la casa, sin pasarte de la ganancia.'
                  : 'Sugerido: ${pesos(suggested)} por semana (la ganancia del negocio menos una reserva del '
                        '${porcentaje(reservaSueldo)} para reponer mercadería e imprevistos).',
              style: TextStyle(fontSize: 13, color: t.secundario),
            ),
            if (h.sueldoSemanal != null && h.gananciaPorMes > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Tu sueldo de ${pesos(h.sueldoSemanal!)} por semana es el '
                  '${porcentaje(h.sueldoSemanal! * semanasPorMes / h.gananciaPorMes)} de la ganancia por mes.',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: h.sueldoSemanal! * semanasPorMes <= h.gananciaPorMes * (1 - reservaSueldo) + 1
                        ? t.verde
                        : t.rojo,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            _MonthsTable(health: h),
          ],
        ),
      ),
    );
  }
}

class _MonthsTable extends StatelessWidget {
  const _MonthsTable({required this.health});
  final BusinessHealth health;

  @override
  Widget build(BuildContext context) {
    final t = Tonos.of(context);
    String short(double v) {
      final a = v.abs();
      final txt = a >= 1000000
          ? '${(a / 1000000).toStringAsFixed(1).replaceAll('.', ',')} M'
          : a >= 1000
          ? '${(a / 1000).round()} mil'
          : a.round().toString();
      return '${v < 0 ? '-' : ''}\$$txt';
    }

    Widget cell(String text, {bool bold = false, Color? color, TextAlign align = TextAlign.right}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        text,
        textAlign: align,
        style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w600 : null, color: color),
      ),
    );
    return ExpansionTile(
      key: const Key('salud-meses'),
      tilePadding: EdgeInsets.zero,
      title: const Text('Mes a mes', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      children: [
        Table(
          columnWidths: const {0: FlexColumnWidth(1.3)},
          children: [
            TableRow(
              children: [
                cell('Mes', bold: true, align: TextAlign.left),
                cell('Ventas', bold: true),
                cell('Margen', bold: true),
                cell('Ganancia', bold: true),
                cell('Retiros', bold: true),
              ],
            ),
            for (final m in health.meses.reversed)
              TableRow(
                children: [
                  cell('${nombreMes(m.mes)}${m.actual ? ' (va)' : ''}', align: TextAlign.left),
                  cell(short(m.ventas)),
                  cell(m.margen == null ? '–' : _puntos(m.margen!)),
                  cell(
                    m.medido == null
                        ? 'sin gastos'
                        : '${short(m.medido!.gananciaNegocio)}${m.completo ? '' : '*'}',
                    color: m.medido == null ? t.secundario : (m.medido!.gananciaNegocio < 0 ? t.rojo : null),
                  ),
                  cell(m.medido == null ? '–' : short(m.medido!.retiros)),
                ],
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'Ganancia = ventas − costo − comisiones − gastos del negocio. "Sin gastos": meses de antes de '
            'empezar a anotar. * Solo desde que se anotan gastos.',
            style: TextStyle(fontSize: 12, color: t.secundario),
          ),
        ),
      ],
    );
  }
}
