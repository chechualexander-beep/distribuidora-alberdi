import 'product_photo.dart';
import 'product_photo_dialog.dart';
import 'product_photo_review_page.dart';
import 'package:distribuidora_alberdi/core/app_theme.dart';
import '../../core/desktop_table.dart';
import 'products_desktop_table.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/offline_queries.dart';
import 'package:distribuidora_alberdi/core/money_format.dart';

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
  bool _soloSinFoto = false;
  bool _puedeCargarFotos = false;
  bool _esAdministrador = false;

  @override
  void initState() {
    super.initState();
    _cargarProductos();
    _cargarPermisos();
  }

  /// Opcional: si el servidor todavía no tiene la carga de fotos, los botones no aparecen.
  Future<void> _cargarPermisos() async {
    try {
      final db = Supabase.instance.client;
      final fotos = await db.rpc('puede_cargar_fotos') == true;
      final admin = await db.rpc('es_administrador') == true;
      if (mounted) {
        setState(() {
          _puedeCargarFotos = fotos;
          _esAdministrador = admin;
        });
      }
    } catch (_) {
      /* Sin permiso: solo consulta. */
    }
  }

  Future<void> _cambiarFoto(Map<String, dynamic> producto) async {
    final cambio = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ProductPhotoDialog(product: producto),
    );
    if (cambio == true && mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Foto guardada. Ya se ve en el catálogo.')),
      );
    }
  }

  Future<void> _cargarProductos() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final respuesta = await consultarProductosCatalogo(
        Supabase.instance.client,
      );

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

  String _precio(dynamic valor) => formatoPesos(valor ?? 0);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Productos'),
        actions: [
          if (_esAdministrador)
            IconButton(
              tooltip: 'Fotos cargadas por preventistas',
              icon: const Icon(Icons.photo_library_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ProductPhotoReviewPage(),
                ),
              ),
            ),
          if (useDesktopLayout(context))
            IconButton(
              onPressed: _cargarProductos,
              tooltip: 'Actualizar productos',
              icon: const Icon(Icons.refresh),
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

    if (_productos.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, size: 80),
            SizedBox(height: 20),
            Text(
              'Todavía no hay productos cargados',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      );
    }

    final texto = _busqueda.toLowerCase();

    final productosFiltrados = _productos.where((producto) {
      final nombre = producto['nombre']?.toString().toLowerCase() ?? '';

      final codigo = producto['codigo']?.toString().toLowerCase() ?? '';

      final descripcion =
          producto['descripcion']?.toString().toLowerCase() ?? '';

      if (_soloSinFoto &&
          (producto['foto_path']?.toString() ?? '').isNotEmpty) {
        return false;
      }
      return nombre.contains(texto) ||
          codigo.contains(texto) ||
          descripcion.contains(texto);
    }).toList();
    final sinFoto = _productos
        .where((p) => (p['foto_path']?.toString() ?? '').isEmpty)
        .length;

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
        if (_puedeCargarFotos)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilterChip(
                avatar: const Icon(Icons.hide_image_outlined, size: 18),
                label: Text('Sin foto ($sinFoto)'),
                selected: _soloSinFoto,
                onSelected: (valor) => setState(() => _soloSinFoto = valor),
              ),
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
              : useDesktopLayout(context)
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: ProductsDesktopTable(products: productosFiltrados),
                )
              : RefreshIndicator(
                  onRefresh: _cargarProductos,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: productosFiltrados.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final producto = productosFiltrados[index];

                      final nombre =
                          producto['nombre']?.toString() ?? 'Sin nombre';

                      final codigo = producto['codigo']?.toString() ?? '';

                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  ProductPhoto(
                                    path: producto['foto_path']?.toString(),
                                    size: 88,
                                  ),
                                  if (_puedeCargarFotos) ...[
                                    const SizedBox(width: 12),
                                    OutlinedButton.icon(
                                      onPressed: () => _cambiarFoto(producto),
                                      icon: const Icon(
                                        Icons.photo_camera_outlined,
                                      ),
                                      label: Text(
                                        (producto['foto_path']?.toString() ??
                                                    '')
                                                .isEmpty
                                            ? 'Agregar foto'
                                            : 'Cambiar foto',
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                nombre,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),

                              if ((producto['descripcion']?.toString().trim() ??
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
                                  style: const TextStyle(color: AppColors.gris),
                                ),
                              ],

                              const SizedBox(height: 12),

                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _PrecioChip(
                                    titulo: 'Normal',
                                    precio: _precio(producto['precio_normal']),
                                  ),
                                  _PrecioChip(
                                    titulo: 'Promo',
                                    precio: _precio(producto['precio_promo']),
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

  const _PrecioChip({required this.titulo, required this.precio});

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text('$titulo: $precio'));
  }
}
