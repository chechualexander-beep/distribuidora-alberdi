import '../../core/app_theme.dart';
import '../../core/desktop_records.dart';
import '../../core/desktop_table.dart';
import '../products/product_photo.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'order_summary_page.dart';
import 'delivery_date_picker.dart';

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
  }

  Future<void> _cargarProductos() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final respuesta = await _client
          .from('productos')
          .select(
            'id, codigo, nombre, descripcion, precio_normal, precio_promo, precio_interior, foto_path',
          )
          .eq('activo', true)
          .eq('visible_preventistas', true)
          .order('nombre');

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

  void _verPedido() {
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

      return nombre.contains(texto) || codigo.contains(texto);
    }).toList();

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
            '${distintaHabitual ? ' · habitual: ${_nombreLista(habitual ?? '')}' : ''}',
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
