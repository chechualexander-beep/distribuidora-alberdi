import 'package:flutter/material.dart';

import '../commissions/commissions_page.dart';
import '../orders/admin_orders_page.dart';
import '../commissions/commission_history_page.dart';
import '../invoicing/invoicing_page.dart';
import '../invoicing/invoiced_orders_page.dart';
class AdminPage extends StatelessWidget {
  const AdminPage({super.key});

  @override
  Widget build(BuildContext context) {
    final esEscritorio = MediaQuery.of(context).size.width >= 900;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Administración'),
      ),
      body: Center(
  child: ConstrainedBox(
    constraints: BoxConstraints(
      maxWidth: esEscritorio ? 1100 : double.infinity,
    ),
    child: ListView(
      padding: EdgeInsets.all(esEscritorio ? 24 : 16),
        children: [
          Card(
            child: ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.inventory_2_outlined),
              ),
              title: const Text(
                'Gestionar pedidos',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: const Text(
                'Preparación, reparto y resultado de entrega',
              ),
              trailing: const Icon(
                Icons.chevron_right,
              ),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AdminOrdersPage(),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
Card(
  child: ListTile(
    leading: const CircleAvatar(
      child: Icon(Icons.receipt_long_outlined),
    ),
    title: const Text(
      'Facturación',
      style: TextStyle(
        fontWeight: FontWeight.bold,
      ),
    ),
    subtitle: const Text(
      'Pedidos pendientes de facturar',
    ),
    trailing: const Icon(
      Icons.chevron_right,
    ),
    onTap: () {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const InvoicingPage(),
        ),
      );
    },
  ),
),
const SizedBox(height: 10),

Card(
  child: ListTile(
    leading: const CircleAvatar(
      child: Icon(Icons.history_outlined),
    ),
    title: const Text(
      'Facturas realizadas',
      style: TextStyle(
        fontWeight: FontWeight.bold,
      ),
    ),
    subtitle: const Text(
      'Consultar facturas emitidas y reimprimir',
    ),
    trailing: const Icon(
      Icons.chevron_right,
    ),
    onTap: () {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const InvoicedOrdersPage(),
        ),
      );
    },
  ),
),
          const SizedBox(height: 10),
          Card(
            child: ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.payments_outlined),
              ),
              title: const Text(
                'Liquidación de comisiones',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: const Text(
                'Ventas entregadas y comisión por preventista',
              ),
              trailing: const Icon(
                Icons.chevron_right,
              ),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const CommissionsPage(),
                  ),
                );
              },
            ),
          ),
  const SizedBox(height: 10),
  Card(
  child: ListTile(
    leading: const CircleAvatar(
      child: Icon(Icons.history_outlined),
    ),
    title: const Text(
      'Historial de liquidaciones',
      style: TextStyle(
        fontWeight: FontWeight.bold,
      ),
    ),
    subtitle: const Text(
      'Consultar liquidaciones registradas y pagadas',
    ),
    trailing: const Icon(
      Icons.chevron_right,
    ),
    onTap: () {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const CommissionHistoryPage(),
        ),
      );
    },
  ),
),
        ],
      ),
      ),
      ),
    );
  }
}