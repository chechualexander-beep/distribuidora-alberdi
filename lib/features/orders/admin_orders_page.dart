import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'manage_order_page.dart';

class AdminOrdersPage extends StatefulWidget {
  const AdminOrdersPage({super.key});

  @override
  State<AdminOrdersPage> createState() => _AdminOrdersPageState();
}

class _AdminOrdersPageState extends State<AdminOrdersPage> {
  bool _cargando = true;
  String? _error;

  List<Map<String, dynamic>> _pedidos = [];
  List<Map<String, dynamic>> _resumenProductos = [];

  @override
  void initState() {
    super.initState();
    _cargarPedidos();
  }

  Future<void> _cargarPedidos() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final respuesta = await Supabase.instance.client
          .from('pedidos')
          .select(
            '''
            id,
            created_at,
            estado,
            resultado_entrega,
            motivo_no_entrega,
            total,
            clientes (
              nombre_comercio,
              direccion
            ),
            usuarios (
              nombre,
              apellido
            )
            ''',
          )
          .order('created_at', ascending: false);

final pedidosCargados =
    List<Map<String, dynamic>>.from(respuesta);

final idsPedidos = pedidosCargados
    .map((pedido) => pedido['id'])
    .where((id) => id != null)
    .toList();

final Map<String, Map<String, dynamic>> productosAgrupados = {};

if (idsPedidos.isNotEmpty) {
  final detallesRespuesta = await Supabase.instance.client
      .from('pedido_detalles')
      .select(
        '''
        producto_id,
        cantidad,
        productos (
          nombre,
          codigo
        )
        ''',
      )
      .inFilter('pedido_id', idsPedidos);

  for (final detalle in detallesRespuesta) {
    final productoId = detalle['producto_id']?.toString();

    if (productoId == null) continue;

    final producto =
        detalle['productos'] as Map<String, dynamic>?;

    final cantidad =
        double.tryParse(detalle['cantidad']?.toString() ?? '') ?? 0;

    if (!productosAgrupados.containsKey(productoId)) {
      productosAgrupados[productoId] = {
        'producto_id': productoId,
        'nombre':
            producto?['nombre']?.toString() ?? 'Producto sin nombre',
        'codigo': producto?['codigo']?.toString() ?? '',
        'cantidad': 0.0,
      };
    }

    productosAgrupados[productoId]!['cantidad'] =
        (productosAgrupados[productoId]!['cantidad'] as double) +
            cantidad;
  }
}

final resumenProductos = productosAgrupados.values.toList();

resumenProductos.sort(
  (a, b) => a['nombre']
      .toString()
      .compareTo(b['nombre'].toString()),
);
      if (!mounted) return;

      setState(() {
  _pedidos = pedidosCargados;
  _resumenProductos = resumenProductos;
  _cargando = false;
});
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _error = 'No se pudieron cargar los pedidos.';
        _cargando = false;
      });
    }
  }

  String _formatearPrecio(dynamic valor) {
    final numero = double.tryParse(valor?.toString() ?? '') ?? 0;
    final entero = numero.round().toString();

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
    final anio = local.year.toString();

    final hora = local.hour.toString().padLeft(2, '0');
    final minuto = local.minute.toString().padLeft(2, '0');

    return '$dia/$mes/$anio $hora:$minuto';
  }
  int get _cantidadPedidos {
  return _pedidos.length;
}

double get _ventaTotal {
  return _pedidos.fold<double>(
    0,
    (total, pedido) {
      final valor = double.tryParse(
            pedido['total']?.toString() ?? '',
          ) ??
          0;

      return total + valor;
    },
  );
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Administración de pedidos'),
      ),
      body: _construirContenido(),
    );
  }

  Widget _construirContenido() {
    if (_cargando) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return Center(
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
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _cargarPedidos,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (_pedidos.isEmpty) {
      return const Center(
        child: Text(
          'No hay pedidos registrados.',
          style: TextStyle(fontSize: 18),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _cargarPedidos,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _pedidos.length + 2,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
  if (index == 0) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Pedidos',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 4),
                Text(
                  '$_cantidadPedidos',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text(
                  'Venta total',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatearPrecio(_ventaTotal),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  if (index == 1) {
  return Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'RESUMEN DE PRODUCTOS',
            style: TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          ..._resumenProductos.map(
            (producto) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      producto['nombre']?.toString() ??
                          'Producto sin nombre',
                    ),
                  ),
                 Text(
  ((producto['cantidad'] as num?) ?? 0).toDouble() % 1 == 0
      ? ((producto['cantidad'] as num?) ?? 0).toInt().toString()
      : ((producto['cantidad'] as num?) ?? 0).toString(),
  style: const TextStyle(
    fontWeight: FontWeight.bold,
  ),
),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

  final pedido = _pedidos[index - 2];

          final cliente =
              pedido['clientes'] as Map<String, dynamic>?;

          final usuario =
              pedido['usuarios'] as Map<String, dynamic>?;

          final clienteNombre =
              cliente?['nombre_comercio']?.toString() ??
                  'Cliente sin nombre';

          final direccion =
              cliente?['direccion']?.toString() ?? '';

          final vendedorNombre =
              usuario?['nombre']?.toString() ?? '';

          final vendedorApellido =
              usuario?['apellido']?.toString() ?? '';

          final vendedor = [
            vendedorNombre,
            vendedorApellido,
          ].where((texto) => texto.isNotEmpty).join(' ');

          final estado =
              pedido['estado']?.toString() ?? 'pendiente';

          final resultado =
              pedido['resultado_entrega']?.toString() ?? 'pendiente';

          final motivo =
              pedido['motivo_no_entrega']?.toString() ?? '';

          return Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          clienteNombre,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Text(
                        _formatearPrecio(pedido['total']),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  if (direccion.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(direccion),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    _formatearFecha(pedido['created_at']),
                    style: const TextStyle(
                      color: Colors.grey,
                    ),
                  ),
                  if (vendedor.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text('Preventista: $vendedor'),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    'Estado: ${estado.toUpperCase()}',
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Entrega: ${resultado.toUpperCase()}',
                  ),
                  if (resultado == 'no_entregado' &&
                      motivo.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Motivo: $motivo',
                    ),
                  ],
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final actualizado =
                            await Navigator.of(context).push<bool>(
                          MaterialPageRoute(
                            builder: (_) => ManageOrderPage(
                              pedido: pedido,
                            ),
                          ),
                        );

                        if (actualizado == true) {
                          await _cargarPedidos();
                        }
                      },
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('GESTIONAR PEDIDO'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}