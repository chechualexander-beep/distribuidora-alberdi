import '../../core/app_config.dart';
import 'package:distribuidora_alberdi/core/app_theme.dart';
import '../../core/desktop_records.dart';
import '../../core/desktop_table.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../clients/client_detail_link.dart';
import 'delivery_date_picker.dart';
import 'manage_order_page.dart';
import 'order_detail_page.dart';
import 'pending_finalizations_page.dart';
import '../stock/product_summary.dart';
import '../stock/stock_home_page.dart' show openPurchase;
import 'day_sales.dart';
import 'package:distribuidora_alberdi/core/money_format.dart';
import '../../core/text_search.dart';

class AdminOrdersPage extends StatefulWidget {
  const AdminOrdersPage({super.key, this.client});

  final SupabaseClient? client;

  @override
  State<AdminOrdersPage> createState() => _AdminOrdersPageState();
}

class _AdminOrdersPageState extends State<AdminOrdersPage> {
  SupabaseClient get _client => widget.client ?? Supabase.instance.client;
  bool _cargando = true;
  String? _error;

  List<Map<String, dynamic>> _pedidos = [];
  List<Map<String, dynamic>> _resumenProductos = [];

  /// El resumen en el formato de la tabla con stock.
  List<SummaryLine> get _lineasResumen => [
    for (final p in _resumenProductos)
      SummaryLine(
        p['producto_id']?.toString(),
        p['nombre']?.toString() ?? 'Producto sin nombre',
        (p['cantidad'] as num?)?.toDouble() ?? 0,
      ),
  ];
  final Set<String> _pedidosSeleccionados = {};
  List<Map<String, dynamic>> _detallesPedidos = [];
  DateTime _fechaSeleccionada = DateTime.now();
  bool _filtrarPorFecha = false;
  bool _mostrarVentaDirecta = false;
  bool _sinProgramar = false;
  String _busquedaReparto = '';
  final TextEditingController _buscador = TextEditingController();
  final Set<String> _expandidos = {};

  /// Tarjeta "Venta del día": lo entregado (preventa) o vendido (venta directa) hoy.
  DaySales? _ventaDia;
  String? _ventaDiaError;

  @override
  void initState() {
    super.initState();
    _cargarPedidos();
  }

  @override
  void dispose() {
    _buscador.dispose();
    super.dispose();
  }

  static String _normalizar(String texto) => sinAcentos(texto);

  List<String> get _palabrasBusqueda => palabrasBusqueda(_busquedaReparto);

  List<Map<String, dynamic>> _detallesDe(String pedidoId) => _detallesPedidos
      .where(
        (d) =>
            d['pedido_id']?.toString() == pedidoId && _cantidadDetalle(d) > 0,
      )
      .toList();

  double _cantidadDetalle(Map<String, dynamic> detalle) {
    final facturada = detalle['cantidad_facturada'];
    return facturada != null
        ? double.tryParse(facturada.toString()) ?? 0
        : double.tryParse(detalle['cantidad']?.toString() ?? '') ?? 0;
  }

  String _textoCantidad(double cantidad) =>
      cantidad % 1 == 0 ? cantidad.toInt().toString() : cantidad.toString();

  String _nombreProducto(Map<String, dynamic> detalle) {
    final producto = detalle['productos'] as Map<String, dynamic>?;
    return producto?['nombre']?.toString() ?? 'Producto';
  }

  bool _productoCoincide(Map<String, dynamic> detalle, List<String> palabras) {
    final producto = detalle['productos'] as Map<String, dynamic>?;
    final texto = _normalizar(
      '${producto?['nombre'] ?? ''} ${producto?['codigo'] ?? ''}',
    );
    return palabras.every(texto.contains);
  }

  /// Pedidos que coinciden con el buscador (cliente, dirección o producto).
  List<Map<String, dynamic>> get _pedidosVisibles {
    final palabras = _palabrasBusqueda;
    if (palabras.isEmpty) return _pedidos;
    return _pedidos.where((pedido) {
      final cliente = pedido['clientes'] as Map<String, dynamic>?;
      final textoCliente = _normalizar(
        '${cliente?['nombre_comercio'] ?? ''} ${cliente?['direccion'] ?? ''}',
      );
      if (palabras.every(textoCliente.contains)) return true;
      return _detallesDe(
        pedido['id'].toString(),
      ).any((d) => _productoCoincide(d, palabras));
    }).toList();
  }

  Widget _buscadorReparto() => TextField(
    controller: _buscador,
    decoration: InputDecoration(
      isDense: true,
      hintText: 'Buscar cliente o producto',
      prefixIcon: const Icon(Icons.search),
      suffixIcon: _busquedaReparto.isEmpty
          ? null
          : IconButton(
              tooltip: 'Borrar búsqueda',
              icon: const Icon(Icons.close),
              onPressed: () {
                _buscador.clear();
                setState(() => _busquedaReparto = '');
              },
            ),
    ),
    onChanged: (valor) => setState(() => _busquedaReparto = valor),
  );

  Widget _tarjetaVentaDia() => DaySalesCard(
    key: ValueKey('venta-dia-$_mostrarVentaDirecta'),
    direct: _mostrarVentaDirecta,
    sales: _ventaDia,
    error: _ventaDiaError,
    pendingCount: _mostrarVentaDirecta ? 0 : _cantidadPedidos,
    pendingTotal: _mostrarVentaDirecta ? 0 : _ventaTotal,
  );

  Future<void> _cargarVentaDia() async {
    final directa = _mostrarVentaDirecta;
    setState(() {
      _ventaDia = null;
      _ventaDiaError = null;
    });
    try {
      final venta = await fetchDaySales(_client, direct: directa);
      if (!mounted || directa != _mostrarVentaDirecta) return;
      setState(() => _ventaDia = venta);
    } catch (_) {
      if (!mounted || directa != _mostrarVentaDirecta) return;
      setState(() => _ventaDiaError = 'No se pudo leer la venta del día.');
    }
  }

  Widget _encabezadoCompacto() {
    final fechaTexto =
        '${_nombreDia(_fechaSeleccionada)} '
        '${_fechaSeleccionada.day.toString().padLeft(2, '0')}/'
        '${_fechaSeleccionada.month.toString().padLeft(2, '0')}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_sinProgramar) ...[_tarjetaVentaDia(), const SizedBox(height: 10)],
        if (_sinProgramar)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Catálogo · Entregas sin programar',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        Row(
          children: [
            if (!_mostrarVentaDirecta && !_sinProgramar) ...[
              _filtrarPorFecha
                  ? InputChip(
                      avatar: const Icon(Icons.calendar_month, size: 18),
                      label: Text(fechaTexto),
                      onPressed: _elegirFecha,
                      onDeleted: _verTodosLosPendientes,
                      deleteButtonTooltipMessage: 'Ver todas las fechas',
                    )
                  : ActionChip(
                      avatar: const Icon(
                        Icons.calendar_month_outlined,
                        size: 18,
                      ),
                      label: const Text('Todas las fechas'),
                      onPressed: _elegirFecha,
                    ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                '$_cantidadPedidos pedidos · ${_formatearPrecio(_ventaTotal)}',
                textAlign: TextAlign.end,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buscadorReparto(),
      ],
    );
  }

  Future<void> _cargarPedidos() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    if (!_sinProgramar) _cargarVentaDia();

    try {
      var consulta = _client
          .from('pedidos')
          .select('''
      id,
      cliente_id,
      fecha_entrega,
      origen,
      tipo_precio,
      created_at,
      estado,
      resultado_entrega,
      motivo_no_entrega,
      total,
      tipo_operacion,
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
          .eq('resultado_entrega', 'pendiente');

      if (_mostrarVentaDirecta) {
        consulta = consulta.eq('tipo_operacion', 'venta_directa');
      } else if (_sinProgramar) {
        consulta = consulta
            .eq('tipo_operacion', 'pedido')
            .eq('origen', 'catalogo')
            .isFilter('fecha_entrega', null)
            .not('estado', 'in', '(cancelado,anulado)');
      } else {
        consulta = consulta
            .eq('tipo_operacion', 'pedido')
            .eq('facturado', true);
      }

      if (_filtrarPorFecha && !_mostrarVentaDirecta && !_sinProgramar) {
        final fechaFiltro =
            '${_fechaSeleccionada.year.toString().padLeft(4, '0')}-'
            '${_fechaSeleccionada.month.toString().padLeft(2, '0')}-'
            '${_fechaSeleccionada.day.toString().padLeft(2, '0')}';

        consulta = consulta.eq('fecha_entrega', fechaFiltro);
      }

      final respuesta = await consulta.order('fecha_entrega', ascending: true);
      final pedidosCargados = List<Map<String, dynamic>>.from(respuesta);

      final idsPedidos = pedidosCargados
          .map((pedido) => pedido['id'])
          .where((id) => id != null)
          .toList();

      final Map<String, Map<String, dynamic>> productosAgrupados = {};

      if (idsPedidos.isNotEmpty) {
        final detallesRespuesta = await _client
            .from('pedido_detalles')
            .select('''
        pedido_id,
producto_id,
cantidad,
cantidad_facturada,
precio_unitario,
productos (
          nombre,
          codigo
        )
        ''')
            .inFilter('pedido_id', idsPedidos);
        _detallesPedidos = List<Map<String, dynamic>>.from(detallesRespuesta);

        for (final detalle in detallesRespuesta) {
          final productoId = detalle['producto_id']?.toString();

          if (productoId == null) continue;

          final producto = detalle['productos'] as Map<String, dynamic>?;

          final cantidadFacturada = detalle['cantidad_facturada'];

          final cantidad = cantidadFacturada != null
              ? double.tryParse(cantidadFacturada.toString()) ?? 0
              : double.tryParse(detalle['cantidad']?.toString() ?? '') ?? 0;

          if (cantidad <= 0) continue;

          if (!productosAgrupados.containsKey(productoId)) {
            productosAgrupados[productoId] = {
              'producto_id': productoId,
              'nombre':
                  producto?['nombre']?.toString() ?? 'Producto sin nombre',
              'codigo': producto?['codigo']?.toString() ?? '',
              'cantidad': 0.0,
            };
          }

          productosAgrupados[productoId]!['cantidad'] =
              (productosAgrupados[productoId]!['cantidad'] as double) +
              cantidad;
        }
      }

      final resumenProductos = productosAgrupados.values.toList();

      resumenProductos.sort(
        (a, b) => a['nombre'].toString().compareTo(b['nombre'].toString()),
      );
      if (!mounted) return;

      setState(() {
        _pedidos = pedidosCargados;
        _resumenProductos = resumenProductos;
        _cargando = false;
      });
    } catch (_) {
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

    if (fecha == null) {
      return valor.toString();
    }

    final local = fecha.toLocal();

    final dia = local.day.toString().padLeft(2, '0');
    final mes = local.month.toString().padLeft(2, '0');
    final anio = local.year.toString();

    final hora = local.hour.toString().padLeft(2, '0');
    final minuto = local.minute.toString().padLeft(2, '0');

    return '$dia/$mes/$anio $hora:$minuto';
  }

  double _totalPedidoParaReparto(Map<String, dynamic> pedido) {
    final facturado = pedido['facturado'] == true;

    if (!facturado) {
      return double.tryParse(pedido['total']?.toString() ?? '') ?? 0;
    }

    final pedidoId = pedido['id']?.toString();

    if (pedidoId == null) return 0;

    double total = 0;

    for (final detalle in _detallesPedidos) {
      if (detalle['pedido_id']?.toString() != pedidoId) {
        continue;
      }

      final cantidadFacturada = detalle['cantidad_facturada'];

      final cantidad = cantidadFacturada != null
          ? double.tryParse(cantidadFacturada.toString()) ?? 0
          : double.tryParse(detalle['cantidad']?.toString() ?? '') ?? 0;

      final precio =
          double.tryParse(detalle['precio_unitario']?.toString() ?? '') ?? 0;

      total += cantidad * precio;
    }

    return total;
  }

  int get _cantidadPedidos {
    return _pedidos.length;
  }

  double get _ventaTotal {
    return _pedidos.fold<double>(0, (total, pedido) {
      return total + _totalPedidoParaReparto(pedido);
    });
  }

  String _nombreDia(DateTime fecha) {
    const dias = [
      'LUNES',
      'MARTES',
      'MIÉRCOLES',
      'JUEVES',
      'VIERNES',
      'SÁBADO',
      'DOMINGO',
    ];

    return dias[fecha.weekday - 1];
  }

  Future<void> _elegirFecha() async {
    final fecha = await pickDeliveryDate(context, selected: _fechaSeleccionada);

    if (!mounted || fecha == null) return;

    setState(() {
      _fechaSeleccionada = fecha;
      _filtrarPorFecha = true;
    });

    await _cargarPedidos();
  }

  Future<void> _verTodosLosPendientes() async {
    setState(() {
      _filtrarPorFecha = false;
    });

    await _cargarPedidos();
  }

  Future<void> _alternarSinProgramar() async {
    setState(() {
      _sinProgramar = !_sinProgramar;
      _pedidosSeleccionados.clear();
    });
    await _cargarPedidos();
  }

  Future<void> _abrirPedido(Map<String, dynamic> pedido) async {
    if (_sinProgramar) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => OrderDetailPage(pedido: pedido, client: _client),
        ),
      );
      if (mounted) await _cargarPedidos();
      return;
    }
    final actualizado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ManageOrderPage(pedido: pedido, client: _client),
      ),
    );
    if (actualizado == true && mounted) await _cargarPedidos();
  }

  /// Compra hecha durante el reparto: el lugar (depósito o vehículo) se elige al anotarla.
  Future<void> _anotarCompra() => openPurchase(context, client: widget.client);

  void _recalcularResumenSeleccionados() {
    final Map<String, Map<String, dynamic>> productosAgrupados = {};

    final detallesFiltrados = _detallesPedidos.where((detalle) {
      final pedidoId = detalle['pedido_id']?.toString();
      return pedidoId != null && _pedidosSeleccionados.contains(pedidoId);
    });

    for (final detalle in detallesFiltrados) {
      final productoId = detalle['producto_id']?.toString();

      if (productoId == null) continue;

      final producto = detalle['productos'] as Map<String, dynamic>?;

      final cantidadFacturada = detalle['cantidad_facturada'];

      final cantidad = cantidadFacturada != null
          ? double.tryParse(cantidadFacturada.toString()) ?? 0
          : double.tryParse(detalle['cantidad']?.toString() ?? '') ?? 0;
      if (cantidad <= 0) continue;

      if (!productosAgrupados.containsKey(productoId)) {
        productosAgrupados[productoId] = {
          'producto_id': productoId,
          'nombre': producto?['nombre']?.toString() ?? 'Producto sin nombre',
          'codigo': producto?['codigo']?.toString() ?? '',
          'cantidad': 0.0,
        };
      }

      productosAgrupados[productoId]!['cantidad'] =
          (productosAgrupados[productoId]!['cantidad'] as double) + cantidad;
    }

    final resumen = productosAgrupados.values.toList();

    resumen.sort(
      (a, b) => a['nombre'].toString().compareTo(b['nombre'].toString()),
    );

    setState(() {
      _resumenProductos = resumen;
    });
  }

  void _seleccionarTodos() {
    setState(() {
      _pedidosSeleccionados
        ..clear()
        ..addAll(
          _pedidos
              .map((pedido) => pedido['id']?.toString())
              .whereType<String>(),
        );
    });

    _recalcularResumenSeleccionados();
  }

  void _limpiarSeleccion() {
    setState(() {
      _pedidosSeleccionados.clear();
    });

    _recalcularResumenSeleccionados();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reparto'),
        actions: [
          IconButton(
            tooltip: 'Anotar compra',
            icon: const Icon(Icons.add_shopping_cart),
            onPressed: _anotarCompra,
          ),
          if (!_mostrarVentaDirecta)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: AppColors.dorado),
              onPressed: _cargando ? null : _alternarSinProgramar,
              child: Text(_sinProgramar ? 'Volver a reparto' : 'Sin programar'),
            ),
          if (appConfig.finalizationV2Enabled)
            IconButton(
              tooltip: 'Solicitudes guardadas / recuperación',
              icon: const Icon(Icons.restore),
              onPressed: () async {
                await Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const PendingFinalizationsPage(),
                  ),
                );
                if (mounted) await _cargarPedidos();
              },
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment<bool>(
                  value: false,
                  icon: Icon(Icons.local_shipping_outlined),
                  label: Text('PREVENTAS'),
                ),
                ButtonSegment<bool>(
                  value: true,
                  icon: Icon(Icons.point_of_sale_outlined),
                  label: Text('VENTA DIRECTA'),
                ),
              ],
              selected: {_mostrarVentaDirecta},
              onSelectionChanged: (seleccion) async {
                setState(() {
                  _mostrarVentaDirecta = seleccion.first;
                  _sinProgramar = false;

                  if (_mostrarVentaDirecta) {
                    _filtrarPorFecha = false;
                  }

                  _pedidosSeleccionados.clear();
                });

                await _cargarPedidos();
              },
            ),
          ),
        ),
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
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 60),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _cargarPedidos,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (_sinProgramar && _pedidos.isEmpty) {
      return const Center(
        child: Text('Todos los pedidos del catálogo ya tienen fecha de entrega.'),
      );
    }
    if (_pedidos.isEmpty) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: _encabezadoCompacto(),
          ),
          Expanded(
            child: Center(
              child: Text(
                _mostrarVentaDirecta
                    ? 'No hay ventas directas pendientes de entregar.\nLo vendido hoy está en la tarjeta de arriba.'
                    : _filtrarPorFecha
                    ? 'No hay entregas para esta fecha.\nTocá la fecha para elegir otra, o la X para ver todas.'
                    : 'No hay preventas para entregar.\nAparecen acá cuando se facturan.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ),
        ],
      );
    }

    if (useDesktopLayout(context)) {
      return Column(
        children: [
          if (!_sinProgramar)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: _tarjetaVentaDia(),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  _mostrarVentaDirecta
                      ? 'Ventas directas pendientes'
                      : _sinProgramar
                      ? 'Catálogo · Entregas sin programar'
                      : _filtrarPorFecha
                      ? 'Entregas: ${_formatearFecha(_fechaSeleccionada.toIso8601String())}'
                      : 'Preventas pendientes',
                ),
                if (!_mostrarVentaDirecta && !_sinProgramar)
                  OutlinedButton.icon(
                    onPressed: _filtrarPorFecha
                        ? _verTodosLosPendientes
                        : _elegirFecha,
                    icon: const Icon(Icons.calendar_month, size: 18),
                    label: Text(
                      _filtrarPorFecha ? 'Ver todos' : 'Elegir fecha',
                    ),
                  ),
                IconButton(
                  tooltip: 'Actualizar pedidos',
                  onPressed: _cargarPedidos,
                  icon: const Icon(Icons.refresh),
                ),
                SizedBox(width: 280, child: _buscadorReparto()),
                Text(
                  '$_cantidadPedidos pedidos · ${_formatearPrecio(_ventaTotal)}',
                ),
                OutlinedButton(
                  onPressed: _seleccionarTodos,
                  child: const Text('Seleccionar todos'),
                ),
                TextButton(
                  onPressed: _limpiarSeleccion,
                  child: const Text('Limpiar selección'),
                ),
                OutlinedButton.icon(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(
                        _pedidosSeleccionados.isEmpty
                            ? 'Productos de todos los pedidos (${_pedidos.length})'
                            : 'Productos de ${_pedidosSeleccionados.length} pedidos',
                      ),
                      content: SizedBox(
                        width: 700,
                        height: 520,
                        child: SingleChildScrollView(
                          child: ProductSummaryTable(lines: _lineasResumen, client: widget.client),
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cerrar'),
                        ),
                      ],
                    ),
                  ),
                  icon: const Icon(Icons.inventory_2_outlined, size: 18),
                  label: const Text('Resumen de productos'),
                ),
              ],
            ),
          ),
          Expanded(
            child: DesktopRecords(
              records: _pedidosVisibles,
              leading: (p) => Checkbox(
                value: _pedidosSeleccionados.contains(p['id'].toString()),
                onChanged: (v) {
                  setState(() {
                    if (v == true) {
                      _pedidosSeleccionados.add(p['id'].toString());
                    } else {
                      _pedidosSeleccionados.remove(p['id'].toString());
                    }
                  });
                  _recalcularResumenSeleccionados();
                },
              ),
              fields: [
                DesktopField(
                  'Cliente',
                  (pedido) => SizedBox(
                    width: 260,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            recordClient(pedido),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        ClientDetailLink(
                          clientId: pedido['cliente_id']?.toString(),
                          client: _client,
                        ),
                      ],
                    ),
                  ),
                  width: 260,
                ),
                DesktopField(
                  'Dirección',
                  (r) => (r['clientes'] as Map?)?['direccion'],
                  width: 200,
                ),
                DesktopField('Preventista', recordSeller),
                if (_sinProgramar)
                  DesktopField(
                    'Programación',
                    (_) => 'Sin programar',
                    width: 120,
                  ),
                DesktopField(
                  'Entrega',
                  (r) => r['resultado_entrega'],
                  width: 110,
                ),
                DesktopField(
                  'Facturación',
                  (r) => r['facturado'] == true ? 'Facturado' : 'Pendiente',
                  width: 110,
                ),
                DesktopField(
                  'Total',
                  (r) => desktopMoney(_totalPedidoParaReparto(r)),
                  numeric: true,
                  width: 120,
                ),
                DesktopField('Observación', recordObservation, width: 180),
              ],
              actions: _sinProgramar
                  ? (pedido) => TextButton(
                      onPressed: () => _abrirPedido(pedido),
                      child: const Text('Programar'),
                    )
                  : null,
              onOpen: _abrirPedido,
            ),
          ),
        ],
      );
    }
    final visibles = _pedidosVisibles;
    final palabras = _palabrasBusqueda;
    Widget itemAt(BuildContext context, int index) {
          if (index == 0) return _encabezadoCompacto();
          if (index == 1) {
            return Card(
              child: ExpansionTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: const Text(
                  'RESUMEN DE PRODUCTOS',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  '${_pedidosSeleccionados.length} de ${_pedidos.length} pedidos seleccionados',
                ),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _seleccionarTodos,
                          child: const Text('SELECCIONAR TODOS'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _limpiarSeleccion,
                          child: const Text('LIMPIAR'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ProductSummaryTable(
                    lines: _lineasResumen,
                    client: widget.client,
                  ),
                ],
              ),
            );
          }

          if (visibles.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Ningún pedido coincide con la búsqueda.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
            );
          }
          final pedido = visibles[index - 2];
          final cliente = pedido['clientes'] as Map<String, dynamic>?;
          final usuario = pedido['usuarios'] as Map<String, dynamic>?;
          final clienteNombre =
              cliente?['nombre_comercio']?.toString() ?? 'Cliente sin nombre';
          final direccion = cliente?['direccion']?.toString() ?? '';
          final vendedor = [
            usuario?['nombre']?.toString() ?? '',
            usuario?['apellido']?.toString() ?? '',
          ].where((texto) => texto.isNotEmpty).join(' ');
          final motivo = pedido['motivo_no_entrega']?.toString() ?? '';
          final pedidoId = pedido['id'].toString();
          final seleccionado = _pedidosSeleccionados.contains(pedidoId);
          final facturado = pedido['facturado'] == true;
          final numeroComprobante =
              pedido['numero_comprobante']?.toString() ?? '';
          final esVentaDirecta =
              pedido['tipo_operacion']?.toString() == 'venta_directa';
          final detalles = _detallesDe(pedidoId);
          final coincidentes = palabras.isEmpty
              ? const <Map<String, dynamic>>[]
              : detalles.where((d) => _productoCoincide(d, palabras)).toList();
          final expandido = _expandidos.contains(pedidoId);

          Widget etiqueta(String texto, Color color) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              border: Border.all(color: color, width: 1.5),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              texto,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          );

          return Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Checkbox(
                        value: seleccionado,
                        onChanged: (valor) {
                          setState(() {
                            if (valor == true) {
                              _pedidosSeleccionados.add(pedidoId);
                            } else {
                              _pedidosSeleccionados.remove(pedidoId);
                            }
                          });
                          _recalcularResumenSeleccionados();
                        },
                      ),
                      Expanded(
                        child: Text(
                          clienteNombre,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      ClientDetailLink(
                        clientId: pedido['cliente_id']?.toString(),
                        client: _client,
                      ),
                      Text(
                        _formatearPrecio(_totalPedidoParaReparto(pedido)),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (direccion.isNotEmpty) Text(direccion),
                        Text(
                          [
                            _formatearFecha(pedido['created_at']),
                            if (vendedor.isNotEmpty) vendedor,
                          ].join(' · '),
                          style: const TextStyle(color: AppColors.gris),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            if (esVentaDirecta)
                              etiqueta('VENTA DIRECTA', AppColors.negro),
                            facturado
                                ? etiqueta(
                                    numeroComprobante.isEmpty
                                        ? 'FACTURADO'
                                        : 'FACTURADO N° $numeroComprobante',
                                    AppColors.verde,
                                  )
                                : etiqueta('NO FACTURADO', AppColors.naranja),
                          ],
                        ),
                        if (motivo.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text('Motivo: $motivo'),
                        ],
                        if (coincidentes.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          for (final d in coincidentes)
                            Text(
                              '${_textoCantidad(_cantidadDetalle(d))} × ${_nombreProducto(d)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.doradoOscuro,
                              ),
                            ),
                        ],
                        if (expandido) ...[
                          const Divider(),
                          if (detalles.isEmpty)
                            const Text('Sin productos para entregar.'),
                          for (final d in detalles)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Text(
                                '${_textoCantidad(_cantidadDetalle(d))} × ${_nombreProducto(d)}',
                                style: const TextStyle(fontSize: 15),
                              ),
                            ),
                        ],
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: TextButton.icon(
                                onPressed: () => setState(() {
                                  if (!_expandidos.remove(pedidoId)) {
                                    _expandidos.add(pedidoId);
                                  }
                                }),
                                icon: Icon(
                                  expandido
                                      ? Icons.expand_less
                                      : Icons.list_alt_outlined,
                                ),
                                label: Text(
                                  expandido
                                      ? 'Ocultar productos'
                                      : 'Ver productos (${detalles.length})',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () => _abrirPedido(pedido),
                                icon: const Icon(Icons.edit_outlined),
                                label: Text(
                                  _sinProgramar ? 'PROGRAMAR' : 'GESTIONAR',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
    }

    return RefreshIndicator(
      onRefresh: _cargarPedidos,
      child: CustomScrollView(
        slivers: [
          // El encabezado y el resumen quedan siempre armados (no se rehacen al desplazarse): con muchos
          // pedidos el resumen abierto es muy alto y, dentro de una lista perezosa, la hacía trabar.
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [itemAt(context, 0), const SizedBox(height: 8), itemAt(context, 1)],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            sliver: SliverList.separated(
              itemCount: visibles.isEmpty ? 1 : visibles.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) => itemAt(context, i + 2),
            ),
          ),
        ],
      ),
    );
  }
}
