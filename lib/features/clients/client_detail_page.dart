import 'package:flutter/material.dart';

import 'edit_client_page.dart';

class ClientDetailPage extends StatelessWidget {
  final Map<String, dynamic> cliente;

  const ClientDetailPage({
    super.key,
    required this.cliente,
  });

  String _texto(dynamic valor) {
    if (valor == null) return 'Sin información';

    final texto = valor.toString().trim();

    return texto.isEmpty ? 'Sin información' : texto;
  }

  @override
  Widget build(BuildContext context) {
    final comercio = _texto(cliente['nombre_comercio']);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ficha del cliente'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const CircleAvatar(
            radius: 42,
            child: Icon(
              Icons.storefront,
              size: 42,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            comercio,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 30),

          _DatoCliente(
            icono: Icons.location_on_outlined,
            titulo: 'Dirección',
            valor: _texto(cliente['direccion']),
          ),

          _DatoCliente(
            icono: Icons.location_city_outlined,
            titulo: 'Localidad',
            valor: _texto(cliente['localidad']),
          ),

          _DatoCliente(
            icono: Icons.person_outline,
            titulo: 'Propietario',
            valor: _texto(cliente['propietario']),
          ),

          _DatoCliente(
            icono: Icons.phone_outlined,
            titulo: 'Teléfono',
            valor: _texto(cliente['telefono']),
          ),

          _DatoCliente(
            icono: Icons.map_outlined,
            titulo: 'Zona',
            valor: _texto(cliente['zona']),
          ),

          _DatoCliente(
            icono: Icons.notes_outlined,
            titulo: 'Observaciones',
            valor: _texto(cliente['observaciones']),
          ),

          const SizedBox(height: 28),

          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: () async {
                final actualizado =
                    await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => EditClientPage(
                      cliente: cliente,
                    ),
                  ),
                );

                if (actualizado == true && context.mounted) {
                  Navigator.of(context).pop(true);
                }
              },
              icon: const Icon(Icons.edit_outlined),
              label: const Text('EDITAR CLIENTE'),
            ),
          ),
        ],
      ),
    );
  }
}

class _DatoCliente extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String valor;

  const _DatoCliente({
    required this.icono,
    required this.titulo,
    required this.valor,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(icono),
        title: Text(
          titulo,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(valor),
      ),
    );
  }
}