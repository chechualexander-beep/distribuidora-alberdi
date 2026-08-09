import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'order_products_page.dart';

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

  String _busqueda = '';

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
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => OrderProductsPage(
                      cliente: _clienteSeleccionado!,
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