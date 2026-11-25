import '../../core/app_theme.dart';
import '../../core/desktop_records.dart';
import '../../core/desktop_table.dart';
import '../products/product_photo.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'order_summary_page.dart';
import 'delivery_date_picker.dart';
import '../../core/offline_queries.dart';
import '../../core/pending_orders.dart';
import '../stock/stock_data.dart';
import 'package:distribuidora_alberdi/core/money_format.dart';
import '../../core/text_search.dart';
import 'order_client_picker.dart';
import '../products/product_price_card.dart';
import '../calculator/calculator_data.dart';
import '../calculator/calculator_page.dart';

/// Lo que se manda al resumen del pedido (para pruebas).
typedef OrderDraft = ({
  Map<String, dynamic> cliente,
  Map<String, int> cantidades,
  Map<String, double> precios,
  Map<String, String> listas,
});

class OrderProductsPage extends StatefulWidget {
  /// Null: pedido armado sin cliente; se elige o se crea al final.
  final Map<String, dynamic>? cliente;
  final DateTime? fechaEntrega;
  final String tipoOperacion;

  final Map<String, int>? cantidadesIniciales;
  final Map<String, double>? preciosIniciales;
  final Map<String, String>? tiposPrecioIniciales;
  final String? pedidoId;
  final String? observacionInicial;
  final String? tipoPrecioInicial;
  final SupabaseClient? client;

  /// Para pruebas: productos ya cargados, elección de cliente y resumen.
  final List<Map<String, dynamic>>? productosIniciales;

  /// Solo para pruebas: lo que lleva el vehículo (venta directa con el viaje abierto).
  final VehicleStock? vehiculoInicial;
  final Future<Map<String, dynamic>?> Function(BuildContext context)?
  elegirCliente;
  final void Function(OrderDraft pedido)? abrirResumen;

  const OrderProductsPage({
    super.key,
    this.cliente,
    this.fechaEntrega,
    required this.tipoOperacion,
    this.cantidadesIniciales,
    this.preciosIniciales,
    this.tiposPrecioIniciales,
    this.pedidoId,
    this.observacionInicial,
    this.tipoPrecioInicial,
    this.client,
    this.productosIniciales,
    this.vehiculoInicial,
    this.elegirCliente,
    this.abrirResumen,
  });

  @override
  State<OrderProductsPage> createState() => _OrderProductsPageState();
}

class _OrderProductsPageState extends State<OrderProductsPage> {
  bool _cargando = true;
  String? _error;

  List<Map<String, dynamic>> _productos = [];

  String _busqueda = '';
  String _tipoPrecio = 'normal';
  late DateTime? _fechaEntrega = widget.fechaEntrega;
  SupabaseClient get _client => widget.client ?? Supabase.instance.client;
  late Map<String, dynamic>? _cliente = widget.cliente;

  final Map<String, int> _cantidades = {};

  // Venta directa con un viaje abierto: se ofrece lo que lleva el vehículo.
  VehicleStock? _vehiculo;
  /// Venta directa con el viaje abierto: qué productos se ven sin buscar.
  _Vista _vista = _Vista.libre;
  bool _avisoNoOfrecido = false;

  /// Lo que el cliente compró la última vez (producto → cantidad).
  Map<String, int> _ultimaCompra = const {};
  final Map<String, double> _preciosFijados = {};
  final Map<String, String> _tiposPrecioFijados = {};

  @override
  void initState() {
    super.initState();

    final tipoHabitual =
        widget.tipoPrecioInicial ??
        _cliente?['tipo_precio_habitual']?.toString();

    if (tipoHabitual == 'normal' ||
        tipoHabitual == 'promo' ||
        tipoHabitual == 'interior') {
      _tipoPrecio = tipoHabitual!;
    }
    if (widget.cantidadesIniciales != null) {
      _cantidades.addAll(widget.cantidadesIniciales!);
    }

    if (widget.preciosIniciales != null) {
      _preciosFijados.addAll(widget.preciosIniciales!);
    }

    if (widget.tiposPrecioIniciales != null) {
      _tiposPrecioFijados.addAll(widget.tiposPrecioIniciales!);
    }

    if (widget.productosIniciales != null) {
      _productos = List<Map<String, dynamic>>.from(widget.productosIniciales!);
      _cargando = false;
    } else {
      _cargarProductos();
    }
    if (widget.vehiculoInicial != null) {
      if (widget.vehiculoInicial!.tripOpen && widget.vehiculoInicial!.lines.isNotEmpty) _vehiculo = widget.vehiculoInicial;
    } else if (widget.tipoOperacion == 'venta_directa' && widget.pedidoId == null) {
      _cargarVehiculo();
      if (_cliente != null) _cargarUltimaCompra();
    }
  }

  Future<void> _cargarVehiculo() async {
    try {
      final vehiculo = await fetchVehicleStock(_client);
      if (!mounted || !vehiculo.tripOpen || vehiculo.lines.isEmpty) return;
      setState(() => _vehiculo = vehiculo);
    } catch (_) {}
  }

  Future<void> _cargarUltimaCompra() async {
    final clienteId = _cliente?['id']?.toString();
    if (clienteId == null || PendingOrders.instance.isPendingClient(clienteId)) return;
    try {
      final ultimo = await _client
          .from('pedidos')
          .select('id')
          .eq('cliente_id', clienteId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (ultimo == null) return;
      final detalles = await _client
          .from('pedido_detalles')
          .select('producto_id,cantidad')
          .eq('pedido_id', ultimo['id']);
      final cantidades = <String, int>{};
      for (final d in List<Map<String, dynamic>>.from(detalles)) {
        final q = num.tryParse(d['cantidad']?.toString() ?? '')?.round() ?? 0;
        if (q > 0) cantidades[d['producto_id'].toString()] = q;
      }
      if (mounted) setState(() => _ultimaCompra = cantidades);
    } catch (_) {}
  }

  bool get _modoVehiculo => _vehiculo != null && _vista != _Vista.todo;

  /// Arriba y sin dueño: se puede vender.
  bool _esLibre(Map<String, dynamic> p) => (_vehiculo?.lines[p['id'].toString()]?.available ?? 0) > 0;

  /// En el vehículo (o por cargar) pero todo reservado para entregas.
  bool _esReservado(Map<String, dynamic> p) {
    final l = _vehiculo?.lines[p['id'].toString()];
    return l != null && l.available <= 0 && l.reparto > 0;
  }

  /// Lo que queda en el vehículo descontando lo que ya está en esta venta.
  double? _quedanEnVehiculo(Map<String, dynamic> producto) {
    final linea = _vehiculo?.lines[producto['id'].toString()];
    if (linea == null) return null;
    return linea.available - _cantidadProducto(producto);
  }

  /// "Vehículo: quedan 3 · 2 para entregar", "Vehículo: reservado para entregas".
  String _textoVehiculo(Map<String, dynamic> producto) {
    final quedan = _quedanEnVehiculo(producto)!;
    final linea = _vehiculo!.lines[producto['id'].toString()]!;
    if (quedan <= 0) {
      return linea.available <= 0 && linea.reparto > 0 ? 'Vehículo: reservado para entregas' : 'Vehículo: no queda';
    }
    return 'Vehículo: quedan ${formatQty(quedan)}${linea.reparto > 0 ? ' · ${formatQty(linea.reparto)} para entregar' : ''}';
  }

  /// Productos del vehículo con algo para vender que no están en la venta.
  List<String> get _noOfrecidos => [
    for (final p in _productos)
      if ((_vehiculo?.lines[p['id'].toString()]?.available ?? 0) > 0 && _cantidadProducto(p) == 0)
        p['nombre']?.toString() ?? 'Producto',
  ];

  Future<void> _cargarProductos() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final respuesta = await consultarProductosParaPedido(_client);

      if (!mounted) return;

      setState(() {
        _productos = List<Map<String, dynamic>>.from(respuesta);
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _error = 'No se pudieron cargar los productos.';
        _cargando = false;
      });
    }
  }

  double _precioActual(Map<String, dynamic> producto) =>
      _precioDeLista(producto, _tipoPrecio);

  double _precioDeLista(Map<String, dynamic> producto, String lista) {
    dynamic valor;

    switch (lista) {
      case 'promo':
        valor = producto['precio_promo'];
        break;
      case 'interior':
        valor = producto['precio_interior'];
        break;
      default:
        valor = producto['precio_normal'];
    }

    return double.tryParse(valor?.toString() ?? '') ?? 0;
  }

  int _cantidadProducto(Map<String, dynamic> producto) {
    final id = producto['id'].toString();
    return _cantidades[id] ?? 0;
  }

  double _precioUsado(Map<String, dynamic> producto) {
    final id = producto['id'].toString();

    if (_preciosFijados.containsKey(id)) {
      return _preciosFijados[id]!;
    }

    return _precioActual(producto);
  }

  void _sumarProducto(Map<String, dynamic> producto) {
    final id = producto['id'].toString();

    setState(() {
      final cantidadActual = _cantidades[id] ?? 0;

      if (cantidadActual == 0) {
        _preciosFijados[id] = _precioActual(producto);
        _tiposPrecioFijados[id] = _tipoPrecio;
      }

      _cantidades[id] = cantidadActual + 1;
    });
  }

  void _restarProducto(Map<String, dynamic> producto) {
    final id = producto['id'].toString();
    final cantidadActual = _cantidades[id] ?? 0;

    if (cantidadActual <= 0) return;

    setState(() {
      if (cantidadActual == 1) {
        _cantidades.remove(id);
        _preciosFijados.remove(id);
        _tiposPrecioFijados.remove(id);
      } else {
        _cantidades[id] = cantidadActual - 1;
      }
    });
  }

  int get _totalUnidades {
    return _cantidades.values.fold(0, (total, cantidad) => total + cantidad);
  }

  double get _totalPedido {
    double total = 0;

    for (final producto in _productos) {
      final cantidad = _cantidadProducto(producto);

      if (cantidad > 0) {
        total += _precioUsado(producto) * cantidad;
      }
    }

    return total;
  }

  String _formatearPrecio(double valor) => formatoPesos(valor);

  /// Imagen con el precio que se ve en la fila (el de su lista).
  PriceCardData _tarjetaPrecio(Map<String, dynamic> producto) => PriceCardData(
    nombre: producto['nombre']?.toString() ?? 'Producto',
    detalle: producto['descripcion']?.toString(),
    precio: _precioUsado(producto),
    lista: _tiposPrecioFijados[producto['id'].toString()] ?? _tipoPrecio,
  );

  Future<void> _elegirFechaEntrega() async {
    final fecha = await pickDeliveryDate(context, selected: _fechaEntrega);
    if (mounted && fecha != null) setState(() => _fechaEntrega = fecha);
  }

  Future<void> _verPedido() async {
    if (_vehiculo != null && !_avisoNoOfrecido) {
      final faltan = _noOfrecidos;
      if (faltan.isNotEmpty) {
        _avisoNoOfrecido = true;
        final seguir = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            icon: const Icon(Icons.lightbulb_outline, size: 40),
            title: const Text('¿Ofreciste todo?'),
            content: SingleChildScrollView(
              child: Text(
                'Del vehículo no ofreciste:\n'
                '${faltan.take(20).map((n) => '• $n').join('\n')}'
                '${faltan.length > 20 ? '\n... y ${faltan.length - 20} más' : ''}',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Volver a la lista'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Seguir'),
              ),
            ],
          ),
        );
        if (seguir != true || !mounted) return;
      }
    }
    final fechaEntrega = _fechaEntrega;

    if (fechaEntrega == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Seleccioná una fecha de entrega antes de continuar.'),
        ),
      );
      return;
    }
    if (widget.pedidoId != null &&
        widget.fechaEntrega == null &&
        _cantidades.keys.any((id) => !_productos.any((p) => p['id'] == id))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Hay productos del pedido que ya no están disponibles para editar. Podés programar la entrega desde el detalle.',
          ),
        ),
      );
      return;
    }

    if (_cliente == null) {
      final asignado = await _asignarCliente();
      if (!asignado || !mounted) return;
    }
    final cliente = _cliente!;
    if (widget.abrirResumen != null) {
      widget.abrirResumen!((
        cliente: cliente,
        cantidades: Map<String, int>.from(_cantidades),
        precios: Map<String, double>.from(_preciosFijados),
        listas: Map<String, String>.from(_tiposPrecioFijados),
      ));
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OrderSummaryPage(
          fechaEntrega: fechaEntrega,
          cliente: cliente,
          tipoOperacion: widget.tipoOperacion,
          productos: _productos,
          cantidades: Map<String, int>.from(_cantidades),
          tipoPrecio: _tipoPrecio,
          preciosFijados: Map<String, double>.from(_preciosFijados),
          tiposPrecioFijados: Map<String, String>.from(_tiposPrecioFijados),
          pedidoId: widget.pedidoId,
          observacionInicial: widget.observacionInicial,
          client: _client,
        ),
      ),
    );
  }

  /// Pedido armado sin cliente: lo elige o lo crea ahora. Si su lista
  /// habitual es otra, ofrece pasar los productos a esa lista.
  Future<bool> _asignarCliente() async {
    final elegido = widget.elegirCliente != null
        ? await widget.elegirCliente!(context)
        : await pickOrderClient(context, client: widget.client);
    if (elegido == null || !mounted) return false;

    var deuda = 0.0;
    final clienteId = elegido['id']?.toString();
    if (widget.elegirCliente == null && clienteId != null) {
      try {
        final saldo = await consultarSaldoResumen(_client, clienteId);
        deuda =
            double.tryParse(saldo?['saldo_pendiente']?.toString() ?? '') ?? 0;
      } catch (_) {}
      if (!mounted) return false;
    }

    final habitual = elegido['tipo_precio_habitual']?.toString();
    final otraLista =
        {'normal', 'promo', 'interior'}.contains(habitual) &&
        _cantidades.keys.any((id) => _tiposPrecioFijados[id] != habitual);
    final lista = habitual ?? 'normal';

    if (deuda > 0 || otraLista) {
      final nombre = elegido['nombre_comercio']?.toString() ?? 'Cliente';
      final pasar = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text(nombre),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (deuda > 0) ...[
                Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: AppColors.naranja),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tiene saldo pendiente: ${formatoPesos(deuda)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                if (otraLista) const SizedBox(height: 14),
              ],
              if (otraLista)
                Text(
                  'Su lista habitual es ${_nombreLista(lista)}. '
                  '¿Pasar todos los productos del pedido a lista '
                  '${_nombreLista(lista)}?',
                ),
            ],
          ),
          actions: otraLista
              ? [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Mantener precios'),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: colorLista(lista),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => Navigator.pop(context, true),
                    child: Text('Pasar a ${_nombreLista(lista)}'),
                  ),
                ]
              : [
                  FilledButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Seguir'),
                  ),
                ],
        ),
      );
      if (!mounted) return false;
      if (pasar == true) _pasarALista(lista);
    }

    setState(() => _cliente = elegido);
    return true;
  }

  void _pasarALista(String lista) {
    setState(() {
      _tipoPrecio = lista;
      for (final id in _cantidades.keys) {
        final producto = _productos.where((p) => p['id'].toString() == id);
        if (producto.isEmpty) continue;
        _preciosFijados[id] = _precioDeLista(producto.first, lista);
        _tiposPrecioFijados[id] = lista;
      }
    });
  }

  Future<void> _confirmarSalida() async {
    final salir = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Salir del pedido?'),
        content: Text(
          'Se pierden los $_totalUnidades productos cargados.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Seguir cargando'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.rojo),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Salir'),
          ),
        ],
      ),
    );
    if (salir == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: widget.cliente != null || _totalUnidades == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmarSalida();
      },
      child: _pantalla(context),
    );
  }

  Widget _pantalla(BuildContext context) {
    return Scaffold(
      appBar: _barraLista(),
      body: Column(
        children: [
          if (widget.pedidoId != null && widget.fechaEntrega == null)
            ListTile(
              leading: const Icon(Icons.calendar_today_outlined),
              title: Text(
                _fechaEntrega == null
                    ? 'Entrega sin programar'
                    : MaterialLocalizations.of(
                        context,
                      ).formatCompactDate(_fechaEntrega!),
              ),
              trailing: TextButton(
                onPressed: _elegirFechaEntrega,
                child: Text(
                  _fechaEntrega == null ? 'Elegir fecha' : 'Cambiar fecha',
                ),
              ),
            ),
          Expanded(child: _construirContenido()),
        ],
      ),
      bottomNavigationBar: _totalUnidades > 0
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: colorLista(_tipoPrecio),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _verPedido,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '$_totalUnidades unidades',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        Text(
                          _formatearPrecio(_totalPedido),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 16),
                        const Text(
                          'VER PEDIDO',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          : null,
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
                onPressed: _cargarProductos,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }
    final texto = sinAcentos(_busqueda);


    final productosFiltrados = _productos.where((producto) {


      // Sin buscar: "Para vender" muestra solo lo libre; "Reservado", lo que ya tiene dueño. Lo que ya está en
      // esta venta se ve siempre, y con el buscador se encuentra cualquier producto.
      if (_modoVehiculo && texto.isEmpty && _cantidadProducto(producto) == 0) {
        if (_vista == _Vista.libre && !_esLibre(producto)) return false;
        if (_vista == _Vista.reservado && !_esReservado(producto)) return false;
      }

      return coincideBusqueda(texto, [producto['nombre'], producto['codigo']]);
    }).toList();

    if (_ultimaCompra.isNotEmpty || _modoVehiculo) {
      // Primero lo que compró la última vez; con el vehículo, después por categoría.
      int orden(Map<String, dynamic> p) => _ultimaCompra.containsKey(p['id'].toString()) ? 0 : 1;
      String categoria(Map<String, dynamic> p) => _modoVehiculo ? (p['categoria']?.toString() ?? '') : '';
      productosFiltrados.sort((a, b) {
        final o = orden(a).compareTo(orden(b));
        if (o != 0) return o;
        final c = categoria(a).compareTo(categoria(b));
        if (c != 0) return c;
        return (a['nombre']?.toString() ?? '').compareTo(b['nombre']?.toString() ?? '');
      });
    }

    final escribiendo = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Column(
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 150),
          child: escribiendo
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<String>(
                      showSelectedIcon: false,
                      style: ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        backgroundColor: WidgetStateProperty.resolveWith<Color?>(
                          (states) => states.contains(WidgetState.selected)
                              ? colorLista(_tipoPrecio)
                              : (Tonos.of(context).oscuro ? null : Colors.white),
                        ),
                        foregroundColor: WidgetStateProperty.resolveWith<Color?>(
                          (states) => states.contains(WidgetState.selected)
                              ? Colors.white
                              : (Tonos.of(context).oscuro ? Colors.white : AppColors.negro),
                        ),
                      ),
                      segments: const [
                        ButtonSegment<String>(
                          value: 'normal',
                          label: Text('Normal'),
                        ),
                        ButtonSegment<String>(
                          value: 'promo',
                          label: Text('Promo'),
                        ),
                        ButtonSegment<String>(
                          value: 'interior',
                          label: Text('Interior'),
                        ),
                      ],
                      selected: {_tipoPrecio},
                      onSelectionChanged: (seleccion) {
                        setState(() {
                          _tipoPrecio = seleccion.first;
                        });
                      },
                    ),
                  ),
                ),
        ),
        if (_vehiculo != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<_Vista>(
                key: const Key('vista-vehiculo'),
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: _Vista.libre,
                    label: Text('Para vender · ${_productos.where(_esLibre).length}'),
                  ),
                  ButtonSegment(value: _Vista.reservado, label: Text('Reservado · ${_productos.where(_esReservado).length}')),
                  const ButtonSegment(value: _Vista.todo, label: Text('Todo')),
                ],
                selected: {_vista},
                onSelectionChanged: (v) => setState(() => _vista = v.first),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: TextField(
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Buscar producto...',
              prefixIcon: Icon(Icons.search, color: colorLista(_tipoPrecio)),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(
                  color: colorLista(_tipoPrecio),
                  width: 2,
                ),
              ),
            ),
            onChanged: (valor) {
              setState(() {
                _busqueda = valor.trim();
              });
            },
          ),
        ),
        Expanded(
          child: productosFiltrados.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _modoVehiculo && texto.isEmpty
                              ? (_vista == _Vista.libre
                                    ? 'No queda nada libre en el vehículo: lo que hay arriba es para entregar.'
                                    : 'No hay nada reservado para entregas.')
                              : 'No se encontraron productos',
                          textAlign: TextAlign.center,
                        ),
                        if (_modoVehiculo && texto.isEmpty)
                          TextButton(
                            onPressed: () => setState(() => _vista = _Vista.todo),
                            child: const Text('Ver todos los productos'),
                          ),
                      ],
                    ),
                  ),
                )
              : useDesktopLayout(context)
              ? DesktopRecords(
                  records: productosFiltrados,
                  fields: [
                    DesktopField(
                      'Producto',
                      (r) => Row(
                        children: [
                          ProductPhoto(
                            path: r['foto_path']?.toString(),
                            size: 30,
                            tarjeta: _tarjetaPrecio(r),
                          ),
                          const SizedBox(width: 8),
                          desktopText(
                            r['nombre']?.toString() ?? 'Producto',
                            width: 220,
                          ),
                        ],
                      ),
                      width: 260,
                    ),
                    DesktopField('Código', (r) => r['codigo'], width: 80),
                    if (productosFiltrados.any(
                      (r) => (r['descripcion']?.toString().trim() ?? '')
                          .isNotEmpty,
                    ))
                      DesktopField(
                        'Descripción',
                        (r) => r['descripcion']?.toString().trim() ?? '',
                        width: 260,
                      ),
                    DesktopField(
                      'Precio',
                      (r) => desktopMoney(_precioUsado(r)),
                      numeric: true,
                      width: 120,
                    ),
                    DesktopField(
                      'Lista fijada',
                      (r) => _tiposPrecioFijados[r['id'].toString()] ?? '—',
                      width: 100,
                    ),
                    if (_vehiculo != null)
                      DesktopField(
                        'Vehículo',
                        (r) {
                          final q = _quedanEnVehiculo(r);
                          return q == null ? '—' : 'Quedan ${formatQty(q)}';
                        },
                        width: 110,
                      ),
                    if (_ultimaCompra.isNotEmpty)
                      DesktopField(
                        'Última compra',
                        (r) => _ultimaCompra[r['id'].toString()] ?? '',
                        numeric: true,
                        width: 100,
                      ),
                    DesktopField(
                      'Cantidad',
                      (r) => _cantidadProducto(r),
                      numeric: true,
                      width: 80,
                    ),
                  ],
                  actions: (p) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Quitar una unidad',
                        onPressed: _cantidadProducto(p) > 0
                            ? () => _restarProducto(p)
                            : null,
                        icon: const Icon(Icons.remove_circle_outline, size: 20),
                      ),
                      IconButton(
                        tooltip: 'Agregar una unidad',
                        onPressed: () => _sumarProducto(p),
                        icon: const Icon(Icons.add_circle_outline, size: 20),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: productosFiltrados.length + (_vista == _Vista.libre && texto.isEmpty && _vehiculo != null && _productos.any(_esReservado) ? 1 : 0),
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    if (index == productosFiltrados.length) {
                      return Card(
                        key: const Key('ver-reservado'),
                        child: ListTile(
                          leading: const Icon(Icons.chevron_right),
                          title: Text(
                            'Reservado para entregas (${_productos.where(_esReservado).length})',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: const Text('Arriba, pero ya tiene dueño. Tocá para ver.'),
                          onTap: () => setState(() => _vista = _Vista.reservado),
                        ),
                      );
                    }
                    final producto = productosFiltrados[index];

                    final nombre =
                        producto['nombre']?.toString() ?? 'Sin nombre';

                    final codigo = producto['codigo']?.toString() ?? '';

                    final precio = _precioUsado(producto);
                    final cantidad = _cantidadProducto(producto);
                    final id = producto['id'].toString();
                    final listaFijada = _tiposPrecioFijados[id];

                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          children: [
                            ProductPhoto(
                              path: producto['foto_path']?.toString(),
                              size: 48,
                              tarjeta: _tarjetaPrecio(producto),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    nombre,
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if ((producto['descripcion']
                                              ?.toString()
                                              .trim() ??
                                          '')
                                      .isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      producto['descripcion'].toString().trim(),
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                  if (codigo.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'Código: $codigo',
                                      style: const TextStyle(
                                        color: AppColors.gris,
                                      ),
                                    ),
                                  ],
                                  if (_quedanEnVehiculo(producto) != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      _textoVehiculo(producto),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: _quedanEnVehiculo(producto)! <= 0
                                            ? AppColors.rojo
                                            : AppColors.verde,
                                      ),
                                    ),
                                  ],
                                  if (_ultimaCompra.containsKey(id)) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'La última vez llevó ${_ultimaCompra[id]}',
                                      style: const TextStyle(
                                        color: AppColors.doradoOscuro,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  Text(
                                    _formatearPrecio(precio),
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (cantidad > 0 && listaFijada != null) ...[
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: colorLista(listaFijada),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        'Lista ${_nombreLista(listaFijada)}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Row(
                              children: [
                                IconButton(
                                  onPressed: cantidad > 0
                                      ? () => _restarProducto(producto)
                                      : null,
                                  icon: const Icon(Icons.remove_circle_outline),
                                ),
                                SizedBox(
                                  width: 32,
                                  child: Text(
                                    '$cantidad',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => _sumarProducto(producto),
                                  icon: const Icon(Icons.add_circle),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  PreferredSizeWidget _barraLista() {
    final habitual = _cliente?['tipo_precio_habitual']?.toString();
    final distintaHabitual =
        habitual != null &&
        {'normal', 'promo', 'interior'}.contains(habitual) &&
        habitual != _tipoPrecio;
    return AppBar(
      backgroundColor: colorLista(_tipoPrecio),
      foregroundColor: Colors.white,
      toolbarHeight: 64,
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: IconButton(
            key: const Key('calculadora-bulto'),
            tooltip: 'Calculadora por bulto',
            style: IconButton.styleFrom(
              backgroundColor: AppColors.dorado,
              foregroundColor: AppColors.negro,
            ),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => CalculatorPage(
                  soloBulto: true,
                  productos: _productos.map(CalcProduct.fromMap).toList(),
                  lista: _tipoPrecio,
                  cargar: widget.productosIniciales == null,
                ),
              ),
            ),
            icon: const Icon(Icons.calculate_outlined),
          ),
        ),
      ],
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _cliente == null
                ? 'CLIENTE AL FINAL'
                : _cliente!['nombre_comercio']?.toString() ?? 'Sin nombre',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          Text(
            'LISTA ${_nombreLista(_tipoPrecio).toUpperCase()}'
            '${distintaHabitual ? ' · habitual: ${_nombreLista(habitual)}' : ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  String _nombreLista(String tipo) {
    switch (tipo) {
      case 'promo':
        return 'Promo';
      case 'interior':
        return 'Interior';
      default:
        return 'Normal';
    }
  }
}

enum _Vista { libre, reservado, todo }
