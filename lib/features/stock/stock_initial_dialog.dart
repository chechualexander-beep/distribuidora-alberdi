import 'package:flutter/material.dart';
import '../../core/desktop_table.dart';
import 'stock_models.dart';
import 'stock_service.dart';

class StockInitialDialog extends StatefulWidget {
  const StockInitialDialog({
    super.key,
    required this.snapshot,
    required this.service,
  });
  final StockSnapshot snapshot;
  final StockService service;
  @override
  State<StockInitialDialog> createState() => _StockInitialDialogState();
}

class _StockInitialDialogState extends State<StockInitialDialog> {
  final _controllers = <String, TextEditingController>{};
  String _search = '';
  InitialStockFilter _filter = InitialStockFilter.all;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    for (final p in widget.snapshot.products) {
      _controllers[p.id] = TextEditingController(
        text: p.initialized ? p.quantity.format() : '',
      );
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, String> get _inputs =>
      _controllers.map((id, c) => MapEntry(id, c.text));
  bool get _invalid => widget.snapshot.products.any(
    (p) => !p.initialized && quantityError(_controllers[p.id]!.text) != null,
  );
  int get _count => widget.snapshot.products
      .where(
        (p) => !p.initialized && _controllers[p.id]!.text.trim().isNotEmpty,
      )
      .length;

  Future<void> _submit() async {
    if (_busy || _invalid || _count == 0) return;
    final items = initialStockItems(widget.snapshot.products, _inputs);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirmar inventario inicial'),
          content: Text(
            'Se cargará el inventario inicial de ${items.length} ${items.length == 1 ? 'producto' : 'productos'}.\n\nDespués de confirmar, cualquier modificación posterior deberá realizarse mediante Ajustar stock.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      final count = await widget.service.initialize(
        widget.snapshot.location.id,
        items,
      );
      if (mounted) Navigator.pop(context, count);
    } catch (error) {
      if (mounted) setState(() => _error = stockError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final products = filterInitialStock(
      widget.snapshot.products,
      _search,
      _filter,
    );
    return PopScope(
      canPop: !_busy,
      child: Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: SizedBox(
          width: 1100,
          height: MediaQuery.sizeOf(context).height * .82,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Cargar inventario inicial',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(widget.snapshot.location.name),
                const SizedBox(height: 8),
                const Text(
                  'Dejá el campo vacío para omitir el producto. Ingresá 0 para inicializarlo sin unidades.',
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 300,
                      child: TextField(
                        key: const ValueKey('initial-search'),
                        enabled: !_busy,
                        decoration: const InputDecoration(
                          labelText: 'Buscar producto o código',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (value) => setState(() => _search = value),
                      ),
                    ),
                    SizedBox(
                      width: 200,
                      child: DropdownButtonFormField<InitialStockFilter>(
                        isExpanded: true,
                        initialValue: _filter,
                        decoration: const InputDecoration(
                          labelText: 'Estado stock',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: InitialStockFilter.all,
                            child: Text('Todos'),
                          ),
                          DropdownMenuItem(
                            value: InitialStockFilter.pending,
                            child: Text('Pendientes'),
                          ),
                          DropdownMenuItem(
                            value: InitialStockFilter.initialized,
                            child: Text('Inicializados'),
                          ),
                        ],
                        onChanged: _busy
                            ? null
                            : (value) => setState(() => _filter = value!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('Productos a inicializar: $_count'),
                if (_invalid)
                  Text(
                    'Revisá las cantidades marcadas: no negativas, hasta 3 decimales.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (_count > 300)
                  Text(
                    'Seleccioná hasta 300 productos por carga.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Expanded(
                  child: products.isEmpty
                      ? const Center(
                          child: Text(
                            'No hay productos que coincidan con los filtros.',
                          ),
                        )
                      : DesktopTable(
                          minimumWidth: 860,
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
                                  'Estado stock',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            DataColumn(
                              label: Flexible(
                                child: Text(
                                  'Cantidad física',
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
                                  DataCell(desktopText(p.name, width: 300)),
                                  DataCell(desktopText(p.code, width: 90)),
                                  DataCell(
                                    Text(
                                      p.initialized
                                          ? 'Inicializado'
                                          : 'Pendiente',
                                    ),
                                  ),
                                  DataCell(
                                    SizedBox(
                                      width: 180,
                                      child: TextField(
                                        key: ValueKey('initial-${p.id}'),
                                        controller: _controllers[p.id],
                                        enabled: !_busy && !p.initialized,
                                        keyboardType:
                                            const TextInputType.numberWithOptions(
                                              decimal: true,
                                            ),
                                        decoration: InputDecoration(
                                          isDense: true,
                                          hintText: 'Sin cargar',
                                          suffixIcon:
                                              quantityError(
                                                    _controllers[p.id]!.text,
                                                  ) ==
                                                  null
                                              ? null
                                              : Tooltip(
                                                  message: quantityError(
                                                    _controllers[p.id]!.text,
                                                  )!,
                                                  child: Icon(
                                                    Icons.error_outline,
                                                    color: Theme.of(
                                                      context,
                                                    ).colorScheme.error,
                                                  ),
                                                ),
                                        ),
                                        onChanged: (_) => setState(() {}),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 12,
                  children: [
                    TextButton(
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      child: const Text('Cancelar'),
                    ),
                    FilledButton(
                      onPressed:
                          _busy || _invalid || _count == 0 || _count > 300
                          ? null
                          : _submit,
                      child: Text(
                        _busy ? 'Procesando…' : 'Guardar inventario inicial',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
