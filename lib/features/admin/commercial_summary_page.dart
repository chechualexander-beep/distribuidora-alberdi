import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CommercialSummaryPage extends StatefulWidget {
  const CommercialSummaryPage({super.key});

  @override
  State<CommercialSummaryPage> createState() =>
      _CommercialSummaryPageState();
}

class _CommercialSummaryPageState extends State<CommercialSummaryPage> {
    
  int _periodoSeleccionado = 0;
  DateTimeRange? _rangoPersonalizado;

final _supabase = Supabase.instance.client;

bool _cargando = false;
String? _error;
double _ventaTotal = 0;
double _mercaderiaEntregada = 0;
double _recaudacion = 0;
double _saldoPendiente = 0;
double _costoMercaderia = 0;
double _comisiones = 0;
double _ganancia = 0;
Map<String, double> _comisionesPorPreventista = {};
Map<String, String> _nombresPreventistas = {};

Future<void> _cargarResumen() async {
  setState(() {
    _cargando = true;
    _error = null;
  });

  try {
    final hoy = DateTime.now();

late DateTime inicio;
late DateTime fin;

if (_periodoSeleccionado == 1) {
  // SEMANA
  final inicioHoy = DateTime(
    hoy.year,
    hoy.month,
    hoy.day,
  );

  inicio = inicioHoy.subtract(
    Duration(days: hoy.weekday - DateTime.monday),
  );

  fin = inicio.add(const Duration(days: 7));
} else if (_periodoSeleccionado == 2 &&
    _rangoPersonalizado != null) {
  // PERSONALIZADO
  inicio = DateTime(
    _rangoPersonalizado!.start.year,
    _rangoPersonalizado!.start.month,
    _rangoPersonalizado!.start.day,
  );

  final ultimoDia = DateTime(
    _rangoPersonalizado!.end.year,
    _rangoPersonalizado!.end.month,
    _rangoPersonalizado!.end.day,
  );

  fin = ultimoDia.add(const Duration(days: 1));
} else {
  // HOY
  inicio = DateTime(
    hoy.year,
    hoy.month,
    hoy.day,
  );

  fin = inicio.add(const Duration(days: 1));
}

    final pedidos = await _supabase
    .from('pedidos')
    .select('''
      id,
      fecha_facturacion,
      facturado,
      tipo_operacion,
      pedido_detalles (
        cantidad_facturada,
        precio_unitario
      )
    ''')
    .eq('facturado', true)
    .gte('fecha_facturacion', inicio.toIso8601String())
    .lt('fecha_facturacion', fin.toIso8601String());

    double venta = 0;

    for (final pedido in pedidos) {
      final detalles = pedido['pedido_detalles'] as List<dynamic>? ?? [];

      for (final detalle in detalles) {
  final cantidadFacturada = double.tryParse(
        detalle['cantidad_facturada']?.toString() ?? '',
      ) ??
      0;

  final precioUnitario = double.tryParse(
        detalle['precio_unitario']?.toString() ?? '',
      ) ??
      0;

  venta += cantidadFacturada * precioUnitario;
}
    }
    final pedidosEntregados = await _supabase
    .from('pedidos')
    .select('''
      id,
      preventista_id,
      fecha_entrega,
      resultado_entrega,
      pedido_detalles (
  cantidad_entregada,
  precio_unitario,
  costo_unitario,
  importe_comision
)
    ''')
    .gte(
      'fecha_entrega',
      inicio.toIso8601String().split('T').first,
    )
    .lt(
      'fecha_entrega',
      fin.toIso8601String().split('T').first,
    );

double mercaderiaEntregada = 0;
double costoMercaderia = 0;
double comisiones = 0;
final Map<String, double> comisionesPorPreventista = {};

for (final pedido in pedidosEntregados) {
  final detalles = pedido['pedido_detalles'] as List<dynamic>? ?? [];
  final preventistaId = pedido['preventista_id']?.toString();

  for (final detalle in detalles) {
    final cantidadEntregada = double.tryParse(
          detalle['cantidad_entregada']?.toString() ?? '',
        ) ??
        0;

    final precioUnitario = double.tryParse(
          detalle['precio_unitario']?.toString() ?? '',
        ) ??
        0;
    final costoUnitario = double.tryParse(
      detalle['costo_unitario']?.toString() ?? '',
    ) ??
    0;
    final importeComision = double.tryParse(
      detalle['importe_comision']?.toString() ?? '',
    ) ??
    0;

    mercaderiaEntregada += cantidadEntregada * precioUnitario;
costoMercaderia += cantidadEntregada * costoUnitario;
comisiones += importeComision;
if (preventistaId != null) {
  comisionesPorPreventista[preventistaId] =
      (comisionesPorPreventista[preventistaId] ?? 0) + importeComision;
}
  }
}
double saldoPendiente = 0;

for (final pedido in pedidosEntregados) {
  final pedidoId = pedido['id']?.toString();

  if (pedidoId == null) continue;

  final detalles = pedido['pedido_detalles'] as List<dynamic>? ?? [];

  double totalEntregadoPedido = 0;

  for (final detalle in detalles) {
    final cantidadEntregada = double.tryParse(
          detalle['cantidad_entregada']?.toString() ?? '',
        ) ??
        0;

    final precioUnitario = double.tryParse(
          detalle['precio_unitario']?.toString() ?? '',
        ) ??
        0;

    totalEntregadoPedido += cantidadEntregada * precioUnitario;
  }

  final pagosPedido = await _supabase
      .from('pedido_pagos')
      .select('importe')
      .eq('pedido_id', pedidoId);

  double totalPagadoPedido = 0;

  for (final pago in pagosPedido) {
    totalPagadoPedido +=
        double.tryParse(pago['importe']?.toString() ?? '') ?? 0;
  }

  final pendientePedido = totalEntregadoPedido - totalPagadoPedido;

  if (pendientePedido > 0) {
    saldoPendiente += pendientePedido;
  }
}

final pagos = await _supabase
    .from('pedido_pagos')
    .select('pedido_id, importe, fecha_pago')
    .gte('fecha_pago', inicio.toIso8601String())
    .lt('fecha_pago', fin.toIso8601String());

double recaudacion = 0;

for (final pago in pagos) {
  final importe = double.tryParse(
        pago['importe']?.toString() ?? '',
      ) ??
      0;

  recaudacion += importe;
}
final ganancia =
    mercaderiaEntregada - costoMercaderia - comisiones;
    final usuariosRespuesta = await _supabase
    .from('usuarios')
    .select('id, nombre, apellido')
    .eq('activo', true);

final Map<String, String> nombresPreventistas = {};

for (final usuario in usuariosRespuesta) {
  final id = usuario['id']?.toString();
  if (id == null) continue;

  final nombre = usuario['nombre']?.toString().trim() ?? '';
  final apellido = usuario['apellido']?.toString().trim() ?? '';

  final nombreCompleto = '$nombre $apellido'.trim();

  nombresPreventistas[id] =
      nombreCompleto.isEmpty ? 'Preventista' : nombreCompleto;
}

    if (!mounted) return;

    setState(() {
      _ventaTotal = venta;
      _mercaderiaEntregada = mercaderiaEntregada;
      _recaudacion = recaudacion;
      _saldoPendiente = saldoPendiente;
      _costoMercaderia = costoMercaderia;
      _comisiones = comisiones;
      _comisionesPorPreventista = Map<String, double>.from(
  comisionesPorPreventista,
);
_nombresPreventistas = Map<String, String>.from(
  nombresPreventistas,
);
      _ganancia = ganancia;
      _cargando = false;
    });
  } catch (e) {
    if (!mounted) return;

    setState(() {
      _error = 'No se pudo cargar el resumen comercial.';
      _cargando = false;
    });
  }
}

@override
void initState() {
  super.initState();
  _cargarResumen();
}

  @override
  Widget build(BuildContext context) {
    final esMovil = MediaQuery.of(context).size.width < 600;
    return Container(
  color: Theme.of(context).scaffoldBackgroundColor,
  padding: EdgeInsets.all(esMovil ? 12 : 24),
  child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
  'Resumen comercial',
  style: TextStyle(
    fontSize: esMovil ? 22 : 26,
    fontWeight: FontWeight.bold,
  ),
),
const SizedBox(height: 4),
Text(
  'Ventas, recaudaciones, comisiones y rentabilidad',
  style: TextStyle(
    fontSize: esMovil ? 14 : null,
    color: Theme.of(context).colorScheme.onSurfaceVariant,
  ),
),
          const SizedBox(height: 24),

          SegmentedButton<int>(
  segments: [
    ButtonSegment<int>(
      value: 0,
      icon: esMovil ? null : const Icon(Icons.today_outlined),
      label: const Text('Hoy'),
    ),
    ButtonSegment<int>(
      value: 1,
      icon: esMovil ? null : const Icon(Icons.date_range_outlined),
      label: const Text('Semana'),
    ),
    ButtonSegment<int>(
      value: 2,
      icon: esMovil ? null : const Icon(Icons.calendar_month_outlined),
      label: const Text('Personalizado'),
    ),
  ],
            selected: {_periodoSeleccionado},
            onSelectionChanged: (seleccion) async {
  final nuevoPeriodo = seleccion.first;

  if (nuevoPeriodo == 2) {
    final rango = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _rangoPersonalizado,
    );

    if (rango == null) {
      return;
    }

    if (!mounted) return;

    setState(() {
      _periodoSeleccionado = 2;
      _rangoPersonalizado = rango;
    });
    _cargarResumen();

    return;
  }

  setState(() {
    _periodoSeleccionado = nuevoPeriodo;
  });

  _cargarResumen();
},
          ),

          const SizedBox(height: 32),

          Expanded(
  child: Center(
    child: _cargando
        ? const CircularProgressIndicator()
        : _error != null
            ? Text(_error!)
            : SingleChildScrollView(
    child: Wrap(
  spacing: 16,
  runSpacing: 16,
  alignment: WrapAlignment.center,
  children: [
    SizedBox(
      width: 280,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.receipt_long_outlined, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'VENTA TOTAL',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                '\$${_ventaTotal.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
  _periodoSeleccionado == 0
      ? 'Facturado hoy'
      : _periodoSeleccionado == 1
          ? 'Facturado en la semana'
          : 'Facturado en el período',
),
            ],
          ),
        ),
      ),
    ),
    SizedBox(
      width: 280,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
  children: [
    Icon(Icons.inventory_2_outlined, size: 20),
    SizedBox(width: 8),
    Expanded(
      child: Text(
        'MERCADERÍA ENTREGADA',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
    ),
  ],
),
              const SizedBox(height: 16),
              Text(
                '\$${_mercaderiaEntregada.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
  _periodoSeleccionado == 0
      ? 'Valor entregado hoy'
      : _periodoSeleccionado == 1
          ? 'Valor entregado en la semana'
          : 'Valor entregado en el período',
),
            ],
          ),
        ),
      ),
    ),
    SizedBox(
      width: 280,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.payments_outlined, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'RECAUDACIÓN',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                '\$${_recaudacion.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
  _periodoSeleccionado == 0
      ? 'Cobrado hoy'
      : _periodoSeleccionado == 1
          ? 'Cobrado en la semana'
          : 'Cobrado en el período',
),
            ],
          ),
        ),
      ),
    ),
    SizedBox(
  width: 280,
  child: Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.account_balance_wallet_outlined, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'SALDOS PENDIENTES',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '\$${_saldoPendiente.toStringAsFixed(0)}',
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
  _periodoSeleccionado == 0
      ? 'Pendiente de cobro hoy'
      : _periodoSeleccionado == 1
          ? 'Pendiente de cobro en la semana'
          : 'Pendiente de cobro en el período',
),
        ],
      ),
    ),
  ),
),
SizedBox(
  width: 280,
  child: Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.inventory_2_outlined, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'COSTO DE MERCADERÍA',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '\$${_costoMercaderia.toStringAsFixed(0)}',
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _periodoSeleccionado == 0
                ? 'Costo de lo entregado hoy'
                : _periodoSeleccionado == 1
                    ? 'Costo de lo entregado en la semana'
                    : 'Costo de lo entregado en el período',
          ),
        ],
      ),
    ),
  ),
),
SizedBox(
  width: 280,
  child: Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.payments_outlined, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'COMISIONES',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '\$${_comisiones.toStringAsFixed(0)}',
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _periodoSeleccionado == 0
                ? 'Comisiones de lo entregado hoy'
                : _periodoSeleccionado == 1
                    ? 'Comisiones de lo entregado en la semana'
                    : 'Comisiones de lo entregado en el período',
          ),
          const SizedBox(height: 16),
const Divider(),
const SizedBox(height: 8),
const Text(
  'POR PREVENTISTA',
  style: TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.bold,
  ),
),
const SizedBox(height: 8),

if (_comisionesPorPreventista.isEmpty)
  const Text('Sin comisiones en este período')
else
  ..._comisionesPorPreventista.entries.map((entry) {
    final nombre =
        _nombresPreventistas[entry.key] ?? 'Preventista';

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              nombre,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '\$${entry.value.toStringAsFixed(0)}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }),
        ],
      ),
    ),
  ),
),
SizedBox(
  width: 280,
  child: Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.trending_up_outlined, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'GANANCIA',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '\$${_ganancia.toStringAsFixed(0)}',
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _periodoSeleccionado == 0
                ? 'Ganancia de lo entregado hoy'
                : _periodoSeleccionado == 1
                    ? 'Ganancia de lo entregado en la semana'
                    : 'Ganancia de lo entregado en el período',
          ),
        ],
      ),
    ),
  ),
),
  ],
),
),
  ),
),
          
        ],
      ),
    );
  }
}