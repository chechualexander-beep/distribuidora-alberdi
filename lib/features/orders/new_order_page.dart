import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'order_products_page.dart';
import '../clients/client_detail_page.dart';
import 'order_detail_page.dart';
import '../clients/new_client_page.dart';

class NewOrderPage extends StatefulWidget {
  const NewOrderPage({super.key});

  @override
  State<NewOrderPage> createState() => _NewOrderPageState();
}

class _NewOrderPageState extends State<NewOrderPage> {
  bool _cargando = true;
  String? _error;

  List<Map<String, dynamic>> _clientes = [];
  Map<String, dynamic>? _clienteSeleccionado;
  List<Map<String, dynamic>> _ultimosPedidos = [];
  String _tipoOperacion = 'pedido';
bool _cargandoSaldoCliente = false;
double _deudaCliente = 0;
int _pedidosPendientesCliente = 0;
  String _busqueda = '';
  static DateTime? _ultimaFechaEntrega;
  DateTime? _fechaEntrega = _ultimaFechaEntrega;

  @override
  void initState() {
    super.initState();
    _cargarClientes();
  }

  Future<void> _cargarClientes() async {
  setState(() {
    _cargando = true;
    _error = null;
  });

  try {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null) {
      throw Exception('No hay usuario autenticado');
    }

    final usuario = await supabase
        .from('usuarios')
        .select('rol')
        .eq('id', user.id)
        .single();

    final String rol = usuario['rol']?.toString() ?? '';

    dynamic consulta = supabase
        .from('clientes')
        .select(
          'id, nombre_comercio, propietario, direccion, localidad, tipo_precio_habitual',
        )
        .eq('activo', true);

    if (rol != 'administrador') {
      consulta = consulta.eq('preventista_id', user.id);
    }

    final respuesta = await consulta.order('nombre_comercio');

    if (!mounted) return;

    setState(() {
      _clientes = List<Map<String, dynamic>>.from(respuesta);
      _cargando = false;
    });
  } catch (_) {
    if (!mounted) return;

    setState(() {
      _error = 'No se pudieron cargar los clientes.';
      _cargando = false;
    });
  }
}
Future<void> _cargarSaldoCliente(Map<String, dynamic> cliente) async {
  try {
    setState(() {
      _cargandoSaldoCliente = true;
      _deudaCliente = 0;
      _pedidosPendientesCliente = 0;
    });

    final clienteId = cliente['id']?.toString();

    if (clienteId == null || clienteId.isEmpty) {
      throw Exception('Cliente sin ID');
    }

    final pedidos = await Supabase.instance.client
        .from('pedidos')
        .select('id, total, estado, resultado_entrega')
        .eq('cliente_id', clienteId);

    double deudaTotal = 0;
    int cantidadPendientes = 0;

    for (final pedido in pedidos) {
      final estado =
          pedido['estado']?.toString().toLowerCase() ?? '';
      final resultadoEntrega =
          pedido['resultado_entrega']?.toString().toLowerCase() ?? '';

      final esCobrable =
          estado != 'cancelado' &&
          resultadoEntrega != 'no_entregado';

      if (!esCobrable) continue;

      final totalPedido =
          double.tryParse(pedido['total']?.toString() ?? '') ?? 0;

      final pagos = await Supabase.instance.client
          .from('pedido_pagos')
          .select('importe')
          .eq('pedido_id', pedido['id']);

      double pagadoPedido = 0;

      for (final pago in pagos) {
        pagadoPedido +=
            double.tryParse(pago['importe']?.toString() ?? '') ?? 0;
      }

      final saldoPedido = totalPedido - pagadoPedido;

      if (saldoPedido > 0) {
        deudaTotal += saldoPedido;
        cantidadPendientes++;
      }
    }

    if (!mounted) return;

    setState(() {
      _deudaCliente = deudaTotal;
      _pedidosPendientesCliente = cantidadPendientes;
      _cargandoSaldoCliente = false;
    });
  } catch (_) {
    if (!mounted) return;

    setState(() {
      _deudaCliente = 0;
      _pedidosPendientesCliente = 0;
      _cargandoSaldoCliente = false;
    });
  }
}

Future<void> _cargarUltimosPedidos(
  Map<String, dynamic> cliente,
) async {
  try {
    final clienteId = cliente['id']?.toString();

    if (clienteId == null || clienteId.isEmpty) {
      return;
    }

    final respuesta = await Supabase.instance.client
        .from('pedidos')
        .select(
          'id, total, created_at, fecha_entrega',
        )
        .eq('cliente_id', clienteId)
        .order('created_at', ascending: false)
        .limit(2);

    final pedidosCargados =
        List<Map<String, dynamic>>.from(respuesta);

    for (final pedido in pedidosCargados) {
      final pedidoId = pedido['id'];

      final detalles = await Supabase.instance.client
          .from('pedido_detalles')
          .select('tipo_precio')
          .eq('pedido_id', pedidoId);

      final tipos = <String>{};

      for (final detalle in detalles) {
        final tipo = detalle['tipo_precio']?.toString();

        if (tipo == 'normal' ||
            tipo == 'promo' ||
            tipo == 'interior') {
          tipos.add(tipo!);
        }
      }

      if (tipos.isEmpty) {
        pedido['tipo_precio_historial'] = 'normal';
      } else if (tipos.length == 1) {
        pedido['tipo_precio_historial'] = tipos.first;
      } else {
        final nombres = <String>[];

        if (tipos.contains('normal')) {
          nombres.add('Normal');
        }

        if (tipos.contains('promo')) {
          nombres.add('Promo');
        }

        if (tipos.contains('interior')) {
          nombres.add('Interior');
        }

        pedido['tipo_precio_historial'] =
            'Mixto (${nombres.join(' + ')})';
      }
    }

    if (!mounted) return;

    setState(() {
      _ultimosPedidos = pedidosCargados;
    });
  } catch (_) {
    if (!mounted) return;

    setState(() {
      _ultimosPedidos = [];
    });
  }
}
Future<void> _seleccionarFechaEntrega() async {
  final hoy = DateTime.now();

  final fecha = await showDatePicker(
    context: context,
    initialDate: _fechaEntrega ?? hoy,
    firstDate: hoy,
    lastDate: hoy.add(const Duration(days: 365)),
  );

  if (!mounted || fecha == null) return;

  setState(() {
    _fechaEntrega = fecha;
    _ultimaFechaEntrega = fecha;
  });
}
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nuevo pedido'),
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
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _cargarClientes,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (_clienteSeleccionado != null) {
      final cliente = _clienteSeleccionado!;

      return Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(
  children: [
            const Text(
              'Cliente seleccionado',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.storefront),
                ),
                title: Text(
                  cliente['nombre_comercio']?.toString() ?? 'Sin nombre',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  cliente['direccion']?.toString() ?? '',
                ),
                trailing: IconButton(
                  tooltip: 'Cambiar cliente',
                  onPressed: () {
                    setState(() {
                      _clienteSeleccionado = null;
                      _busqueda = '';
                    });
                  },
                  icon: const Icon(Icons.swap_horiz),
                ),
              ),
            ),
            const SizedBox(height: 16),

const Text(
  'Tipo de operación',
  style: TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.bold,
  ),
),
const SizedBox(height: 10),

SegmentedButton<String>(
  segments: const [
    ButtonSegment<String>(
      value: 'pedido',
      icon: Icon(Icons.shopping_cart_outlined),
      label: Text('Pedido'),
    ),
    ButtonSegment<String>(
      value: 'venta_directa',
      icon: Icon(Icons.point_of_sale),
      label: Text('Venta directa'),
    ),
  ],
  selected: {_tipoOperacion},
  onSelectionChanged: (seleccion) {
  setState(() {
    _tipoOperacion = seleccion.first;

    if (_tipoOperacion == 'venta_directa') {
      final hoy = DateTime.now();
      _fechaEntrega = DateTime(hoy.year, hoy.month, hoy.day);
      _ultimaFechaEntrega = _fechaEntrega;
    }
  });
},
),

const SizedBox(height: 16),
            if (_cargandoSaldoCliente) ...[
  const SizedBox(height: 16),
  const Center(
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        SizedBox(width: 10),
        Text('Consultando saldo del cliente...'),
      ],
    ),
  ),
],
if (!_cargandoSaldoCliente && _deudaCliente > 0) ...[
  const SizedBox(height: 16),
  Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Cliente con saldo pendiente',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$_pedidosPendientesCliente '
                  '${_pedidosPendientesCliente == 1 ? 'pedido pendiente' : 'pedidos pendientes'}',
                ),
                Text(
                  'Deuda total: \$${_deudaCliente.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),

TextButton.icon(
  onPressed: () {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ClientDetailPage(
        cliente: _clienteSeleccionado!,
      ),
    ),
  );
},
  icon: const Icon(Icons.visibility_outlined),
  label: const Text('REVISAR SALDO'),
),
              ],
            ),
          ),
        ],
      ),
    ),
  ),
],
if (_ultimosPedidos.isNotEmpty) ...[
  const SizedBox(height: 16),
  Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Últimos pedidos',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),

          ..._ultimosPedidos.map((pedido) {
            final fecha =
                DateTime.tryParse(pedido['created_at']?.toString() ?? '');

            final fechaTexto = fecha == null
                ? 'Sin fecha'
                : '${fecha.day.toString().padLeft(2, '0')}/'
                  '${fecha.month.toString().padLeft(2, '0')}/'
                  '${fecha.year}';

            final total =
                double.tryParse(pedido['total']?.toString() ?? '') ?? 0;

            final tipoPrecio =
    pedido['tipo_precio_historial']?.toString() ?? 'normal';

            final nombreTipo = switch (tipoPrecio) {
  'promo' => 'Promo',
  'interior' => 'Interior',
  'normal' => 'Normal',
  _ => tipoPrecio,
};

            return InkWell(
  borderRadius: BorderRadius.circular(8),
  onTap: () {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OrderDetailPage(
          pedido: pedido,
        ),
      ),
    );
  },
  child: Padding(
    padding: const EdgeInsets.symmetric(
      vertical: 8,
      horizontal: 4,
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            '$fechaTexto · $nombreTipo',
          ),
        ),
        Text(
          '\$${total.toStringAsFixed(0)}',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 6),
        const Icon(
          Icons.chevron_right,
          size: 18,
        ),
      ],
    ),
  ),
);
          }),
        ],
      ),
    ),
  ),
],
Card(
  child: ListTile(
    leading: const Icon(Icons.calendar_month_outlined),
    title: Text(
      _tipoOperacion == 'venta_directa'
          ? 'Entrega inmediata'
          : 'Fecha de entrega',
    ),
    subtitle: Text(
      _tipoOperacion == 'venta_directa'
          ? 'Hoy'
          : _fechaEntrega == null
              ? 'Seleccionar fecha'
              : '${_fechaEntrega!.day.toString().padLeft(2, '0')}/'
                '${_fechaEntrega!.month.toString().padLeft(2, '0')}/'
                '${_fechaEntrega!.year}',
    ),
    trailing: _tipoOperacion == 'venta_directa'
        ? const Icon(Icons.check_circle_outline)
        : const Icon(Icons.chevron_right),
    onTap: _tipoOperacion == 'venta_directa'
        ? null
        : _seleccionarFechaEntrega,
  ),
),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
  if (_fechaEntrega == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Seleccioná una fecha de entrega antes de continuar.'),
      ),
    );
    return;
  }

  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => OrderProductsPage(
        cliente: _clienteSeleccionado!,
        fechaEntrega: _fechaEntrega,
        tipoOperacion: _tipoOperacion,
      ),
    ),
  );
},
              icon: const Icon(Icons.shopping_cart_outlined),
              label: const Text('CONTINUAR CON PRODUCTOS'),
            ),
          ],
        ),
      );
    }

    final texto = _busqueda.toLowerCase();

    final clientesFiltrados = _clientes.where((cliente) {
      final comercio =
          cliente['nombre_comercio']?.toString().toLowerCase() ?? '';

      final propietario =
          cliente['propietario']?.toString().toLowerCase() ?? '';

      final direccion =
          cliente['direccion']?.toString().toLowerCase() ?? '';

      return comercio.contains(texto) ||
          propietario.contains(texto) ||
          direccion.contains(texto);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Buscar cliente...',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: (valor) {
              setState(() {
                _busqueda = valor.trim();
              });
            },
          ),
        ),
        Padding(
  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
  child: Material(
    color: const Color(0xFFF0F5FF),
    borderRadius: BorderRadius.circular(14),
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        final clienteCreado =
            await Navigator.of(context).push<Map<String, dynamic>>(
          MaterialPageRoute(
            builder: (_) => const NewClientPage(),
          ),
        );

        if (clienteCreado != null) {
          await _cargarClientes();

          if (!mounted) return;

          setState(() {
            _clienteSeleccionado = clienteCreado;
            _busqueda = '';
          });

          await _cargarSaldoCliente(clienteCreado);
          await _cargarUltimosPedidos(clienteCreado);
        }
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFF1565C0),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                color: Color(0xFFD8E6FF),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.person_add_alt_1,
                color: Color(0xFF1565C0),
                size: 27,
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'NUEVO CLIENTE',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0B4A91),
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Agregar un cliente nuevo',
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF1565C0),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: Color(0xFF0B4A91),
            ),
          ],
        ),
      ),
    ),
  ),
),
        Expanded(
          child: clientesFiltrados.isEmpty
              ? const Center(
                  child: Text(
                    'No se encontraron clientes',
                    style: TextStyle(fontSize: 16),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: clientesFiltrados.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final cliente = clientesFiltrados[index];

                    final comercio =
                        cliente['nombre_comercio']?.toString() ??
                            'Sin nombre';

                    final direccion =
                        cliente['direccion']?.toString() ?? '';

                    final localidad =
                        cliente['localidad']?.toString();

                    return Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.storefront),
                        ),
                        title: Text(
                          comercio,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          [
                            direccion,
                            if (localidad != null &&
                                localidad.toString().isNotEmpty)
                              localidad.toString(),
                          ].join(' • '),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          setState(() {
                            _clienteSeleccionado = cliente;
                          });
                          _cargarSaldoCliente(cliente);
                          _cargarUltimosPedidos(cliente);

                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}