import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'order_products_page.dart';
import '../clients/client_detail_page.dart';

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
bool _cargandoSaldoCliente = false;
double _deudaCliente = 0;
int _pedidosPendientesCliente = 0;
  String _busqueda = '';
  DateTime? _fechaEntrega;

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
      final respuesta = await Supabase.instance.client
          .from('clientes')
          .select(
            'id, nombre_comercio, propietario, direccion, localidad',
          )
          .eq('activo', true)
          .order('nombre_comercio');

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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
Card(
  child: ListTile(
    leading: const Icon(Icons.calendar_month_outlined),
    title: const Text('Fecha de entrega'),
    subtitle: Text(
      _fechaEntrega == null
          ? 'Seleccionar fecha'
          : '${_fechaEntrega!.day.toString().padLeft(2, '0')}/'
              '${_fechaEntrega!.month.toString().padLeft(2, '0')}/'
              '${_fechaEntrega!.year}',
    ),
    trailing: const Icon(Icons.chevron_right),
    onTap: _seleccionarFechaEntrega,
  ),
),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => OrderProductsPage(
                      cliente: _clienteSeleccionado!,
                      fechaEntrega: _fechaEntrega,
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