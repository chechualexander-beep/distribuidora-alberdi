import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'invoice_detail_page.dart';

class InvoicedOrdersPage extends StatefulWidget {
  const InvoicedOrdersPage({super.key});

  @override
  State<InvoicedOrdersPage> createState() => _InvoicedOrdersPageState();
}

class _InvoicedOrdersPageState extends State<InvoicedOrdersPage> {
  bool _cargando = true;
  String? _error;

  List<Map<String, dynamic>> _pedidos = [];
  DateTime? _fechaSeleccionada;
  String _filtroCliente = '';
  String _filtroPreventista = '';

  @override
  void initState() {
    super.initState();
    _cargarFacturas();
  }

  Future<void> _cargarFacturas() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final respuesta = await Supabase.instance.client
          .from('pedidos')
          .select('''
            id,
            total,
            tipo_precio,
            fecha_facturacion,
            numero_comprobante,
            pedido_detalles (
  cantidad,
  cantidad_facturada,
  precio_unitario
),
            clientes (
              nombre_comercio,
              direccion
            ),
            usuarios (
              nombre,
              apellido
            )
          ''')
          .eq('facturado', true)
          .order('fecha_facturacion', ascending: false);

      if (!mounted) return;

      setState(() {
        _pedidos = List<Map<String, dynamic>>.from(respuesta);
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = 'No se pudieron cargar las facturas.';
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
  bool _esMismaFecha(dynamic valor, DateTime fechaSeleccionada) {
  if (valor == null) return false;

  final fecha = DateTime.tryParse(valor.toString());
  if (fecha == null) return false;

  final local = fecha.toLocal();

  return local.year == fechaSeleccionada.year &&
      local.month == fechaSeleccionada.month &&
      local.day == fechaSeleccionada.day;
}

Future<void> _seleccionarFecha() async {
  final ahora = DateTime.now();

  final fecha = await showDatePicker(
    context: context,
    initialDate: _fechaSeleccionada ?? ahora,
    firstDate: DateTime(2020),
    lastDate: DateTime(ahora.year + 1),
    locale: const Locale('es', 'AR'),
  );

  if (fecha == null || !mounted) return;

  setState(() {
    _fechaSeleccionada = fecha;
  });
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Facturas realizadas'),
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
              onPressed: _cargarFacturas,
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
          'No hay facturas realizadas.',
          style: TextStyle(fontSize: 18),
        ),
      );
    }

    final pedidosFiltrados = _pedidos.where((pedido) {
  final cumpleFecha =
      _fechaSeleccionada == null ||
      _esMismaFecha(
        pedido['fecha_facturacion'],
        _fechaSeleccionada!,
      );

  final cliente =
      pedido['clientes'] as Map<String, dynamic>?;

  final nombreCliente =
      cliente?['nombre_comercio']
              ?.toString()
              .toLowerCase() ??
          '';

  final cumpleCliente =
      _filtroCliente.isEmpty ||
      nombreCliente.contains(
        _filtroCliente.toLowerCase(),
      );

  final usuario =
      pedido['usuarios'] as Map<String, dynamic>?;

  final nombrePreventista = [
    usuario?['nombre']?.toString() ?? '',
    usuario?['apellido']?.toString() ?? '',
  ]
      .where((texto) => texto.isNotEmpty)
      .join(' ')
      .toLowerCase();

  final cumplePreventista =
      _filtroPreventista.isEmpty ||
      nombrePreventista.contains(
        _filtroPreventista.toLowerCase(),
      );

  return cumpleFecha &&
      cumpleCliente &&
      cumplePreventista;
}).toList();

return Column(
  children: [
    Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
  children: [
    OutlinedButton.icon(
      onPressed: _seleccionarFecha,
      icon: const Icon(Icons.calendar_month_outlined),
      label: Text(
        _fechaSeleccionada == null
            ? 'Todas las fechas'
            : _formatearFecha(_fechaSeleccionada),
      ),
    ),
    if (_fechaSeleccionada != null) ...[
      const SizedBox(width: 8),
      IconButton(
        tooltip: 'Quitar filtro de fecha',
        onPressed: () {
          setState(() {
            _fechaSeleccionada = null;
          });
        },
        icon: const Icon(Icons.close),
      ),
    ],
    const SizedBox(width: 16),
    Expanded(
      child: TextField(
        decoration: const InputDecoration(
          hintText: 'Buscar cliente...',
          prefixIcon: Icon(Icons.search),
          border: OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: (valor) {
          setState(() {
            _filtroCliente = valor.trim();
          });
        },
      ),
    ),
    const SizedBox(width: 12),
Expanded(
  child: TextField(
    decoration: const InputDecoration(
      hintText: 'Buscar preventista...',
      prefixIcon: Icon(Icons.person_search_outlined),
      border: OutlineInputBorder(),
      isDense: true,
    ),
    onChanged: (valor) {
      setState(() {
        _filtroPreventista = valor.trim();
      });
    },
  ),
),
  ],
)
    ),
    Expanded(
      child: RefreshIndicator(
        onRefresh: _cargarFacturas,
        child: pedidosFiltrados.isEmpty
            ? ListView(
                padding: const EdgeInsets.all(24),
                children: const [
                  Center(
                    child: Text(
                      'No hay facturas para la fecha seleccionada.',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: pedidosFiltrados.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final pedido = pedidosFiltrados[index];

                  final cliente =
                      pedido['clientes'] as Map<String, dynamic>?;

                  final usuario =
                      pedido['usuarios'] as Map<String, dynamic>?;

                  final nombreCliente =
                      cliente?['nombre_comercio']?.toString() ??
                          'Cliente sin nombre';

                  final direccion =
                      cliente?['direccion']?.toString() ?? '';

                  final nombre =
                      usuario?['nombre']?.toString() ?? '';
                  final apellido =
                      usuario?['apellido']?.toString() ?? '';

                  final preventista = [
                    nombre,
                    apellido,
                  ].where((texto) => texto.isNotEmpty).join(' ');

                  final comprobante =
                      pedido['numero_comprobante']?.toString() ?? '';

                  return Card(
                    child: InkWell(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => InvoiceDetailPage(
                              pedido: pedido,
                              soloLectura: true,
                            ),
                          ),
                        );
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
                                    nombreCliente,
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
                                    'Factura: ${_formatearFecha(pedido['fecha_facturacion'])}',
                                  ),
                                  if (comprobante.isNotEmpty)
                                    Text(
                                      'Comprobante: $comprobante',
                                    ),
                                  if (preventista.isNotEmpty)
                                    Text(
                                      'Preventista: $preventista',
                                    ),
                                  Text(
                                    'Tipo de precio: ${pedido['tipo_precio']?.toString().toUpperCase() ?? ''}',
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Text(
                              _formatearPrecio(
                                (pedido['pedido_detalles']
                                            as List<dynamic>? ??
                                        [])
                                    .fold<double>(
                                  0,
                                  (suma, detalle) {
                                    final cantidad =
                                        double.tryParse(
                                              detalle[
                                                          'cantidad_facturada']
                                                      ?.toString() ??
                                                  '',
                                            ) ??
                                            double.tryParse(
                                              detalle['cantidad']
                                                      ?.toString() ??
                                                  '0',
                                            ) ??
                                            0;

                                    final precio =
                                        double.tryParse(
                                              detalle['precio_unitario']
                                                      ?.toString() ??
                                                  '',
                                            ) ??
                                            0;

                                    return suma +
                                        (cantidad * precio);
                                  },
                                ),
                              ),
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
      ),
    ),
  ],
);
  }
}