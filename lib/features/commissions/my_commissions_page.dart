import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'commission_order_detail.dart';

class MyCommissionsPage extends StatefulWidget {
  const MyCommissionsPage({super.key});

  @override
  State<MyCommissionsPage> createState() => _MyCommissionsPageState();
}

class _MyCommissionsPageState extends State<MyCommissionsPage> {
    String? get _preventistaId =>
    Supabase.instance.client.auth.currentUser?.id;
  String _periodo = 'hoy';
  DateTime? _fechaDesdePersonalizada;
DateTime? _fechaHastaPersonalizada;
  bool _cargando = false;
List<Map<String, dynamic>> _detalles = [];
double _comisionTotal = 0;

Future<void> _cargarHoy() async {
  final preventistaId = _preventistaId;

  if (preventistaId == null) return;

  setState(() {
    _cargando = true;
  });

  try {
    final ahoraArgentina = DateTime.now()
    .toUtc()
    .subtract(const Duration(hours: 3));

final desde = DateTime.utc(
  ahoraArgentina.year,
  ahoraArgentina.month,
  ahoraArgentina.day,
  3,
);

final hasta = desde.add(
  const Duration(days: 1),
).subtract(
  const Duration(milliseconds: 1),
);

    final respuesta = await Supabase.instance.client
        .from('pedido_detalles')
        .select(
          '''
          id,
          cantidad_entregada,
          precio_unitario,
          porcentaje_comision,
          importe_comision,
          productos (
            nombre
          ),
          pedidos!inner (
            id,
            preventista_id,
            fecha_finalizacion,
            resultado_entrega,
            clientes (
              nombre_comercio
            )
          )
          ''',
        )
        .eq('pedidos.preventista_id', preventistaId)
        .gte(
          'pedidos.fecha_finalizacion',
          desde.toIso8601String(),
        )
        .lte(
          'pedidos.fecha_finalizacion',
          hasta.toIso8601String(),
        );

    final detalles =
        List<Map<String, dynamic>>.from(respuesta);
      

    double total = 0;

    for (final detalle in detalles) {
      total +=
          double.tryParse(
            detalle['importe_comision']?.toString() ?? '0',
          ) ??
          0;
    }

    if (!mounted) return;

    setState(() {
      _detalles = detalles;
      _comisionTotal = total;
      _cargando = false;
    });
  } catch (_) {
    if (!mounted) return;

    setState(() {
      _detalles = [];
      _comisionTotal = 0;
      _cargando = false;
    });
  }
}
Future<void> _cargarSemana() async {
  final preventistaId = _preventistaId;

  if (preventistaId == null) return;

  setState(() {
    _cargando = true;
  });

  try {
    final ahoraArgentina = DateTime.now()
        .toUtc()
        .subtract(const Duration(hours: 3));

    final inicioSemanaArgentina = ahoraArgentina.subtract(
      Duration(days: ahoraArgentina.weekday - 1),
    );

    final desde = DateTime.utc(
      inicioSemanaArgentina.year,
      inicioSemanaArgentina.month,
      inicioSemanaArgentina.day,
      3,
    );

    final hasta = desde
        .add(const Duration(days: 7))
        .subtract(const Duration(milliseconds: 1));

    final respuesta = await Supabase.instance.client
        .from('pedido_detalles')
        .select(
          '''
          id,
          cantidad_entregada,
          precio_unitario,
          porcentaje_comision,
          importe_comision,
          productos (
            nombre
          ),
          pedidos!inner (
            id,
            preventista_id,
            fecha_finalizacion,
            resultado_entrega,
            clientes (
              nombre_comercio
            )
          )
          ''',
        )
        .eq('pedidos.preventista_id', preventistaId)
        .gte(
          'pedidos.fecha_finalizacion',
          desde.toIso8601String(),
        )
        .lte(
          'pedidos.fecha_finalizacion',
          hasta.toIso8601String(),
        );

    final detalles =
        List<Map<String, dynamic>>.from(respuesta);

    double total = 0;

    for (final detalle in detalles) {
      total +=
          double.tryParse(
            detalle['importe_comision']?.toString() ?? '0',
          ) ??
          0;
    }

    if (!mounted) return;

    setState(() {
      _detalles = detalles;
      _comisionTotal = total;
      _cargando = false;
    });
  } catch (_) {
    if (!mounted) return;

    setState(() {
      _detalles = [];
      _comisionTotal = 0;
      _cargando = false;
    });
  }
}
Future<void> _cargarPersonalizado() async {
  final preventistaId = _preventistaId;
  final fechaDesde = _fechaDesdePersonalizada;
  final fechaHasta = _fechaHastaPersonalizada;

  if (preventistaId == null ||
      fechaDesde == null ||
      fechaHasta == null) {
    return;
  }

  setState(() {
    _cargando = true;
  });

  try {
    final desde = DateTime.utc(
      fechaDesde.year,
      fechaDesde.month,
      fechaDesde.day,
      3,
    );

    final hasta = DateTime.utc(
      fechaHasta.year,
      fechaHasta.month,
      fechaHasta.day,
      3,
    )
        .add(const Duration(days: 1))
        .subtract(const Duration(milliseconds: 1));

    final respuesta = await Supabase.instance.client
        .from('pedido_detalles')
        .select(
          '''
          id,
          cantidad_entregada,
          precio_unitario,
          porcentaje_comision,
          importe_comision,
          productos (
            nombre
          ),
          pedidos!inner (
            id,
            preventista_id,
            fecha_finalizacion,
            resultado_entrega,
            clientes (
              nombre_comercio
            )
          )
          ''',
        )
        .eq('pedidos.preventista_id', preventistaId)
        .gte(
          'pedidos.fecha_finalizacion',
          desde.toIso8601String(),
        )
        .lte(
          'pedidos.fecha_finalizacion',
          hasta.toIso8601String(),
        );

    final detalles =
        List<Map<String, dynamic>>.from(respuesta);

    double total = 0;

    for (final detalle in detalles) {
      total +=
          double.tryParse(
            detalle['importe_comision']?.toString() ?? '0',
          ) ??
          0;
    }

    if (!mounted) return;

    setState(() {
      _detalles = detalles;
      _comisionTotal = total;
      _cargando = false;
    });
  } catch (_) {
    if (!mounted) return;

    setState(() {
      _detalles = [];
      _comisionTotal = 0;
      _cargando = false;
    });
  }
}
@override
void initState() {
  super.initState();
  _cargarHoy();
}
Map<String, double> get _comisionesPorCliente {
  final resultado = <String, double>{};

  for (final detalle in _detalles) {
    final pedido = detalle['pedidos'] as Map<String, dynamic>?;

    final cliente =
        pedido?['clientes'] as Map<String, dynamic>?;

    final nombreCliente =
        cliente?['nombre_comercio']?.toString() ?? 'Sin cliente';

    final importe =
        double.tryParse(
          detalle['importe_comision']?.toString() ?? '0',
        ) ??
        0;

    resultado[nombreCliente] =
        (resultado[nombreCliente] ?? 0) + importe;
  }

  return resultado;
}
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis comisiones'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'hoy',
                  label: Text('Hoy'),
                  icon: Icon(Icons.today_outlined),
                ),
                ButtonSegment(
                  value: 'semana',
                  label: Text('Esta semana'),
                  icon: Icon(Icons.date_range_outlined),
                ),
                ButtonSegment(
                  value: 'personalizado',
                  label: Text('Personalizado'),
                  icon: Icon(Icons.calendar_month_outlined),
                ),
              ],
              selected: {_periodo},
              onSelectionChanged: (seleccion) async {
  final nuevoPeriodo = seleccion.first;

  if (nuevoPeriodo == 'personalizado') {
    final ahoraArgentina = DateTime.now()
        .toUtc()
        .subtract(const Duration(hours: 3));

    final rango = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2025),
      lastDate: DateTime(
        ahoraArgentina.year,
        ahoraArgentina.month,
        ahoraArgentina.day,
      ),
      initialDateRange:
          _fechaDesdePersonalizada != null &&
              _fechaHastaPersonalizada != null
          ? DateTimeRange(
              start: _fechaDesdePersonalizada!,
              end: _fechaHastaPersonalizada!,
            )
          : null,
    );

    if (rango == null || !mounted) return;

    setState(() {
      _periodo = 'personalizado';
      _fechaDesdePersonalizada = rango.start;
      _fechaHastaPersonalizada = rango.end;
    });
    _cargarPersonalizado();

    return;
  }

  setState(() {
    _periodo = nuevoPeriodo;
  });

  if (nuevoPeriodo == 'hoy') {
    _cargarHoy();
  } else if (nuevoPeriodo == 'semana') {
    _cargarSemana();
  }
},
            ),
            const SizedBox(height: 24),
             Card(
              child: ListTile(
                title: Text('COMISIÓN GENERADA'),
                trailing: Text(
                  _cargando
    ? '...'
    : '\$${_comisionTotal.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Detalle por cliente',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
  child: _comisionesPorCliente.isEmpty
      ? const Center(
          child: Text(
            'Todavía no hay datos para mostrar.',
          ),
        )
      : ListView(
          children: _comisionesPorCliente.entries.map((entry) {
            return Card(
              child: ListTile(
  leading: const Icon(
    Icons.storefront_outlined,
  ),
  title: Text(entry.key),
  trailing: Text(
    '\$${entry.value.toStringAsFixed(0)}',
    style: const TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.bold,
    ),
  ),
  onTap: () {
    final detallesCliente = _detalles.where((detalle) {
      final pedido =
          detalle['pedidos'] as Map<String, dynamic>?;

      final cliente =
          pedido?['clientes'] as Map<String, dynamic>?;

      final nombreCliente =
          cliente?['nombre_comercio']?.toString() ??
          'Sin cliente';

      return nombreCliente == entry.key;
    }).toList();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: Text(entry.key),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: CommissionOrderDetail(
              detalles: detallesCliente,
            ),
          ),
        ),
      ),
    );
  },
),
            );
          }).toList(),
        ),
),
          ],
        ),
      ),
    );
  }
}