import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/offline_queries.dart';
import '../../core/text_search.dart';
import '../clients/new_client_page.dart';

typedef ClientLoader = Future<List<Map<String, dynamic>>> Function();

/// Pedido armado sin cliente: al final se crea uno nuevo o se elige uno
/// existente. Devuelve null si el preventista vuelve atrás.
Future<Map<String, dynamic>?> pickOrderClient(
  BuildContext context, {
  SupabaseClient? client,
  ClientLoader? loadClients,
  WidgetBuilder? newClientPage,
}) async {
  final opcion = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '¿Para quién es el pedido?',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('pedido-cliente-nuevo'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
              ),
              onPressed: () => Navigator.pop(context, 'nuevo'),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text(
                'CLIENTE NUEVO',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('pedido-cliente-existente'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
              ),
              onPressed: () => Navigator.pop(context, 'existente'),
              icon: const Icon(Icons.person_search),
              label: const Text(
                'CLIENTE QUE YA EXISTE',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  if (opcion == null || !context.mounted) return null;
  if (opcion == 'nuevo') {
    return Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: newClientPage ?? ((_) => const NewClientPage()),
      ),
    );
  }
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (_) => _ClientSearchDialog(
      load:
          loadClients ??
          (() => _clientesParaPedido(client ?? Supabase.instance.client)),
    ),
  );
}

Future<List<Map<String, dynamic>>> _clientesParaPedido(SupabaseClient c) async {
  final uid = c.auth.currentUser?.id;
  if (uid == null) throw Exception('No hay usuario autenticado');
  final usuario = await consultarRolActivo(c, uid);
  return List<Map<String, dynamic>>.from(
    await consultarClientesParaPedido(
      c,
      uid: uid,
      administrador: usuario['rol']?.toString() == 'administrador',
    ),
  );
}

class _ClientSearchDialog extends StatefulWidget {
  const _ClientSearchDialog({required this.load});

  final ClientLoader load;

  @override
  State<_ClientSearchDialog> createState() => _ClientSearchDialogState();
}

class _ClientSearchDialogState extends State<_ClientSearchDialog> {
  late Future<List<Map<String, dynamic>>> _clientes = widget.load();
  String _busqueda = '';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Elegí el cliente'),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      content: SizedBox(
        width: 460,
        height: 420,
        child: Column(
          children: [
            TextField(
              key: const Key('pedido-buscar-cliente'),
              autofocus: true,
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Buscar cliente...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _busqueda = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _clientes,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('No se pudieron cargar los clientes.'),
                          TextButton.icon(
                            onPressed: () =>
                                setState(() => _clientes = widget.load()),
                            icon: const Icon(Icons.refresh),
                            label: const Text('Reintentar'),
                          ),
                        ],
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final lista = snapshot.data!
                      .where(
                        (c) => coincideBusqueda(_busqueda, [
                          c['nombre_comercio'],
                          c['propietario'],
                          c['direccion'],
                        ]),
                      )
                      .take(60)
                      .toList();
                  if (lista.isEmpty) {
                    return const Center(
                      child: Text('No se encontraron clientes'),
                    );
                  }
                  return ListView.separated(
                    itemCount: lista.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final c = lista[i];
                      final direccion = c['direccion']?.toString() ?? '';
                      return ListTile(
                        leading: const Icon(Icons.storefront_outlined),
                        title: Text(
                          c['nombre_comercio']?.toString() ?? 'Sin nombre',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: direccion.isEmpty ? null : Text(direccion),
                        onTap: () => Navigator.pop(context, c),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Volver'),
        ),
      ],
    );
  }
}
