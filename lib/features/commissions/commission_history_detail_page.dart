import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
class CommissionHistoryDetailPage extends StatefulWidget {
  final Map<String, dynamic> liquidacion;

  const CommissionHistoryDetailPage({
    super.key,
    required this.liquidacion,
  });

  @override
  State<CommissionHistoryDetailPage> createState() =>
      _CommissionHistoryDetailPageState();
}

class _CommissionHistoryDetailPageState
    extends State<CommissionHistoryDetailPage> {
  Map<String, dynamic> get liquidacion => widget.liquidacion;
bool _cargandoDetalles = true;
String? _errorDetalles;

List<Map<String, dynamic>> _detalles = [];

@override
void initState() {
  super.initState();
  _cargarDetalles();
}

Future<void> _cargarDetalles() async {
  try {
    final liquidacionId =
        liquidacion['id']?.toString();

    if (liquidacionId == null ||
        liquidacionId.isEmpty) {
      throw Exception('Liquidación sin ID');
    }

    final respuesta =
        await Supabase.instance.client
            .from('liquidacion_detalles')
            .select(
              '''
              id,
              importe_comision,
              pedido_detalles (
                id,
                cantidad,
                cantidad_entregada,
                cantidad_no_entregada,
                precio_unitario,
                porcentaje_comision,
                importe_comision,
                productos (
                  nombre,
                  codigo_original
                ),
                pedidos (
                  id,
                  created_at,
                  clientes (
                    nombre_comercio
                  )
                )
              )
              ''',
            )
            .eq('liquidacion_id', liquidacionId);

    if (!mounted) return;

    setState(() {
      _detalles =
          List<Map<String, dynamic>>.from(
        respuesta,
      );
      _cargandoDetalles = false;
    });
  } catch (_) {
    if (!mounted) return;

    setState(() {
      _errorDetalles =
          'No se pudo cargar el detalle de la liquidación.';
      _cargandoDetalles = false;
    });
  }
}
  double _numero(dynamic valor) {
    return double.tryParse(
          valor?.toString() ?? '0',
        ) ??
        0;
  }

  String _formatearPrecio(double valor) {
    final entero = valor.round().toString();

    final buffer = StringBuffer();
    int contador = 0;

    for (int i = entero.length - 1; i >= 0; i--) {
      buffer.write(entero[i]);
      contador++;

      if (contador == 3 && i != 0) {
        buffer.write('.');
        contador = 0;
      }
    }

    return '\$${buffer.toString().split('').reversed.join()}';
  }

  String _formatearFecha(dynamic valor) {
    if (valor == null) return '';

    final fecha = DateTime.tryParse(valor.toString());

    if (fecha == null) {
      return valor.toString();
    }

    final local = fecha.toLocal();

    final dia = local.day.toString().padLeft(2, '0');
    final mes = local.month.toString().padLeft(2, '0');

    return '$dia/$mes/${local.year}';
  }

  String _nombrePreventista() {
    final usuario =
        liquidacion['usuarios'] as Map<String, dynamic>?;

    final nombre =
        usuario?['nombre']?.toString() ?? '';

    final apellido =
        usuario?['apellido']?.toString() ?? '';

    final completo = [
      nombre,
      apellido,
    ].where((e) => e.isNotEmpty).join(' ');

    return completo.isEmpty ? 'Preventista' : completo;
  }

  @override
  Widget build(BuildContext context) {
    final preventista = _nombrePreventista();

    final fechaDesde =
        _formatearFecha(liquidacion['fecha_desde']);

    final fechaHasta =
        _formatearFecha(liquidacion['fecha_hasta']);

    final ventaEntregada =
        _numero(liquidacion['venta_entregada']);

    final comisionTotal =
        _numero(liquidacion['comision_total']);

    final estado =
        liquidacion['estado']
                ?.toString()
                .toUpperCase() ??
            'PENDIENTE';

    final fechaPago =
        _formatearFecha(liquidacion['fecha_pago']);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Detalle de liquidación',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    preventista,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Período: $fechaDesde al $fechaHasta',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Venta entregada: ${_formatearPrecio(ventaEntregada)}',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Estado: $estado',
                  ),
                  if (fechaPago.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Fecha de pago: $fechaPago',
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment:
                    MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'TOTAL PAGADO',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    _formatearPrecio(comisionTotal),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Detalle de ventas',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
         if (_cargandoDetalles)
  const Padding(
    padding: EdgeInsets.symmetric(vertical: 24),
    child: Center(
      child: CircularProgressIndicator(),
    ),
  )
else if (_errorDetalles != null)
  Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Text(
      _errorDetalles!,
      style: const TextStyle(
        color: Colors.red,
      ),
    ),
  )
else if (_detalles.isEmpty)
  const Padding(
    padding: EdgeInsets.symmetric(vertical: 16),
    child: Text(
      'No hay detalles registrados para esta liquidación.',
    ),
  )
else
  ..._detalles.map((registro) {
    final detalle =
        registro['pedido_detalles']
            as Map<String, dynamic>?;

    final producto =
        detalle?['productos']
            as Map<String, dynamic>?;

    final pedido =
        detalle?['pedidos']
            as Map<String, dynamic>?;

    final cliente =
        pedido?['clientes']
            as Map<String, dynamic>?;

    final nombreProducto =
        producto?['nombre']?.toString() ??
        'Producto';

    final nombreCliente =
        cliente?['nombre_comercio']?.toString() ??
        'Cliente';

    final cantidadEntregada =
        _numero(detalle?['cantidad_entregada']);

    final precioUnitario =
        _numero(detalle?['precio_unitario']);

    final porcentaje =
        _numero(detalle?['porcentaje_comision']);

    final comision =
        _numero(registro['importe_comision']);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                nombreCliente,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(nombreProducto),
              const SizedBox(height: 4),
              Text(
                'Entregado: ${cantidadEntregada.toStringAsFixed(0)} × ${_formatearPrecio(precioUnitario)}',
              ),
              const SizedBox(height: 4),
              Text(
                'Comisión: ${porcentaje.toStringAsFixed(0)}%',
              ),
              const SizedBox(height: 4),
              Text(
                'Generada: ${_formatearPrecio(comision)}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }),
  ],
      ),
    );
  }
}