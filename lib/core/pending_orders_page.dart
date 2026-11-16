import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'network_status.dart';
import 'pending_orders.dart';

String _money(double value) {
  final entero = value.round().toString();
  final b = StringBuffer();
  for (var i = 0; i < entero.length; i++) {
    if (i > 0 && (entero.length - i) % 3 == 0) b.write('.');
    b.write(entero[i]);
  }
  return '\$$b';
}

/// Tarjeta del inicio: aparece solo si hay pedidos guardados en el teléfono sin enviar.
class PendingOrdersCard extends StatelessWidget {
  const PendingOrdersCard({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<List<PendingOrder>>(
    valueListenable: PendingOrders.instance.items,
    builder: (context, items, _) {
      if (items.isEmpty) return const SizedBox.shrink();
      final rejected = items.where((o) => o.rejected != null).length;
      return Card(
        color: rejected > 0 ? const Color(0xFFFDECEA) : const Color(0xFFFFF3E0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: ListTile(
          leading: Icon(
            rejected > 0 ? Icons.error_outline : Icons.cloud_upload_outlined,
            color: rejected > 0 ? AppColors.rojo : AppColors.naranja,
            size: 28,
          ),
          title: Text(
            'Pendientes de enviar (${items.length})',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            rejected > 0
                ? '$rejected no se pudieron cargar: tocá para revisar'
                : 'Guardados en el teléfono. Se envían solos al volver la señal.',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const PendingOrdersPage()),
          ),
        ),
      );
    },
  );
}

class PendingOrdersPage extends StatelessWidget {
  const PendingOrdersPage({super.key});

  String _when(DateTime d) => describeSavedAt(d);

  Future<void> _sendNow(BuildContext context) async {
    final sent = await PendingOrders.instance.sendAll();
    if (!context.mounted) return;
    final left = PendingOrders.instance.items.value.where((o) => o.rejected == null).length;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          left == 0
              ? 'Listo: ${sent == 1 ? 'se envió 1 pedido' : 'se enviaron $sent pedidos'}.'
              : 'Todavía sin señal: quedan $left. Se envían solos cuando vuelva.',
        ),
      ),
    );
  }

  Future<void> _discard(BuildContext context, PendingOrder order) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Descartar pedido'),
        content: Text(
          'El pedido de ${order.clientName} no se cargó y se va a borrar del teléfono. '
          'Si hace falta, volvé a hacerlo desde Nuevo pedido.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Descartar')),
        ],
      ),
    );
    if (ok == true) await PendingOrders.instance.discard(order.id);
  }

  @override
  Widget build(BuildContext context) {
    final pending = PendingOrders.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Pendientes de enviar')),
      body: ValueListenableBuilder<List<PendingOrder>>(
        valueListenable: pending.items,
        builder: (context, items, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Estos pedidos se confirmaron sin señal y están guardados en el teléfono. '
              'Se envían solos cuando vuelve la conexión, y nunca se cargan dos veces.',
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder<bool>(
              valueListenable: pending.sending,
              builder: (context, busy, _) => FilledButton.icon(
                onPressed: busy || items.every((o) => o.rejected != null)
                    ? null
                    : () => _sendNow(context),
                icon: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_upload_outlined),
                label: Text(busy ? 'Enviando…' : 'Enviar ahora'),
              ),
            ),
            const SizedBox(height: 12),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Text('No hay pedidos pendientes.', textAlign: TextAlign.center),
              ),
            for (final order in items)
              Card(
                child: ListTile(
                  leading: Icon(
                    order.rejected != null ? Icons.error_outline : Icons.schedule,
                    color: order.rejected != null ? AppColors.rojo : AppColors.naranja,
                  ),
                  title: Text(order.clientName),
                  subtitle: Text(
                    '${order.isDirectSale ? 'Venta directa' : 'Pedido'} · ${_money(order.total)} · '
                    '${_when(order.createdAt)}'
                    '${order.rejected != null ? '\nNo se cargó: ${order.rejected}' : ''}',
                  ),
                  isThreeLine: order.rejected != null,
                  trailing: order.rejected != null
                      ? IconButton(
                          tooltip: 'Descartar',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _discard(context, order),
                        )
                      : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
