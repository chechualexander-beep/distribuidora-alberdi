import 'package:flutter/material.dart';
import '../clients/clients_page.dart';
import '../products/products_page.dart';
import '../products/admin_products_page.dart';
import '../orders/orders_page.dart';
import '../orders/new_order_page.dart';
import '../orders/admin_orders_page.dart';
import '../invoicing/invoicing_page.dart';
import '../invoicing/invoiced_orders_page.dart';
import '../commissions/my_commissions_page.dart';
import '../commissions/commissions_page.dart';
import '../commissions/commission_history_page.dart';
import '../admin/commercial_summary_page.dart';
import '../stock/stock_home_page.dart';
import '../stock/vehicle_load_page.dart';
import '../balances/balances_page.dart';
import '../catalog/general_catalog_page.dart';
import '../../core/pending_orders_page.dart';
import '../finance/finance_home_page.dart';
import '../finance/finance_dashboard_page.dart';

class DesktopHome extends StatefulWidget {
  const DesktopHome({
    super.key,
    required this.name,
    required this.isAdmin,
    this.canGeneralCatalog = false,
    required this.onSignOut,
  });
  final String name;
  final bool isAdmin;
  final bool canGeneralCatalog;
  final VoidCallback onSignOut;
  @override
  State<DesktopHome> createState() => _DesktopHomeState();
}

class _DesktopHomeState extends State<DesktopHome> {
  String _selected = 'Inicio';
  void _newOrder() => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const NewOrderPage()));
  Widget _page() => switch (_selected) {
    'Clientes' => const ClientsPage(),
    'Productos' => const ProductsPage(),
    'Pedidos' => const OrdersPage(),
    'Mis comisiones' => const MyCommissionsPage(),
    'Preparación y reparto' => const AdminOrdersPage(),
    'Facturación' => const InvoicingPage(),
    'Facturas realizadas' => const InvoicedOrdersPage(),
    'Comisiones' => const CommissionsPage(),
    'Liquidaciones' => const CommissionHistoryPage(),
    'Administrar productos' => const AdminProductsPage(),
    'Stock' when widget.isAdmin => const StockHomePage(),
    'Lo que llevamos' => const VehicleLoadPage(),
    'Saldos' when widget.isAdmin => const BalancesPage(),
    'Plata del negocio' when widget.isAdmin => const FinanceHomePage(),
    'Tablero del mes' when widget.isAdmin => const FinanceDashboardPage(),
    'Catálogo general' when widget.canGeneralCatalog => GeneralCatalogPage(
      isAdmin: widget.isAdmin,
    ),
    'Resumen comercial' => const CommercialSummaryPage(),
    _ => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 12, 24, 0),
          child: PendingOrdersCard(),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hola, ${widget.name}',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.isAdmin
                          ? 'Pedidos pendientes de facturar'
                          : 'Tus pedidos',
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: _newOrder,
                icon: const Icon(Icons.add, size: 20),
                label: const Text('Nuevo pedido'),
              ),
            ],
          ),
        ),
        Expanded(
          child: widget.isAdmin
              ? const InvoicingPage(embedded: true)
              : const OrdersPage(),
        ),
      ],
    ),
  };
  @override
  Widget build(BuildContext context) {
    Widget link(String name, IconData icon) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        selected: _selected == name,
        selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
        leading: Icon(icon, size: 20),
        title: Text(name),
        onTap: () => setState(() => _selected = name),
      ),
    );
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 56,
        backgroundColor: const Color(0xFF062A5E),
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        title: const Text(
          'Alberdi',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: widget.onSignOut,
            icon: const Icon(Icons.logout, size: 22),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Row(
        children: [
          SizedBox(
            width: 220,
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(10),
                    children: [
                      link('Inicio', Icons.home_outlined),
                      link('Clientes', Icons.people_outline),
                      link('Productos', Icons.inventory_2_outlined),
                      link('Pedidos', Icons.receipt_long_outlined),
                      link('Mis comisiones', Icons.payments_outlined),
                      if (!widget.isAdmin)
                        link('Lo que llevamos', Icons.local_shipping_outlined),
                      if (widget.canGeneralCatalog)
                        link('Catálogo general', Icons.storefront_outlined),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: _newOrder,
                        icon: const Icon(Icons.add, size: 20),
                        label: const Text('Nuevo pedido'),
                      ),
                      if (widget.isAdmin) ...[
                        const Padding(
                          padding: EdgeInsets.fromLTRB(12, 24, 12, 8),
                          child: Text(
                            'ADMINISTRACIÓN',
                            style: TextStyle(fontSize: 11, letterSpacing: 1),
                          ),
                        ),
                        link('Plata del negocio', Icons.savings_outlined),
                        link('Tablero del mes', Icons.insights),
                        link('Saldos', Icons.account_balance_wallet_outlined),
                        link(
                          'Preparación y reparto',
                          Icons.local_shipping_outlined,
                        ),
                        link('Facturación', Icons.request_quote_outlined),
                        link('Facturas realizadas', Icons.history),
                        link('Comisiones', Icons.payments_outlined),
                        link(
                          'Liquidaciones',
                          Icons.account_balance_wallet_outlined,
                        ),
                        link('Administrar productos', Icons.edit_note),
                        link('Stock', Icons.warehouse_outlined),
                        link('Resumen comercial', Icons.analytics_outlined),
                      ],
                    ],
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  dense: true,
                  title: Text(widget.name),
                  subtitle: Text(
                    widget.isAdmin ? 'Administrador' : 'Preventista',
                  ),
                ),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: KeyedSubtree(key: ValueKey(_selected), child: _page()),
          ),
        ],
      ),
    );
  }
}
