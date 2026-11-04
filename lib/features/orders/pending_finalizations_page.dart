import '../../core/app_config.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'finalization_request.dart';
import 'manage_order_page.dart';

/// Always reachable from reparto, even if a confirmed order disappeared from
/// the pending delivery query or the selected date changed after app restart.
class PendingFinalizationsPage extends StatefulWidget {
  const PendingFinalizationsPage({super.key});

  @override
  State<PendingFinalizationsPage> createState() =>
      _PendingFinalizationsPageState();
}

class _PendingFinalizationsPageState extends State<PendingFinalizationsPage> {
  List<String>? _ids;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!appConfig.finalizationV2Enabled) {
      setState(
        () => _error = 'Recuperación V2 disponible únicamente en TESTING.',
      );
      return;
    }
    try {
      final store = await finalizationStore(Supabase.instance.client);
      if (mounted) setState(() => _ids = store.pendingOrderIds);
    } on LocalOutboxException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No se pudo leer la recuperación local.');
      }
    }
  }

  Future<void> _open(String id) async {
    if (!appConfig.finalizationV2Enabled) return;
    setState(() => _busy = true);
    try {
      final pedido = await Supabase.instance.client
          .from('pedidos')
          .select('*,clientes(nombre_comercio,direccion)')
          .eq('id', id)
          .single();
      if (!mounted) return;
      await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => ManageOrderPage(pedido: pedido)),
      );
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo abrir la solicitud. Se conserva para reintentar.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Solicitudes guardadas')),
    body: _error != null
        ? Center(child: Text(_error!))
        : _ids == null
        ? const Center(child: CircularProgressIndicator())
        : _ids!.isEmpty
        ? const Center(child: Text('No hay gestiones por confirmar.'))
        : ListView(
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Revisá cada solicitud antes de iniciar otra gestión. Los reintentos conservan cantidades, pago y fecha.',
                ),
              ),
              for (final id in _ids!)
                ListTile(
                  title: Text('Pedido $id'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _busy ? null : () => _open(id),
                ),
            ],
          ),
  );
}
