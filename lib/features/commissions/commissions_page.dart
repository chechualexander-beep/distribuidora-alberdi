import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'commission_order_detail.dart';
class CommissionsPage extends StatefulWidget {
  const CommissionsPage({super.key});

  @override
  State<CommissionsPage> createState() => _CommissionsPageState();
}

class _CommissionsPageState extends State<CommissionsPage> {
  bool _cargando = true;
  String? _error;

  List<Map<String, dynamic>> _usuarios = [];
  String? _preventistaId;

  DateTime _desde = DateTime.now().subtract(
    const Duration(days: 30),
  );

  DateTime _hasta = DateTime.now();

  List<Map<String, dynamic>> _detalles = [];

  @override
  void initState() {
    super.initState();
    _cargarPreventistas();
  }

  Future<void> _cargarPreventistas() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final respuesta = await Supabase.instance.client
          .from('usuarios')
          .select('id, nombre, apellido, rol, activo')
          .eq('activo', true)
          .order('nombre');

      if (!mounted) return;

      final usuarios =
          List<Map<String, dynamic>>.from(respuesta);

      setState(() {
        _usuarios = usuarios;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _error = 'No se pudieron cargar los usuarios.';
        _cargando = false;
      });
    }
  }

  Future<void> _buscarComisiones() async {
    if (_preventistaId == null) {
      _mostrarMensaje('Seleccioná un preventista.');
      return;
    }

    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final desde = DateTime(
        _desde.year,
        _desde.month,
        _desde.day,
      );

      final hasta = DateTime(
        _hasta.year,
        _hasta.month,
        _hasta.day,
        23,
        59,
        59,
      );

      final respuesta = await Supabase.instance.client
          .from('pedido_detalles')
          .select(
            '''
            id,
            cantidad,
            cantidad_entregada,
            cantidad_no_entregada,
            precio_unitario,
            porcentaje_comision,
            importe_comision,
            tipo_precio,
            productos (
              nombre,
              codigo_original
            ),
            pedidos!inner (
              id,
              created_at,
              preventista_id,
              resultado_entrega,
              clientes (
                nombre_comercio
              )
            )
            ''',
          )
          .eq('pedidos.preventista_id', _preventistaId!)
          .gte(
            'pedidos.created_at',
            desde.toIso8601String(),
          )
          .lte(
            'pedidos.created_at',
            hasta.toIso8601String(),
          )
          .order(
            'created_at',
            referencedTable: 'pedidos',
            ascending: false,
          );

      if (!mounted) return;

      setState(() {
        _detalles = List<Map<String, dynamic>>.from(
          respuesta,
        );
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _error = 'No se pudieron cargar las comisiones.';
        _cargando = false;
      });
    }
  }

  double _numero(dynamic valor) {
    return double.tryParse(
          valor?.toString() ?? '0',
        ) ??
        0;
  }

  double get _ventaPedida {
    double total = 0;

    for (final detalle in _detalles) {
      total +=
          _numero(detalle['cantidad']) *
          _numero(detalle['precio_unitario']);
    }

    return total;
  }

  double get _ventaEntregada {
    double total = 0;

    for (final detalle in _detalles) {
      total +=
          _numero(detalle['cantidad_entregada']) *
          _numero(detalle['precio_unitario']);
    }

    return total;
  }

  double get _ventaNoEntregada {
    double total = 0;

    for (final detalle in _detalles) {
      total +=
          _numero(detalle['cantidad_no_entregada']) *
          _numero(detalle['precio_unitario']);
    }

    return total;
  }

  double get _comisionTotal {
    double total = 0;

    for (final detalle in _detalles) {
      total += _numero(
        detalle['importe_comision'],
      );
    }

    return total;
  }
  Map<String, List<Map<String, dynamic>>> get _detallesPorPedido {
  final grupos = <String, List<Map<String, dynamic>>>{};

  for (final detalle in _detalles) {
    final pedido =
        detalle['pedidos'] as Map<String, dynamic>?;

    final pedidoId =
        pedido?['id']?.toString() ?? 'sin-pedido';

    grupos.putIfAbsent(
      pedidoId,
      () => <Map<String, dynamic>>[],
    );

    grupos[pedidoId]!.add(detalle);
  }

  return grupos;
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

  String _formatearFecha(DateTime fecha) {
    final dia = fecha.day.toString().padLeft(2, '0');
    final mes = fecha.month.toString().padLeft(2, '0');
    final anio = fecha.year.toString();

    return '$dia/$mes/$anio';
  }

  Future<void> _seleccionarDesde() async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: _desde,
      firstDate: DateTime(2024),
      lastDate: DateTime(2100),
    );

    if (fecha == null) return;

    setState(() {
      _desde = fecha;

      if (_hasta.isBefore(_desde)) {
        _hasta = _desde;
      }
    });
  }

  Future<void> _seleccionarHasta() async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: _hasta,
      firstDate: _desde,
      lastDate: DateTime(2100),
    );

    if (fecha == null) return;

    setState(() {
      _hasta = fecha;
    });
  }

  void _mostrarMensaje(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Liquidación de comisiones'),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Liquidación de comisiones'),
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 60,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _cargarPreventistas,
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DropdownButtonFormField<String>(
                  value: _preventistaId,
                  decoration: const InputDecoration(
                    labelText: 'Preventista',
                    border: OutlineInputBorder(),
                  ),
                  items: _usuarios.map((usuario) {
                    final nombre =
                        usuario['nombre']?.toString() ?? '';

                    final apellido =
                        usuario['apellido']?.toString() ?? '';

                    final nombreCompleto = [
                      nombre,
                      apellido,
                    ].where((e) => e.isNotEmpty).join(' ');

                    return DropdownMenuItem<String>(
                      value: usuario['id'].toString(),
                      child: Text(
                        nombreCompleto.isEmpty
                            ? 'Usuario'
                            : nombreCompleto,
                      ),
                    );
                  }).toList(),
                  onChanged: (valor) {
                    setState(() {
                      _preventistaId = valor;
                      _detalles = [];
                    });
                  },
                ),

                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _seleccionarDesde,
                        icon: const Icon(
                          Icons.calendar_month_outlined,
                        ),
                        label: Text(
                          'Desde ${_formatearFecha(_desde)}',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _seleccionarHasta,
                        icon: const Icon(
                          Icons.calendar_month_outlined,
                        ),
                        label: Text(
                          'Hasta ${_formatearFecha(_hasta)}',
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                FilledButton.icon(
                  onPressed: _buscarComisiones,
                  icon: const Icon(Icons.search),
                  label: const Text('CALCULAR COMISIONES'),
                ),

                const SizedBox(height: 24),

                if (_detalles.isNotEmpty) ...[
                  const Text(
                    'Resumen',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 12),

                  _TarjetaResumen(
                    titulo: 'Venta pedida',
                    valor: _formatearPrecio(_ventaPedida),
                  ),
                  _TarjetaResumen(
                    titulo: 'Venta entregada',
                    valor: _formatearPrecio(_ventaEntregada),
                  ),
                  _TarjetaResumen(
                    titulo: 'No entregado',
                    valor: _formatearPrecio(_ventaNoEntregada),
                  ),
                  _TarjetaResumen(
                    titulo: 'COMISIÓN TOTAL',
                    valor: _formatearPrecio(_comisionTotal),
                    destacado: true,
                  ),

                  const SizedBox(height: 24),

                  const Text(
                    'Detalle',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 10),

        ..._detallesPorPedido.entries.map((entrada) {
  final detallesPedido = entrada.value;

  if (detallesPedido.isEmpty) {
    return const SizedBox.shrink();
  }

  final primerDetalle = detallesPedido.first;

  final pedido =
      primerDetalle['pedidos'] as Map<String, dynamic>?;

  final cliente =
      pedido?['clientes'] as Map<String, dynamic>?;

  final clienteNombre =
      cliente?['nombre_comercio']?.toString() ??
          'Cliente';

  final pedidoId =
      pedido?['id']?.toString() ?? '';

  final numeroPedido = pedidoId.length >= 8
      ? pedidoId.substring(0, 8).toUpperCase()
      : pedidoId.toUpperCase();

  double ventaPedidaPedido = 0;
  double ventaEntregadaPedido = 0;
  double ventaNoEntregadaPedido = 0;
  double comisionPedido = 0;

  for (final detalle in detallesPedido) {
    final cantidad =
        _numero(detalle['cantidad']);

    final entregada =
        _numero(detalle['cantidad_entregada']);

    final noEntregada =
        _numero(detalle['cantidad_no_entregada']);

    final precio =
        _numero(detalle['precio_unitario']);

    ventaPedidaPedido += cantidad * precio;
    ventaEntregadaPedido += entregada * precio;
    ventaNoEntregadaPedido += noEntregada * precio;

    comisionPedido +=
        _numero(detalle['importe_comision']);
  }

  return Card(
    margin: const EdgeInsets.only(bottom: 14),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            clienteNombre,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Pedido #$numeroPedido',
            style: const TextStyle(
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Pedido: ${_formatearPrecio(ventaPedidaPedido)}',
          ),
          const SizedBox(height: 4),
          Text(
            'Entregado: ${_formatearPrecio(ventaEntregadaPedido)}',
          ),
          const SizedBox(height: 4),
          Text(
            'No entregado: ${_formatearPrecio(ventaNoEntregadaPedido)}',
          ),
          const SizedBox(height: 4),
          Text(
            'Comisión: ${_formatearPrecio(comisionPedido)}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          const Divider(height: 24),
CommissionOrderDetail(
  detalles: detallesPedido,
),
          if (false)
  ...detallesPedido.map((detalle) {
            final producto =
                detalle['productos']
                    as Map<String, dynamic>?;

            final nombreProducto =
                producto?['nombre']?.toString() ??
                    'Producto';

            final entregada =
                _numero(detalle['cantidad_entregada']);

            final precio =
                _numero(detalle['precio_unitario']);

            final porcentaje =
                _numero(detalle['porcentaje_comision']);

            final comision =
                _numero(detalle['importe_comision']);

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    nombreProducto,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Entregado: ${entregada.toStringAsFixed(0)} × ${_formatearPrecio(precio)}',
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Comisión: ${porcentaje.toStringAsFixed(0)}%',
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Generada: ${_formatearPrecio(comision)}',
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
  );
}),
                ] else ...[
                  const SizedBox(height: 50),
                  const Center(
                    child: Text(
                      'Seleccioná un preventista y un período.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _TarjetaResumen extends StatelessWidget {
  final String titulo;
  final String valor;
  final bool destacado;

  const _TarjetaResumen({
    required this.titulo,
    required this.valor,
    this.destacado = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(
          titulo,
          style: TextStyle(
            fontWeight:
                destacado ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        trailing: Text(
          valor,
          style: TextStyle(
            fontSize: destacado ? 20 : 17,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}