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

final _supabase = Supabase.instance.client;

bool _cargando = false;
String? _error;
double _ventaTotal = 0;
double _mercaderiaEntregada = 0;
double _recaudacion = 0;
double _saldoPendiente = 0;

Future<void> _cargarResumen() async {
  setState(() {
    _cargando = true;
    _error = null;
  });

  try {
    final hoy = DateTime.now();

    final inicio = DateTime(
      hoy.year,
      hoy.month,
      hoy.day,
    );

    final fin = inicio.add(const Duration(days: 1));

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
      fecha_entrega,
      resultado_entrega,
      pedido_detalles (
        cantidad_entregada,
        precio_unitario
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

for (final pedido in pedidosEntregados) {
  final detalles = pedido['pedido_detalles'] as List<dynamic>? ?? [];

  for (final detalle in detalles) {
    final cantidadEntregada = double.tryParse(
          detalle['cantidad_entregada']?.toString() ?? '',
        ) ??
        0;

    final precioUnitario = double.tryParse(
          detalle['precio_unitario']?.toString() ?? '',
        ) ??
        0;

    mercaderiaEntregada += cantidadEntregada * precioUnitario;
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
    if (!mounted) return;

    setState(() {
      _ventaTotal = venta;
      _mercaderiaEntregada = mercaderiaEntregada;
      _recaudacion = recaudacion;
      _saldoPendiente = saldoPendiente;
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
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Resumen comercial',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Ventas, recaudaciones, comisiones y rentabilidad',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),

          SegmentedButton<int>(
            segments: const [
              ButtonSegment<int>(
                value: 0,
                icon: Icon(Icons.today_outlined),
                label: Text('Hoy'),
              ),
              ButtonSegment<int>(
                value: 1,
                icon: Icon(Icons.date_range_outlined),
                label: Text('Semana'),
              ),
              ButtonSegment<int>(
                value: 2,
                icon: Icon(Icons.calendar_month_outlined),
                label: Text('Personalizado'),
              ),
            ],
            selected: {_periodoSeleccionado},
            onSelectionChanged: (seleccion) {
              setState(() {
                _periodoSeleccionado = seleccion.first;
              });
            },
          ),

          const SizedBox(height: 32),

          Expanded(
  child: Center(
    child: _cargando
        ? const CircularProgressIndicator()
        : _error != null
            ? Text(_error!)
            : Wrap(
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
              const Text('Facturado en la jornada'),
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
              const Text('Valor entregado en la jornada'),
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
              const Text('Cobrado efectivamente'),
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
          const Text('Pendiente de cobro'),
        ],
      ),
    ),
  ),
),
  ],
),
  ),
),
        ],
      ),
    );
  }
}