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

class OrderProductsPage extends StatefulWidget {
  final Map<String, dynamic> cliente;
  final DateTime? fechaEntrega;
  final String tipoOperacion;

  final Map<String, int>? cantidadesIniciales;
  final Map<String, double>? preciosIniciales;
  final Map<String, String>? tiposPrecioIniciales;
  final String? pedidoId;
  final String? observacionInicial;
  final String? tipoPrecioInicial;
  final SupabaseClient? client;

  const OrderProductsPage({
    super.key,
    required this.cliente,
    this.fechaEntrega,
    required this.tipoOperacion,
    this.cantidadesIniciales,
    this.preciosIniciales,
    this.tiposPrecioIniciales,
    this.pedidoId,
    this.observacionInicial,
    this.tipoPrecioInicial,
    this.client,
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

  final Map<String, int> _cantidades = {};

  // Venta directa con un viaje abierto: se ofrece lo que lleva el vehículo.
  VehicleStock? _vehiculo;
  bool _soloVehiculo = true;
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
        widget.cliente['tipo_precio_habitual']?.toString();

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

    _cargarProductos();
    if (widget.tipoOperacion == 'venta_directa' && widget.pedidoId == null) {
      _cargarVehiculo();
      _cargarUltimaCompra();
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
    final clienteId = widget.cliente['id']?.toString();
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

  bool get _modoVehiculo => _vehiculo != null && _soloVehiculo;

  /// Lo que queda en el vehículo descontando lo que ya está en esta venta.
  double? _quedanEnVehiculo(Map<String, dynamic> producto) {
    final linea = _vehiculo?.lines[producto['id'].toString()];
    if (linea == null) return null;
    return linea.available - _cantidadProducto(producto);
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

  double _precioActual(Map<String, dynamic> producto) {
    dynamic valor;

    switch (_tipoPrecio) {
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

  String _formatearPrecio(double valor) {
    final entero = valor.round().toString();

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

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OrderSummaryPage(
          fechaEntrega: fechaEntrega,
          cliente: widget.cliente,
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

  @override
  Widget build(BuildContext context) {
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
    String normalizarTexto(String texto) {
      return texto
          .toLowerCase()
          .replaceAll('á', 'a')
          .replaceAll('é', 'e')
          .replaceAll('í', 'i')
          .replaceAll('ó', 'o')
          .replaceAll('ú', 'u')
          .replaceAll('ü', 'u')
          .replaceAll('ñ', 'n');
    }

    final texto = normalizarTexto(_busqueda.trim());

    final productosFiltrados = _productos.where((producto) {
      final nombre = normalizarTexto(producto['nombre']?.toString() ?? '');

      final codigo = producto['codigo']?.toString().toLowerCase() ?? '';

      if (_modoVehiculo &&
          texto.isEmpty &&
          !_vehiculo!.lines.containsKey(producto['id'].toString()) &&
          _cantidadProducto(producto) == 0) {
        return false;
      }

      return nombre.contains(texto) || codigo.contains(texto);
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
                              : Colors.white,
                        ),
                        foregroundColor: WidgetStateProperty.resolveWith<Color?>(
                          (states) => states.contains(WidgetState.selected)
                              ? Colors.white
                              : AppColors.negro,
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
            child: Row(
              children: [
                FilterChip(
                  avatar: const Icon(Icons.local_shipping_outlined, size: 18),
                  label: const Text('Solo lo del vehículo'),
                  selected: _soloVehiculo,
                  onSelected: (v) => setState(() => _soloVehiculo = v),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${_vehiculo!.lines.values.where((l) => l.available > 0).length} productos para ofrecer',
                    style: const TextStyle(color: AppColors.gris),
                  ),
                ),
              ],
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
              ? const Center(child: Text('No se encontraron productos'))
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
                  itemCount: productosFiltrados.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
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
                                      (_quedanEnVehiculo(producto)! <= 0)
                                          ? 'Vehículo: no queda'
                                          : 'Vehículo: quedan ${formatQty(_quedanEnVehiculo(producto)!)}',
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
    final habitual = widget.cliente['tipo_precio_habitual']?.toString();
    final distintaHabitual =
        habitual != null &&
        {'normal', 'promo', 'interior'}.contains(habitual) &&
        habitual != _tipoPrecio;
    return AppBar(
      backgroundColor: colorLista(_tipoPrecio),
      foregroundColor: Colors.white,
      toolbarHeight: 64,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.cliente['nombre_comercio']?.toString() ?? 'Sin nombre',
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
