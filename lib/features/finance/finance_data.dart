import 'package:supabase_flutter/supabase_flutter.dart';

import '../stock/stock_data.dart';
import 'package:distribuidora_alberdi/core/money_format.dart';

// "Plata del negocio": efectivo y billetera, gastos, plata para el hogar, gastos fijos con sobre,
// proveedores a pagar y arqueo. Ver docs/GESTION-NEGOCIO.md.

const efectivo = 'efectivo';
const billetera = 'billetera';

/// Los sobres de verdad: el frasco (efectivo apartado) y la reserva (apartada dentro de la billetera).
const sobreEfectivo = 'sobre_efectivo';
const sobreBilletera = 'sobre_billetera';

String cuentaNombre(String codigo) => switch (codigo) {
  efectivo => 'Efectivo',
  sobreEfectivo => 'Frasco (efectivo)',
  sobreBilletera => 'Reserva (billetera)',
  _ => 'Billetera virtual',
};

/// El sobre donde va un gasto fijo según cómo se paga.
String sobreDe(String medio) => medio == efectivo ? sobreEfectivo : sobreBilletera;

/// De dónde sale la plata para llenar un sobre.
String libreDe(String sobre) => sobre == sobreEfectivo ? efectivo : billetera;

/// 15000 → "$ 15.000"; 1500.5 → "$ 1.500,50"; −200 → "−$ 200".
String pesos(double value) => formatoPesos(value);

/// "15000", "15.000", "15000,50" o "15.000,50" → número; vacío o inválido → null.
double? parseMoney(String text) => leerImporte(text);

DateTime? _date(Object? value) => value == null ? null : DateTime.tryParse(value.toString());

/// "19/11".
String diaMes(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

/// "19/11 14:05" en hora local.
String diaMesHora(DateTime d) {
  final l = d.toLocal();
  return '${diaMes(l)} ${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

class FinAccount {
  const FinAccount(this.codigo, this.nombre, this.saldo);
  final String codigo;
  final String nombre;
  final double saldo;
}

class FixedExpense {
  const FixedExpense({
    required this.id,
    required this.nombre,
    required this.importe,
    required this.diaPago,
    required this.ambito,
    required this.activo,
    required this.vence,
    required this.vencido,
    required this.reservado,
    required this.porSemana,
    required this.pagadoMes,
    this.medio = billetera,
    this.periodoMes,
  });

  final String id;
  final String nombre;
  final double importe;
  final int diaPago;

  /// negocio, hogar o mixto (la tarjeta).
  final String ambito;
  final bool activo;

  /// Próximo vencimiento sin pagar (es el período que se paga).
  final DateTime vence;
  final bool vencido;

  /// Lo que ya debería estar apartado hoy.
  final double reservado;
  final double porSemana;
  final bool pagadoMes;

  /// efectivo o billetera (transferencia): define a qué sobre va.
  final String medio;

  /// El vencimiento de este mes (para deshacer "ya lo pagué").
  final DateTime? periodoMes;

  /// Gasto de la casa: se paga con el sueldo, no va al sobre.
  bool get conSueldo => ambito == 'hogar';

  static FixedExpense fromJson(Map<String, dynamic> j) => FixedExpense(
    id: j['id'].toString(),
    nombre: j['nombre']?.toString() ?? '',
    importe: stockNum(j['importe']),
    diaPago: stockNum(j['dia_pago']).round(),
    ambito: j['ambito']?.toString() ?? 'negocio',
    activo: j['activo'] != false,
    vence: _date(j['vence']) ?? DateTime.now(),
    vencido: j['vencido'] == true,
    reservado: stockNum(j['reservado']),
    porSemana: stockNum(j['por_semana']),
    pagadoMes: j['pagado_mes'] == true,
    medio: j['medio']?.toString() == efectivo ? efectivo : billetera,
    periodoMes: _date(j['periodo_mes']),
  );
}

/// Un sobre: lo que hay, lo que debería haber hoy y lo que hay que poner el sábado.
class Envelope {
  const Envelope({
    required this.codigo,
    required this.medio,
    required this.nombre,
    required this.saldo,
    required this.deberia,
    required this.faltan,
    required this.ponerSabado,
    this.sabado,
  });

  final String codigo;
  final String medio;
  final String nombre;
  final double saldo;
  final double deberia;
  final double faltan;
  final double ponerSabado;
  final DateTime? sabado;

  static Envelope fromJson(Map<String, dynamic> j) => Envelope(
    codigo: j['codigo']?.toString() ?? sobreBilletera,
    medio: j['medio']?.toString() ?? billetera,
    nombre: j['nombre']?.toString() ?? '',
    saldo: stockNum(j['saldo']),
    deberia: stockNum(j['deberia']),
    faltan: stockNum(j['faltan']),
    ponerSabado: stockNum(j['poner_sabado']),
    sabado: _date(j['sabado']),
  );
}

class Debt {
  const Debt({
    required this.id,
    required this.proveedor,
    required this.importe,
    required this.resta,
    required this.vence,
    required this.vencida,
    this.descripcion,
  });

  final String id;
  final String proveedor;
  final double importe;
  final double resta;
  final DateTime vence;
  final bool vencida;
  final String? descripcion;

  static Debt fromJson(Map<String, dynamic> j) => Debt(
    id: j['id'].toString(),
    proveedor: j['proveedor']?.toString() ?? '',
    importe: stockNum(j['importe']),
    resta: stockNum(j['resta']),
    vence: _date(j['vence']) ?? DateTime.now(),
    vencida: j['vencida'] == true,
    descripcion: j['descripcion']?.toString(),
  );
}

class FinMovement {
  const FinMovement({
    required this.id,
    required this.fecha,
    required this.tipo,
    required this.cuenta,
    required this.importe,
    required this.parteHogar,
    required this.anulable,
    this.categoria,
    this.descripcion,
  });

  final String id;
  final DateTime fecha;
  final String tipo;
  final String cuenta;

  /// Con signo: positivo entra, negativo sale.
  final double importe;
  final double parteHogar;
  final bool anulable;
  final String? categoria;
  final String? descripcion;

  static FinMovement fromJson(Map<String, dynamic> j) => FinMovement(
    id: j['id'].toString(),
    fecha: _date(j['fecha']) ?? DateTime.now(),
    tipo: j['tipo']?.toString() ?? '',
    cuenta: j['cuenta']?.toString() ?? efectivo,
    importe: stockNum(j['importe']),
    parteHogar: stockNum(j['parte_hogar']),
    anulable: j['anulable'] == true,
    categoria: j['categoria']?.toString(),
    descripcion: j['descripcion']?.toString(),
  );

  /// De quién es una salida: negocio, casa, personal o sueldo (null si no es gasto ni retiro).
  String? get deQuien => switch (tipo) {
    'gasto' || 'gasto_fijo' => 'negocio',
    'hogar' => switch (categoria) {
      'Sueldo' => 'sueldo',
      'Personal' => 'personal',
      _ => 'casa',
    },
    _ => null,
  };

  bool get esAporte => tipo == 'ingreso' && categoria == aporteDelDueno;

  /// Se puede pasar de negocio a casa/personal o al revés (el sueldo y los gastos fijos no).
  bool get reclasificable => anulable && (tipo == 'gasto' || (tipo == 'hogar' && categoria != 'Sueldo'));

  /// "Gasto · Combustible", "Cobro · Kiosco Pepe"...
  String get titulo {
    final base = switch (tipo) {
      'saldo_inicial' => 'Foto inicial',
      'gasto' => 'Gasto',
      'gasto_fijo' => 'Gasto fijo',
      'hogar' => switch (categoria) {
        'Sueldo' => 'Mi sueldo',
        'Personal' => 'Personal',
        _ => 'Para la casa',
      },
      'ingreso' when categoria == aporteDelDueno => aporteDelDueno,
      'compra' => 'Compra',
      'pago_proveedor' => 'Pago a proveedor',
      'pase' => 'Pase entre cuentas',
      'ingreso' => 'Ingreso',
      'ajuste' => 'Arqueo',
      'cobro' => 'Cobro',
      'devolucion' => 'Devolución a cliente',
      'comision' => 'Comisiones',
      _ => tipo,
    };
    final detalle = [
      if (categoria != null && categoria!.isNotEmpty && categoria != base && tipo != 'cobro' && tipo != 'hogar')
        categoria!,
      if (descripcion != null && descripcion!.isNotEmpty) descripcion!,
    ];
    return detalle.isEmpty ? base : '$base · ${detalle.join(' · ')}';
  }
}

class FinMonth {
  const FinMonth(this.values);
  final Map<String, double> values;
  double operator [](String key) => values[key] ?? 0;
}

/// Sueldo fijo semanal (se paga los sábados; semana de lunes a sábado).
class SalaryStatus {
  const SalaryStatus({
    this.semanal,
    this.desde,
    this.semana,
    this.pendiente = false,
    this.pagado,
    this.ultimoSemana,
    this.ultimoImporte,
    this.porMes = 0,
  });

  /// null = todavía no se fijó un sueldo.
  final double? semanal;
  final DateTime? desde;

  /// La semana a pagar (su sábado): la pendiente o, si está al día, la próxima.
  final DateTime? semana;

  /// El sábado ya llegó y no se pagó.
  final bool pendiente;

  /// Importe si [semana] ya está pagada (se adelantó).
  final double? pagado;
  final DateTime? ultimoSemana;
  final double? ultimoImporte;
  final double porMes;

  bool get fijado => semanal != null;

  static SalaryStatus? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final j = Map<String, dynamic>.from(raw);
    final pagado = j['pagado'] is Map ? Map<String, dynamic>.from(j['pagado'] as Map) : null;
    final ultimo = j['ultimo'] is Map ? Map<String, dynamic>.from(j['ultimo'] as Map) : null;
    return SalaryStatus(
      semanal: j['semanal'] == null ? null : stockNum(j['semanal']),
      desde: _date(j['desde']),
      semana: _date(j['semana']),
      pendiente: j['pendiente'] == true,
      pagado: pagado == null ? null : stockNum(pagado['importe']),
      ultimoSemana: _date(ultimo?['semana']),
      ultimoImporte: ultimo == null ? null : stockNum(ultimo['importe']),
      porMes: stockNum(j['por_mes']),
    );
  }
}

Future<SalaryStatus?> fetchSalaryStatus(SupabaseClient client) async {
  final result = await client.rpc('fin_sueldo_estado', params: const {}, get: true);
  return SalaryStatus.fromJson(result);
}

/// "sábado 28/11".
String sabado(DateTime d) => 'sábado ${diaMes(d)}';

class FinState {
  const FinState({
    required this.inicio,
    required this.cuentas,
    required this.plata,
    required this.gastosFijos,
    required this.sobre,
    required this.deudas,
    required this.deben,
    required this.disponible,
    required this.mes,
    required this.ultimos,
    this.sueldo,
    this.libre,
    this.sobres = const [],
    this.faltanSobres = 0,
  });

  /// Foto inicial; null = todavía no se hizo.
  final DateTime? inicio;
  final List<FinAccount> cuentas;
  final double plata;
  final List<FixedExpense> gastosFijos;

  /// Lo apartado hoy para los gastos fijos.
  final double sobre;
  final List<Debt> deudas;
  final double deben;

  /// Plata − sobre − proveedores: lo que se puede usar para mercadería.
  final double disponible;
  final FinMonth mes;
  final List<FinMovement> ultimos;
  final SalaryStatus? sueldo;

  /// Efectivo + billetera, sin los sobres (null: el servidor todavía no tiene sobres).
  final double? libre;
  final List<Envelope> sobres;

  /// Lo que falta en los sobres para estar al día hoy (se descuenta del disponible).
  final double faltanSobres;

  bool get started => inicio != null;
  List<FixedExpense> get activos => gastosFijos.where((g) => g.activo && !g.conSueldo).toList();
  List<FixedExpense> get delNegocio => gastosFijos.where((g) => !g.conSueldo).toList();
  List<FixedExpense> get deLaCasa => gastosFijos.where((g) => g.conSueldo).toList();
  double get ponerSabado => sobres.fold(0, (s, e) => s + e.ponerSabado);
  Envelope? sobre(String codigo) => sobres.where((e) => e.codigo == codigo).firstOrNull;
  double get gastosFijosMes => activos.fold(0, (s, g) => s + g.importe);
  double get apartarPorSemana => activos.fold(0, (s, g) => s + g.porSemana);
  double saldo(String cuenta) => cuentas.where((c) => c.codigo == cuenta).map((c) => c.saldo).firstOrNull ?? 0;

  static FinState fromJson(Map<String, dynamic> j) {
    List<Map<String, dynamic>> list(String key) => [
      for (final e in (j[key] as List? ?? const [])) Map<String, dynamic>.from(e as Map),
    ];
    final mes = Map<String, dynamic>.from(j['mes'] as Map? ?? const {});
    return FinState(
      inicio: _date(j['inicio']),
      cuentas: [
        for (final c in list('cuentas'))
          FinAccount(c['codigo'].toString(), c['nombre']?.toString() ?? '', stockNum(c['saldo'])),
      ],
      plata: stockNum(j['plata']),
      gastosFijos: [for (final g in list('gastos_fijos')) FixedExpense.fromJson(g)],
      sobre: stockNum(j['sobre']),
      deudas: [for (final d in list('deudas')) Debt.fromJson(d)],
      deben: stockNum(j['deben']),
      disponible: stockNum(j['disponible']),
      mes: FinMonth({for (final e in mes.entries) e.key: stockNum(e.value)}),
      ultimos: [for (final m in list('ultimos')) FinMovement.fromJson(m)],
      sueldo: SalaryStatus.fromJson(j['sueldo']),
      libre: j['libre'] == null ? null : stockNum(j['libre']),
      sobres: [for (final e in list('sobres')) Envelope.fromJson(e)],
      faltanSobres: stockNum(j['faltan_sobres']),
    );
  }
}

/// Por GET: queda en la copia del teléfono y se ve aunque se corte la señal.
Future<FinState> fetchFinState(SupabaseClient client) async {
  final result = await client.rpc('fin_estado', params: const {}, get: true);
  return FinState.fromJson(Map<String, dynamic>.from(result as Map));
}

Future<List<FinMovement>> fetchFinMovements(SupabaseClient client, DateTime desde, DateTime hasta) async {
  final result = await client.rpc(
    'fin_movimientos_lista',
    params: {'p_desde': desde.toUtc().toIso8601String(), 'p_hasta': hasta.toUtc().toIso8601String()},
    get: true,
  );
  return [for (final m in (result as List? ?? const [])) FinMovement.fromJson(Map<String, dynamic>.from(m as Map))];
}

/// Operación de plata: con id y hora del teléfono; sin señal queda guardada y se envía sola.
/// [client] null = el de la app (no se toca si hay [runner], para las pruebas).
Future<StockOpOutcome> runFinOp(
  SupabaseClient? client, {
  required String rpc,
  required Map<String, dynamic> args,
  required String description,
  double total = 0,
  StockOpRunner? runner,
}) => runner != null
    ? runner(rpc, args)
    : runStockOp(client ?? Supabase.instance.client, rpc: rpc, args: args, description: description, total: total);

const aporteDelDueno = 'Aporte del dueño';

const categoriasGasto = [
  'Combustible',
  'Vehículo',
  'Ayudantes',
  'Bolsas e insumos',
  'Impuestos',
  'Servicios',
  'Teléfono e internet',
  'Otros',
];
