import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'client_detail_page.dart';
import 'new_client_page.dart';

class ClientsPage extends StatefulWidget {
  const ClientsPage({super.key});

  @override
  State<ClientsPage> createState() => _ClientsPageState();
}

class _ClientsPageState extends State<ClientsPage> {
  bool _cargando = true;
  String? _error;

  List<Map<String, dynamic>> _clientes = [];
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
          .select()
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
        title: const Text('Clientes'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final clienteCreado = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => const NewClientPage(),
            ),
          );

          if (clienteCreado == true) {
            await _cargarClientes();
          }
        },
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Nuevo cliente'),
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
                onPressed: _cargarClientes,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (_clientes.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 80,
            ),
            SizedBox(height: 20),
            Text(
              'Todavía no hay clientes cargados',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Presioná "Nuevo cliente" para agregar el primero.',
              textAlign: TextAlign.center,
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

      final telefono =
          cliente['telefono']?.toString().toLowerCase() ?? '';

      return comercio.contains(texto) ||
          propietario.contains(texto) ||
          direccion.contains(texto) ||
          telefono.contains(texto);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
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
              : RefreshIndicator(
                  onRefresh: _cargarClientes,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: clientesFiltrados.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final cliente = clientesFiltrados[index];

                      final comercio =
                          cliente['nombre_comercio']?.toString() ??
                              'Sin nombre';

                      final propietario =
                          cliente['propietario']?.toString();

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
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (propietario != null &&
                                  propietario.isNotEmpty)
                                Text(propietario),
                              Text(direccion),
                              if (localidad != null &&
                                  localidad.isNotEmpty)
                                Text(localidad),
                            ],
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () async {
                            final actualizado =
                                await Navigator.of(context).push<bool>(
                              MaterialPageRoute(
                                builder: (_) => ClientDetailPage(
                                  cliente: cliente,
                                ),
                              ),
                            );

                            if (actualizado == true) {
                              await _cargarClientes();
                            }
                          },
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}