import '../orders/order_observation_indicator.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'invoice_detail_page.dart';
import '../../core/desktop_table.dart';
import 'invoicing_desktop_table.dart';
import '../../core/app_config.dart';
import 'invoice_recovery_page.dart';
import 'package:distribuidora_alberdi/core/money_format.dart';
import '../../core/page_switch.dart';
import 'invoiced_orders_page.dart';

class InvoicingPage extends StatefulWidget {
  const InvoicingPage({super.key, this.embedded = false});
  final bool embedded;

  @override
  State<InvoicingPage> createState() => _InvoicingPageState();
}

class _InvoicingPageState extends State<InvoicingPage> {
  /// 0 Para facturar, 1 Realizadas.
  int _vista = 0;
  bool _cargando = true;
  String? _error;

  List<Map<String, dynamic>> _pedidos = [];

  @override
  void initState() {
    super.initState();
    _cargarPedidos();
  }

  Future<void> _cargarPedidos() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final respuesta = await Supabase.instance.client
          .from('pedidos')
          .select('''
            id,
            created_at,
      observacion,
            total,
            tipo_precio,
            estado,
            resultado_entrega,
            facturado,
            fecha_facturacion,
            numero_comprobante,
            clientes (
              nombre_comercio,
              direccion
            ),
            usuarios (
              nombre,
              apellido
            )
          ''')
          .eq('facturado', false)
          .eq('tipo_operacion', 'pedido')
          .order('created_at', ascending: false);

      if (!mounted) return;

      setState(() {
        _pedidos = List<Map<String, dynamic>>.from(respuesta);
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = 'No se pudieron cargar los pedidos.';
        _cargando = false;
      });
    }
  }

  String _formatearPrecio(dynamic valor) => formatoPesos(valor);

  String _formatearFecha(dynamic valor) {
    if (valor == null) return '';

    final fecha = DateTime.tryParse(valor.toString());

    if (fecha == null) return valor.toString();

    final local = fecha.toLocal();

    final dia = local.day.toString().padLeft(2, '0');
    final mes = local.month.toString().padLeft(2, '0');
    final anio = local.year.toString();

    return '$dia/$mes/$anio';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return Column(
        children: [
          if (appConfig.isTesting)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const InvoiceRecoveryPage(),
                  ),
                ),
                icon: const Icon(Icons.history),
                label: const Text('Recuperación de boletas internas'),
              ),
            ),
          Expanded(child: _construirContenido()),
        ],
      );
    }
    // Facturar: "Para facturar" y "Realizadas" en la misma pantalla.
    final vistas = pageSwitch(
      labels: const ['Para facturar', 'Realizadas'],
      icons: const [Icons.request_quote_outlined, Icons.history],
      selected: _vista,
      onChanged: (v) => setState(() => _vista = v),
    );
    if (_vista == 1) {
      return Scaffold(
        appBar: AppBar(title: const Text('Facturar'), bottom: vistas),
        body: const InvoicedOrdersPage(embedded: true),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Facturar'),
        bottom: vistas,
        actions: [
          if (appConfig.isTesting)
            IconButton(
              tooltip: 'Recuperación de boletas internas',
              icon: const Icon(Icons.history),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const InvoiceRecoveryPage()),
              ),
            ),
        ],
      ),
      body: _construirContenido(),
    );
  }

  Widget _construirContenido() {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _cargarPedidos,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    if (useDesktopLayout(context)) {
      return InvoicingDesktopTable(
        orders: _pedidos,
        onRefresh: _cargarPedidos,
        onOpen: (pedido) async {
          await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => InvoiceDetailPage(pedido: pedido),
            ),
          );
          if (mounted) await _cargarPedidos();
        },
      );
    }

    if (_pedidos.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Está todo facturado.\nLos pedidos nuevos aparecen acá para facturarlos.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _cargarPedidos,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _pedidos.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final pedido = _pedidos[index];

          final cliente = pedido['clientes'] as Map<String, dynamic>?;

          final usuario = pedido['usuarios'] as Map<String, dynamic>?;

          final clienteNombre =
              cliente?['nombre_comercio']?.toString() ?? 'Cliente sin nombre';

          final direccion = cliente?['direccion']?.toString() ?? '';

          final vendedorNombre = usuario?['nombre']?.toString() ?? '';

          final vendedorApellido = usuario?['apellido']?.toString() ?? '';

          final vendedor = [
            vendedorNombre,
            vendedorApellido,
          ].where((texto) => texto.isNotEmpty).join(' ');

          return Card(
            child: InkWell(
              onTap: () async {
                await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => InvoiceDetailPage(pedido: pedido),
                  ),
                );

                if (mounted) {
                  await _cargarPedidos();
                }
              },

              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    OrderObservationIndicator(
                      observation: pedido['observacion'],
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            clienteNombre,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (direccion.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(direccion),
                          ],
                          const SizedBox(height: 6),
                          Text(
                            'Fecha: ${_formatearFecha(pedido['created_at'])}',
                          ),
                          if (vendedor.isNotEmpty)
                            Text('Preventista: $vendedor'),
                          Text(
                            'Tipo de precio: ${pedido['tipo_precio']?.toString().toUpperCase() ?? ''}',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),
                    Text(
                      _formatearPrecio(pedido['total']),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
