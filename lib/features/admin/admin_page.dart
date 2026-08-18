import 'package:flutter/material.dart';

import '../commissions/commissions_page.dart';
import '../orders/admin_orders_page.dart';
import '../commissions/commission_history_page.dart';
import '../invoicing/invoicing_page.dart';
import '../invoicing/invoiced_orders_page.dart';
import '../products/admin_products_page.dart';
class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  int _seccionSeleccionada = 0;

  @override
  Widget build(BuildContext context) {
    final esEscritorio = MediaQuery.of(context).size.width >= 900;
    if (esEscritorio) {
  return Scaffold(
    body: Row(
      children: [
        Container(
          width: 250,
          padding: const EdgeInsets.all(20),
          child: Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    const Icon(
      Icons.inventory_2_outlined,
      size: 36,
    ),
    const SizedBox(height: 12),
    const Text(
      'Distribuidora Alberdi',
      style: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    ),
    const SizedBox(height: 4),
    const Text('Administración'),

    const SizedBox(height: 28),

    ListTile(
      selected: _seccionSeleccionada == 1,
      leading: const Icon(Icons.inventory_2_outlined),
      title: const Text('Pedidos'),
      onTap: () {
  setState(() {
    _seccionSeleccionada = 1;
  });
},
    ),

    ListTile(
      selected: _seccionSeleccionada == 2,
      leading: const Icon(Icons.receipt_long_outlined),
      title: const Text('Facturación'),
      onTap: () {
  setState(() {
    _seccionSeleccionada = 2;
  });
},
    ),

    ListTile(
      selected: _seccionSeleccionada == 3,
      leading: const Icon(Icons.history_outlined),
      title: const Text('Facturas realizadas'),
      onTap: () {
  setState(() {
    _seccionSeleccionada = 3;
  });
},
    ),

    ListTile(
      selected: _seccionSeleccionada == 4,
      leading: const Icon(Icons.payments_outlined),
      title: const Text('Comisiones'),
      onTap: () {
  setState(() {
    _seccionSeleccionada = 4;
  });
},
    ),

    ListTile(
      selected: _seccionSeleccionada == 5,
      leading: const Icon(Icons.history_outlined),
      title: const Text('Historial de liquidaciones'),
      onTap: () {
  setState(() {
    _seccionSeleccionada = 5;
  });
},
    ),
    ListTile(
  selected: _seccionSeleccionada == 6,
  leading: const Icon(Icons.inventory_outlined),
  title: const Text('Productos'),
  onTap: () {
    setState(() {
      _seccionSeleccionada = 6;
    });
  },
),
  ],
),

        ),
        const VerticalDivider(width: 1),
        Expanded(
  child: _seccionSeleccionada == 1
      ? const AdminOrdersPage()
      : _seccionSeleccionada == 2
          ? const InvoicingPage()
          : _seccionSeleccionada == 3
              ? const InvoicedOrdersPage()
              : _seccionSeleccionada == 4
                  ? const CommissionsPage()
                  : _seccionSeleccionada == 5
                      ? const CommissionHistoryPage()
                      : _seccionSeleccionada == 6
                          ? const AdminProductsPage()
                      : Center(
                          child: Text(
                            _tituloSeccion(),
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
),
      ],
    ),
  );
  
}
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
  String _tituloSeccion() {
  switch (_seccionSeleccionada) {
    case 0:
      return 'Panel de administración';
    case 1:
      return 'Pedidos';
    case 2:
      return 'Facturación';
    case 3:
      return 'Facturas realizadas';
    case 4:
      return 'Comisiones';
    case 5:
      return 'Historial de liquidaciones';
      case 6:
  return 'Productos';
    default:
      return 'Panel de administración';
  }
}
}