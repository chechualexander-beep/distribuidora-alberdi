import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'order_summary_page.dart';

class OrderProductsPage extends StatefulWidget {
  final Map<String, dynamic> cliente;
  final DateTime? fechaEntrega;

  const OrderProductsPage({
    super.key,
    required this.cliente,
    this.fechaEntrega,
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

  final Map<String, int> _cantidades = {};
  final Map<String, double> _preciosFijados = {};
  final Map<String, String> _tiposPrecioFijados = {};

  @override
void initState() {
  super.initState();

  final tipoHabitual =
      widget.cliente['tipo_precio_habitual']?.toString();

  if (tipoHabitual == 'normal' ||
      tipoHabitual == 'promo' ||
      tipoHabitual == 'interior') {
    _tipoPrecio = tipoHabitual!;
  }

  _cargarProductos();
}

  Future<void> _cargarProductos() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final respuesta = await Supabase.instance.client
          .from('productos')
          .select(
            'id, codigo, nombre, precio_normal, precio_promo, precio_interior',
          )
          .eq('activo', true)
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
    return _cantidades.values.fold(
      0,
      (total, cantidad) => total + cantidad,
    );
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

  void _verPedido() {
  final fechaEntrega = widget.fechaEntrega;

  if (fechaEntrega == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Seleccioná una fecha de entrega antes de continuar.'),
      ),
    );
    return;
  }

  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => OrderSummaryPage(
        fechaEntrega: fechaEntrega,
        cliente: widget.cliente,
        productos: _productos,
        cantidades: Map<String, int>.from(_cantidades),
        tipoPrecio: _tipoPrecio,
        preciosFijados: Map<String, double>.from(_preciosFijados),
        tiposPrecioFijados:
            Map<String, String>.from(_tiposPrecioFijados),
      ),
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Productos del pedido'),
      ),
      body: _construirContenido(),
      bottomNavigationBar: _totalUnidades > 0
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton(
                  onPressed: _verPedido,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '$_totalUnidades unidades',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Text(
                          _formatearPrecio(_totalPedido),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Text(
                          'VER PEDIDO',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
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
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 60,
              ),
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

    final texto = _busqueda.toLowerCase();

    final productosFiltrados = _productos.where((producto) {
      final nombre =
          producto['nombre']?.toString().toLowerCase() ?? '';

      final codigo =
          producto['codigo']?.toString().toLowerCase() ?? '';

      return nombre.contains(texto) || codigo.contains(texto);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Cliente',
                    style: TextStyle(
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.cliente['nombre_comercio']?.toString() ??
                        'Sin nombre',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Tipo de precio para nuevos productos',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    style: ButtonStyle(
  backgroundColor: WidgetStateProperty.resolveWith<Color?>(
    (states) {
      if (!states.contains(WidgetState.selected)) {
        return null;
      }

      switch (_tipoPrecio) {
        case 'promo':
          return Colors.orange;
        case 'interior':
          return Colors.green;
        default:
          return Colors.blue;
      }
    },
  ),
  foregroundColor: WidgetStateProperty.resolveWith<Color?>(
    (states) {
      if (states.contains(WidgetState.selected)) {
        return Colors.white;
      }
      return null;
    },
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
                ],
              ),
            ),
          ),
        ),
        Container(
  width: double.infinity,
  margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
  padding: const EdgeInsets.symmetric(vertical: 10),
  decoration: BoxDecoration(
    color: _tipoPrecio == 'promo'
        ? Colors.orange
        : _tipoPrecio == 'interior'
            ? Colors.green
            : Colors.blue,
    borderRadius: BorderRadius.circular(8),
  ),
  child: Text(
    _tipoPrecio == 'promo'
        ? 'LISTA PROMO'
        : _tipoPrecio == 'interior'
            ? 'LISTA INTERIOR'
            : 'LISTA NORMAL',
    textAlign: TextAlign.center,
    style: const TextStyle(
      color: Colors.white,
      fontWeight: FontWeight.bold,
      fontSize: 16,
    ),
  ),
),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Buscar producto...',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
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
              ? const Center(
                  child: Text('No se encontraron productos'),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: productosFiltrados.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final producto = productosFiltrados[index];

                    final nombre =
                        producto['nombre']?.toString() ?? 'Sin nombre';

                    final codigo =
                        producto['codigo']?.toString() ?? '';

                    final precio = _precioUsado(producto);
                    final cantidad = _cantidadProducto(producto);
                    final id = producto['id'].toString();
                    final listaFijada = _tiposPrecioFijados[id];

                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    nombre,
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (codigo.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'Código: $codigo',
                                      style: const TextStyle(
                                        color: Colors.grey,
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
                                  if (cantidad > 0 &&
                                      listaFijada != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'Precio fijado: ${_nombreLista(listaFijada)}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
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
                                  icon: const Icon(
                                    Icons.remove_circle_outline,
                                  ),
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
                                  onPressed: () =>
                                      _sumarProducto(producto),
                                  icon: const Icon(
                                    Icons.add_circle,
                                  ),
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