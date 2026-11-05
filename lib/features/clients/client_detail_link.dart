import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'client_detail_page.dart';

class ClientDetailLink extends StatelessWidget {
  const ClientDetailLink({
    super.key,
    this.clientId,
    this.client,
    this.enabled = true,
  });

  final String? clientId;
  final SupabaseClient? client;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: !enabled || clientId == null || clientId!.isEmpty
          ? null
          : () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => _ClientDetailLookup(
                  clientId: clientId!,
                  client: client ?? Supabase.instance.client,
                ),
              ),
            ),
      child: const Text('Ver ficha'),
    );
  }
}

class _ClientDetailLookup extends StatefulWidget {
  const _ClientDetailLookup({required this.clientId, required this.client});

  final String clientId;
  final SupabaseClient client;

  @override
  State<_ClientDetailLookup> createState() => _ClientDetailLookupState();
}

class _ClientDetailLookupState extends State<_ClientDetailLookup> {
  late final Future<Map<String, dynamic>?> _cliente = widget.client
      .from('clientes')
      .select()
      .eq('id', widget.clientId)
      .maybeSingle();

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _cliente,
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        return ClientDetailPage(
          cliente: snapshot.data!,
          client: widget.client,
          soloConsulta: true,
        );
      }
      return Scaffold(
        appBar: AppBar(title: const Text('Ficha del cliente')),
        body: Center(
          child: snapshot.connectionState != ConnectionState.done
              ? const CircularProgressIndicator()
              : Text(
                  snapshot.hasError
                      ? 'No se pudo consultar la ficha del cliente.'
                      : 'El cliente ya no existe o no está disponible para tu usuario.',
                ),
        ),
      );
    },
  );
}
