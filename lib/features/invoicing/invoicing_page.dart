import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'invoice_detail_page.dart';

class InvoicingPage extends StatefulWidget {
  const InvoicingPage({super.key});

  @override
  State<InvoicingPage> createState() => _InvoicingPageState();
}

class _InvoicingPageState extends State<InvoicingPage> {
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

  String _formatearPrecio(dynamic valor) {
    final numero = double.tryParse(valor?.toString() ?? '') ?? 0;
    final entero = numero.round().toString();

    final buffer = StringBuffer();
    int contador = 0;

    for (int i = entero.length - 1; i >= 0; i--) {
      buffer.write(entero[i]);
      contador++;

      if (contador == 3 && i != 0) {
        buffer.write('.');
        contador = 0;
      }
    }

    return '\$${buffer.toString().split('').reversed.join()}';
  }

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Facturación'),
      ),
      body: _construirContenido(),
    );
  }

  Widget _construirContenido() {
    if (_cargando) {
      return const Center(
        child: CircularProgressIndicator(),
      );
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

    if (_pedidos.isEmpty) {
      return const Center(
        child: Text(
          'No hay pedidos pendientes de facturar.',
          style: TextStyle(fontSize: 18),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _cargarPedidos,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _pedidos.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final pedido = _pedidos[index];

          final cliente =
              pedido['clientes'] as Map<String, dynamic>?;

          final usuario =
              pedido['usuarios'] as Map<String, dynamic>?;

          final clienteNombre =
              cliente?['nombre_comercio']?.toString() ??
              'Cliente sin nombre';

          final direccion =
              cliente?['direccion']?.toString() ?? '';

          final vendedorNombre =
              usuario?['nombre']?.toString() ?? '';

          final vendedorApellido =
              usuario?['apellido']?.toString() ?? '';

          final vendedor = [
            vendedorNombre,
            vendedorApellido,
          ].where((texto) => texto.isNotEmpty).join(' ');

          return Card(
  child: InkWell(
      onTap: () async {
  final resultado = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => InvoiceDetailPage(
        pedido: pedido,
      ),
    ),
  );

  if (resultado == true) {
    await _cargarPedidos();
  }
},
    
    child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(
                    Icons.receipt_long_outlined,
                    size: 32,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
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