import 'package:flutter/material.dart';
import '../../core/desktop_table.dart';
import 'stock_models.dart';
import 'stock_service.dart';
import 'stock_adjust_dialog.dart';
import 'stock_initial_dialog.dart';
import 'stock_movements_page.dart';

class StockPage extends StatefulWidget {
  const StockPage({super.key, this.service});
  final StockService? service;
  @override
  State<StockPage> createState() => _StockPageState();
}

class _StockPageState extends State<StockPage> {
  late final _service = widget.service ?? StockService();
  StockSnapshot? _data;
  bool _loading = true;
  String? _error;
  String _search = '';
  StockFilter _filter = StockFilter.all;
  int _request = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _service.load();
      if (mounted && request == _request) setState(() => _data = data);
    } catch (error) {
      if (mounted && request == _request) {
        setState(() => _error = stockError(error));
      }
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  Future<void> _initial() async {
    final count = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StockInitialDialog(snapshot: _data!, service: _service),
    );
    if (!mounted) return;
    if (count != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            count == 1
                ? 'Se inicializó 1 producto.'
                : 'Se inicializaron $count productos.',
          ),
        ),
      );
    }
    // También al cerrar tras un error de red: pudo perderse la respuesta final.
    await _load();
  }

  Future<void> _adjust(StockProduct product) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StockAdjustDialog(
        product: product,
        location: _data!.location,
        service: _service,
      ),
    );
    if (!mounted) return;
    if (saved == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stock ajustado correctamente.')),
      );
    }
    await _load();
  }

  Future<void> _movements() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            StockMovementsPage(location: _data!.location, service: _service),
      ),
    );
    if (mounted) await _load();
  }

  Widget _card(String label, String value, double width) => SizedBox(
    width: width,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 10),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
          ],
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final data = _data;
    final products = data == null
        ? <StockProduct>[]
        : filterStock(data.products, _search, _filter);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock'),
        actions: [
          IconButton(
            tooltip: 'Actualizar Stock',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _load,
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    data!.location.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (!data.location.active)
                    const Text('Ubicación inactiva: solo consulta.'),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, box) {
                      final width = box.maxWidth >= 510
                          ? (box.maxWidth - 16) / 3
                          : box.maxWidth;
                      return Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _card(
                            'Productos',
                            data.summary.products.toString(),
                            width,
                          ),
                          _card(
                            'Unidades totales',
                            data.summary.units.format(),
                            width,
                          ),
                          _card(
                            'Valor estimado a costo actual',
                            desktopMoney(data.summary.value),
                            width,
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        onPressed:
                            data.location.active &&
                                data.products.any((p) => !p.initialized)
                            ? _initial
                            : null,
                        icon: const Icon(Icons.playlist_add),
                        label: const Text('Cargar inventario inicial'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _movements,
                        icon: const Icon(Icons.history),
                        label: const Text('Movimientos'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: 320,
                        child: TextField(
                          decoration: const InputDecoration(
                            labelText: 'Buscar producto o código',
                            prefixIcon: Icon(Icons.search),
                          ),
                          onChanged: (v) => setState(() => _search = v),
                        ),
                      ),
                      SizedBox(
                        width: 180,
                        child: DropdownButtonFormField<StockFilter>(
                          isExpanded: true,
                          initialValue: _filter,
                          decoration: const InputDecoration(
                            labelText: 'Estado',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: StockFilter.all,
                              child: Text('Todos'),
                            ),
                            DropdownMenuItem(
                              value: StockFilter.active,
                              child: Text('Activos'),
                            ),
                            DropdownMenuItem(
                              value: StockFilter.inactive,
                              child: Text('Inactivos'),
                            ),
                          ],
                          onChanged: (v) => setState(() => _filter = v!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: data.products.isEmpty
                        ? const Center(
                            child: Text('No hay productos cargados.'),
                          )
                        : products.isEmpty
                        ? const Center(
                            child: Text(
                              'No hay productos que coincidan con los filtros.',
                            ),
                          )
                        : DesktopTable(
                            minimumWidth: 1180,
                            columns: const [
                              DataColumn(
                                label: Flexible(
                                  child: Text(
                                    'Producto',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              DataColumn(
                                label: Flexible(
                                  child: Text(
                                    'Código',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              DataColumn(
                                label: Flexible(
                                  child: Text(
                                    'Estado',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              DataColumn(
                                label: Flexible(
                                  child: Text(
                                    'Costo',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                numeric: true,
                              ),
                              DataColumn(
                                label: Flexible(
                                  child: Text(
                                    'Stock',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                numeric: true,
                              ),
                              DataColumn(
                                label: Flexible(
                                  child: Text(
                                    'Valor stock',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                numeric: true,
                              ),
                              DataColumn(
                                label: Flexible(
                                  child: Text(
                                    'Estado stock',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              DataColumn(
                                label: Flexible(
                                  child: Text(
                                    'Acciones',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                            rows: [
                              for (final p in products)
                                DataRow(
                                  key: ValueKey(p.id),
                                  cells: [
                                    DataCell(desktopText(p.name, width: 230)),
                                    DataCell(desktopText(p.code, width: 80)),
                                    DataCell(
                                      Text(p.active ? 'Activo' : 'Inactivo'),
                                    ),
                                    DataCell(Text(desktopMoney(p.cost))),
                                    DataCell(
                                      Text(
                                        p.initialized
                                            ? p.quantity.format()
                                            : '—',
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        p.initialized
                                            ? desktopMoney(p.value)
                                            : '—',
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        p.initialized
                                            ? 'Inicializado'
                                            : 'No inicializado',
                                      ),
                                    ),
                                    DataCell(
                                      p.initialized
                                          ? TextButton(
                                              onPressed: data.location.active
                                                  ? () => _adjust(p)
                                                  : null,
                                              child: const Text('Ajustar'),
                                            )
                                          : const Text('Inicializar primero'),
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
}
