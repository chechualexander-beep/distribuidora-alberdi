import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ClientsPage extends StatefulWidget {
  const ClientsPage({super.key});

  @override
  State<ClientsPage> createState() => _ClientsPageState();
}

class _ClientsPageState extends State<ClientsPage> {
  bool _cargando = true;
  String? _error;
  List<Map<String, dynamic>> _clientes = [];

  @override
  void initState() {
    super.initState();
    _cargarClientes();
  }

  Future<void> _cargarClientes() async {
    try {
      final datos = await Supabase.instance.client
          .from('clientes')
          .select(
            'id, nombre_comercio, propietario, telefono, direccion, localidad, zona',
          )
          .eq('activo', true)
          .order('nombre_comercio');

      if (!mounted) return;

      setState(() {
        _clientes = List<Map<String, dynamic>>.from(datos);
        _cargando = false;
      });
    } catch (error) {
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
      body: _cargando
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : _error != null
              ? Center(
                  child: Text(_error!),
                )
              : _clientes.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.people_outline,
                            size: 70,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Todavía no hay clientes cargados',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'En el próximo paso agregaremos el primero.',
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _cargarClientes,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _clientes.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final cliente = _clientes[index];

                          final nombre =
                              cliente['nombre_comercio']?.toString() ?? '';

                          final direccion =
                              cliente['direccion']?.toString() ?? '';

                          final localidad =
                              cliente['localidad']?.toString() ?? '';

                          return Card(
                            child: ListTile(
                              leading: const CircleAvatar(
                                child: Icon(Icons.store_outlined),
                              ),
                              title: Text(
                                nombre,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(
                                [
                                  direccion,
                                  if (localidad.isNotEmpty) localidad,
                                ].join(' • '),
                              ),
                              trailing:
                                  const Icon(Icons.chevron_right),
                              onTap: () {},
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}