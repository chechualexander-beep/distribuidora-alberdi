import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_theme.dart';
import '../home/home_menu.dart';
import '../home/home_summary.dart';
import '../clients/clients_page.dart';
import '../products/products_page.dart';
import '../orders/orders_page.dart';
import '../orders/new_order_page.dart';
import '../orders/admin_orders_page.dart';
import '../invoicing/invoicing_page.dart';
import '../commissions/my_commissions_page.dart';
import '../commissions/commissions_page.dart';
import '../admin/commercial_summary_page.dart';
import '../stock/stock_home_page.dart';
import '../stock/vehicle_load_page.dart';
import '../balances/balances_page.dart';
import '../catalog/general_catalog_page.dart';
import '../../core/pending_orders_page.dart';
import '../finance/finance_home_page.dart';
import '../finance/finance_data.dart' show pesos;
import '../finance/finance_dashboard_page.dart';
import '../sales/special_sale_page.dart';
import '../calculator/calculator_page.dart';

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
  HomeSummary? _summary;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  /// Los números del menú y de la tarjeta Hoy (si no se pueden leer, el menú queda sin números).
  Future<void> _loadSummary() async {
    if (!widget.isAdmin) return;
    try {
      final summary = await fetchHomeSummary(Supabase.instance.client, admin: true);
      if (mounted) setState(() => _summary = summary);
    } catch (_) {}
  }

  void _go(String name) {
    setState(() => _selected = name);
    _loadSummary();
  }

  Future<void> _newOrder() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NewOrderPage()));
    _loadSummary();
  }

  Widget _page() => switch (_selected) {
    'Clientes' => const ClientsPage(),
    'Productos' => const ProductsPage(),
    'Pedidos' => const OrdersPage(),
    'Mis comisiones' => const MyCommissionsPage(),
    'Reparto' => const AdminOrdersPage(),
    'Facturar' => const InvoicingPage(),
    'Comisiones' => const CommissionsPage(),
    'Stock' when widget.isAdmin => const StockHomePage(),
    'En negativo' when widget.isAdmin => const StockHomePage(onlyNegatives: true),
    'Lo que llevamos' => const VehicleLoadPage(),
    'Saldos' when widget.isAdmin => const BalancesPage(),
    'Venta especial' when widget.isAdmin => const SpecialSalePage(),
    'Plata del negocio' when widget.isAdmin => const FinanceHomePage(),
    'Tablero del mes' when widget.isAdmin => const FinanceDashboardPage(),
    'Catálogo general' when widget.canGeneralCatalog => GeneralCatalogPage(
      isAdmin: widget.isAdmin,
    ),
    'Resumen y estadísticas' => const CommercialSummaryPage(),
    'Calculadora' => const CalculatorPage(),
    _ => _home(),
  };

  Widget _home() {
    final r = _summary;
    String n(int? v) => v == null ? '–' : '$v';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 12, 24, 0),
          child: PendingOrdersCard(),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
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
              if (widget.isAdmin)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: TodayCard(
                    title: 'Hoy',
                    note: r != null && r.cached ? 'Sin señal: datos guardados.' : null,
                    items: [
                      TodayItem(HomeArea.facturacion, n(r?.toInvoice), 'para facturar', () => _go('Facturar')),
                      TodayItem(HomeArea.reparto, n(r?.toDeliver), 'para entregar', () => _go('Reparto')),
                      TodayItem(
                        HomeArea.reparto,
                        r?.tripOpen == null
                            ? 'Viaje'
                            : r!.tripOpen!
                            ? 'Viaje abierto'
                            : 'Sin viaje abierto',
                        '',
                        () => _go('Stock'),
                        icon: Icons.local_shipping_outlined,
                      ),
                      TodayItem(
                        HomeArea.herramientas,
                        n(r?.negatives),
                        'en negativo',
                        () => _go('En negativo'),
                        alert: (r?.negatives ?? 0) > 0,
                      ),
                      if (r?.salaryDue != null)
                        TodayItem(
                          HomeArea.plata,
                          pesos(r!.salaryDue!),
                          'tu sueldo, sin pagar',
                          () => _go('Plata del negocio'),
                          alert: true,
                        ),
                    ],
                  ),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Tonos.of(context);
    Widget link(String name, IconData icon, {HomeArea? area, int? badge, VoidCallback? action}) {
      final colors = area == null ? null : AreaColors.of(context, area);
      final selected = _selected == name || (name == 'Stock' && _selected == 'En negativo');
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          selected: selected,
          selectedColor: colors?.texto,
          selectedTileColor: colors?.fondo ?? Theme.of(context).colorScheme.primaryContainer,
          leading: Icon(icon, size: 20, color: colors?.titulo),
          title: Text(name),
          trailing: badge != null && badge > 0
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                  decoration: BoxDecoration(
                    color: colors?.fuerte ?? AppColors.gris,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$badge',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: colors?.fuerte == AppColors.dorado ? AppColors.negro : Colors.white,
                    ),
                  ),
                )
              : null,
          onTap: action ?? () => _go(name),
        ),
      );
    }

    Widget group(String title, HomeArea area) => Padding(
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          letterSpacing: 1,
          fontWeight: FontWeight.w700,
          color: AreaColors.of(context, area).titulo,
        ),
      ),
    );
    final r = _summary;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 56,
        backgroundColor: AppColors.negro,
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
            width: 230,
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(10),
                    children: [
                      link('Inicio', Icons.home_outlined),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.dorado,
                          foregroundColor: AppColors.negro,
                        ),
                        onPressed: _newOrder,
                        icon: const Icon(Icons.add, size: 20),
                        label: const Text('Nuevo pedido', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      group('VENTAS', HomeArea.ventas),
                      link('Pedidos', Icons.receipt_long_outlined, area: HomeArea.ventas),
                      link('Clientes', Icons.people_outline, area: HomeArea.ventas),
                      if (widget.isAdmin) link('Venta especial', Icons.point_of_sale, area: HomeArea.ventas),
                      if (!widget.isAdmin) link('Productos', Icons.inventory_2_outlined, area: HomeArea.ventas),
                      if (!widget.isAdmin)
                        link('Lo que llevamos', Icons.local_shipping_outlined, area: HomeArea.ventas),
                      if (widget.canGeneralCatalog)
                        link('Catálogo general', Icons.storefront_outlined, area: HomeArea.ventas),
                      if (widget.isAdmin) ...[
                        group('REPARTO Y STOCK', HomeArea.reparto),
                        link('Reparto', Icons.route_outlined, area: HomeArea.reparto, badge: r?.toDeliver),
                        link('Stock', Icons.warehouse_outlined, area: HomeArea.reparto),
                        link(
                          'Anotar compra',
                          Icons.add_shopping_cart,
                          area: HomeArea.reparto,
                          action: () async {
                            await openPurchase(context);
                            _loadSummary();
                          },
                        ),
                        group('FACTURACIÓN', HomeArea.facturacion),
                        link('Facturar', Icons.request_quote_outlined, area: HomeArea.facturacion, badge: r?.toInvoice),
                        group('PLATA', HomeArea.plata),
                        link(
                          'Anotar gasto',
                          Icons.receipt_outlined,
                          area: HomeArea.plata,
                          action: () => quickExpense(context),
                        ),
                        link('Plata del negocio', Icons.savings_outlined, area: HomeArea.plata),
                        link('Tablero del mes', Icons.insights, area: HomeArea.plata),
                        link('Saldos', Icons.account_balance_wallet_outlined, area: HomeArea.plata),
                        link('Comisiones', Icons.payments_outlined, area: HomeArea.plata),
                        group('HERRAMIENTAS', HomeArea.herramientas),
                        link('Productos', Icons.inventory_2_outlined, area: HomeArea.herramientas),
                        link('Calculadora', Icons.calculate_outlined, area: HomeArea.herramientas),
                        link('Resumen y estadísticas', Icons.analytics_outlined, area: HomeArea.herramientas),
                      ] else ...[
                        group('MÍO', HomeArea.plata),
                        link('Mis comisiones', Icons.payments_outlined, area: HomeArea.plata),
                        link('Calculadora', Icons.calculate_outlined, area: HomeArea.plata),
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
                    style: TextStyle(color: t.secundario),
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
