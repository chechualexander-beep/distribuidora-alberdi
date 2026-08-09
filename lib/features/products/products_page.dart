import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key});

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  bool _cargando = true;
  String? _error;

  List<Map<String, dynamic>> _productos = [];
  String _busqueda = '';

  @override
  void initState() {
    super.initState();
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
          .select()
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

  String _precio(dynamic valor) {
    if (valor == null) return '\$0';

    final numero = double.tryParse(valor.toString()) ?? 0;

    return '\$${numero.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Productos'),
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

    if (_productos.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 80,
            ),
            SizedBox(height: 20),
            Text(
              'Todavía no hay productos cargados',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    final texto = _busqueda.toLowerCase();

    final productosFiltrados = _productos.where((producto) {
      final nombre =
          producto['nombre']?.toString().toLowerCase() ?? '';

      final codigo =
          producto['codigo']?.toString().toLowerCase() ?? '';

      final descripcion =
          producto['descripcion']?.toString().toLowerCase() ?? '';

      return nombre.contains(texto) ||
          codigo.contains(texto) ||
          descripcion.contains(texto);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
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
                  child: Text(
                    'No se encontraron productos',
                    style: TextStyle(fontSize: 16),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _cargarProductos,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: productosFiltrados.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final producto = productosFiltrados[index];

                      final nombre =
                          producto['nombre']?.toString() ??
                              'Sin nombre';

                      final codigo =
                          producto['codigo']?.toString() ?? '';

                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                nombre,
                                style: const TextStyle(
                                  fontSize: 18,
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

                              const SizedBox(height: 12),

                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _PrecioChip(
                                    titulo: 'Normal',
                                    precio: _precio(
                                      producto['precio_normal'],
                                    ),
                                  ),
                                  _PrecioChip(
                                    titulo: 'Promo',
                                    precio: _precio(
                                      producto['precio_promo'],
                                    ),
                                  ),
                                  _PrecioChip(
                                    titulo: 'Interior',
                                    precio: _precio(
                                      producto['precio_interior'],
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
        ),
      ],
    );
  }
}

class _PrecioChip extends StatelessWidget {
  final String titulo;
  final String precio;

  const _PrecioChip({
    required this.titulo,
    required this.precio,
  });

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(
        '$titulo: $precio',
      ),
    );
  }
}