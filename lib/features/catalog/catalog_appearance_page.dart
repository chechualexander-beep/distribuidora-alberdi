import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/desktop_records.dart';
import '../../core/text_search.dart';

/// Paletas del catálogo web (las mismas del sitio: catalogo/src/vitrina.css).
const catalogThemes = <String, ({String label, Color color})>{
  'alberdi': (label: 'Negro y dorado', color: Color(0xFF1A1A1A)),
  'rojo': (label: 'Rojo', color: Color(0xFF9B3A2E)),
  'azul': (label: 'Azul', color: Color(0xFF3A4486)),
  'verde': (label: 'Verde', color: Color(0xFF1B6B4A)),
  'naranja': (label: 'Naranja', color: Color(0xFF8A5A00)),
};

String _normalize(String? text) => (text ?? '').trim().toLowerCase();

/// Orden final: primero las guardadas que siguen existiendo, después las nuevas por nombre.
List<String> mergeCategoryOrder(List<String> saved, Iterable<String> current) {
  final existing = current.map(_normalize).where((c) => c.isNotEmpty).toSet();
  final ordered = <String>{
    for (final c in saved.map(_normalize))
      if (existing.contains(c)) c,
  }.toList();
  final rest = existing.difference(ordered.toSet()).toList()..sort();
  return [...ordered, ...rest];
}

/// Apariencia de todos los catálogos web: color, orden de categorías y novedades.
class CatalogAppearancePage extends StatefulWidget {
  const CatalogAppearancePage({super.key});
  @override
  State<CatalogAppearancePage> createState() => _CatalogAppearancePageState();
}

class _CatalogAppearancePageState extends State<CatalogAppearancePage> {
  String _theme = 'alberdi';
  List<String> _order = [];
  final _names = <String, String>{}; // categoría normalizada -> como se escribe
  final _novelties = <String, DateTime>{}; // producto -> hasta
  List<Map<String, dynamic>> _products = [];
  String? _error;
  bool _loading = true, _saving = false, _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = Supabase.instance.client;
      final config = Map<String, dynamic>.from(
        await db.rpc('leer_presentacion_catalogo') as Map,
      );
      final products = await db
          .from('productos')
          .select('id,nombre,categoria')
          .eq('activo', true)
          .eq('visible_preventistas', true)
          .order('nombre');
      if (!mounted) return;
      setState(() {
        _products = List<Map<String, dynamic>>.from(products);
        _names.clear();
        for (final p in _products) {
          final raw = p['categoria']?.toString().trim() ?? '';
          if (raw.isNotEmpty) _names.putIfAbsent(_normalize(raw), () => raw);
        }
        _theme = catalogThemes.containsKey(config['tema'])
            ? config['tema'].toString()
            : 'alberdi';
        _order = mergeCategoryOrder(
          List<String>.from(
            (config['orden_categorias'] as List? ?? const []).map(
              (e) => e.toString(),
            ),
          ),
          _names.keys,
        );
        _novelties.clear();
        for (final n in (config['novedades'] as List? ?? const [])) {
          final until = DateTime.tryParse(n['hasta']?.toString() ?? '');
          if (until != null) _novelties[n['producto_id'].toString()] = until;
        }
        _changed = false;
      });
    } on PostgrestException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'No se pudo cargar. Verificá la conexión y que esté instalada la migración del catálogo.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  void _move(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _order.length) return;
    setState(() {
      final item = _order.removeAt(index);
      _order.insert(target, item);
      _changed = true;
    });
  }

  Future<void> _addNovelty() async {
    final result = await showDialog<({String id, int days})>(
      context: context,
      builder: (_) => NoveltyDialog(
        products: _products
            .where((p) => !_novelties.containsKey(p['id'].toString()))
            .toList(),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _novelties[result.id] = DateTime.now().add(Duration(days: result.days));
        _changed = true;
      });
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await Supabase.instance.client.rpc(
        'guardar_presentacion_catalogo',
        params: {
          'p_tema': _theme,
          'p_orden_categorias': _order,
          'p_novedades': _novelties.entries
              .map(
                (e) => {
                  'producto_id': e.key,
                  'hasta': e.value.toUtc().toIso8601String(),
                },
              )
              .toList(),
        },
      );
      if (mounted) setState(() => _changed = false);
      _message(
        'Guardado. Los clientes lo ven la próxima vez que abran el catálogo.',
      );
    } on PostgrestException catch (error) {
      _message(error.message);
    } catch (_) {
      _message('No se pudo guardar. Verificá la conexión.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _date(DateTime date) {
    final d = date.toLocal();
    String pad(int value) => value.toString().padLeft(2, '0');
    return '${pad(d.day)}/${pad(d.month)}';
  }

  @override
  Widget build(BuildContext context) {
    final title = Theme.of(context).textTheme.titleMedium;
    final names = {
      for (final p in _products) p['id'].toString(): p['nombre'].toString(),
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Apariencia del catálogo')),
      bottomNavigationBar: _loading || _error != null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: _saving || !_changed ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(
                    _saving
                        ? 'Guardando…'
                        : _changed
                        ? 'Guardar cambios'
                        : 'Sin cambios',
                  ),
                ),
              ),
            ),
      body: DesktopForm(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      TextButton(
                        onPressed: _load,
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const Text(
                    'Vale para todos los catálogos: los de cada cliente y los generales.',
                  ),
                  const SizedBox(height: 20),
                  Text('Color', style: title),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: catalogThemes.entries
                        .map(
                          (e) => ChoiceChip(
                            avatar: CircleAvatar(backgroundColor: e.value.color),
                            label: Text(e.value.label),
                            selected: _theme == e.key,
                            onSelected: _saving
                                ? null
                                : (_) => setState(() {
                                    _theme = e.key;
                                    _changed = true;
                                  }),
                          ),
                        )
                        .toList(),
                  ),
                  const Divider(height: 40),
                  Text('Novedades', style: title),
                  const Text(
                    'Aparecen arriba de todo. Cada una se quita sola en la fecha indicada.',
                  ),
                  ..._novelties.entries.map(
                    (e) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(names[e.key] ?? 'Producto no disponible'),
                      subtitle: Text('Hasta el ${_date(e.value)}'),
                      trailing: IconButton(
                        tooltip: 'Quitar',
                        onPressed: _saving
                            ? null
                            : () => setState(() {
                                _novelties.remove(e.key);
                                _changed = true;
                              }),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: _saving ? null : _addNovelty,
                      icon: const Icon(Icons.add),
                      label: const Text('Agregar novedad'),
                    ),
                  ),
                  const Divider(height: 40),
                  Text('Orden de las categorías', style: title),
                  const Text('Usá las flechas. La primera aparece primero.'),
                  const SizedBox(height: 8),
                  for (var i = 0; i < _order.length; i++)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: Text('${i + 1}.'),
                      title: Text(_names[_order[i]] ?? _order[i]),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Subir',
                            onPressed: _saving || i == 0
                                ? null
                                : () => _move(i, -1),
                            icon: const Icon(Icons.arrow_upward),
                          ),
                          IconButton(
                            tooltip: 'Bajar',
                            onPressed: _saving || i == _order.length - 1
                                ? null
                                : () => _move(i, 1),
                            icon: const Icon(Icons.arrow_downward),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 24),
                ],
              ),
      ),
    );
  }
}

/// Ventana para elegir un producto y cuántos días se muestra como novedad.
/// Tiene su propio buscador: se libera recién cuando la ventana termina de cerrarse.
class NoveltyDialog extends StatefulWidget {
  const NoveltyDialog({super.key, required this.products});
  final List<Map<String, dynamic>> products;
  @override
  State<NoveltyDialog> createState() => _NoveltyDialogState();
}

class _NoveltyDialogState extends State<NoveltyDialog> {
  final _search = TextEditingController();
  String? _selected;
  int _days = 15;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _normalize(_search.text);
    final matches = widget.products
        .where(
          (p) => coincideBusqueda(query, [p['nombre'], p['categoria']]),
        )
        .take(60)
        .toList();
    // Con el teclado abierto queda menos alto: la lista se achica en vez de desbordar.
    final available =
        MediaQuery.sizeOf(context).height - MediaQuery.viewInsetsOf(context).bottom;
    return AlertDialog(
      title: const Text('Agregar novedad'),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      content: SizedBox(
        width: 440,
        height: (available * 0.45).clamp(180.0, 460.0),
        child: Column(
          children: [
            TextField(
              controller: _search,
              decoration: const InputDecoration(
                labelText: 'Buscar producto o categoría',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => setState(() {}),
            ),
            Expanded(
              child: matches.isEmpty
                  ? const Center(child: Text('No hay productos con ese nombre.'))
                  : ListView.builder(
                      itemCount: matches.length,
                      itemBuilder: (context, index) {
                        final p = matches[index];
                        final id = p['id'].toString();
                        return ListTile(
                          dense: true,
                          selected: _selected == id,
                          leading: Icon(
                            _selected == id
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                          ),
                          title: Text(p['nombre'].toString()),
                          subtitle: Text(p['categoria']?.toString() ?? ''),
                          onTap: () => setState(() => _selected = id),
                        );
                      },
                    ),
            ),
            DropdownButtonFormField<int>(
              initialValue: _days,
              decoration: const InputDecoration(labelText: 'Se muestra durante'),
              items: const [7, 15, 30, 60]
                  .map((d) => DropdownMenuItem(value: d, child: Text('$d días')))
                  .toList(),
              onChanged: (value) => setState(() => _days = value ?? 15),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _selected == null
              ? null
              : () => Navigator.pop(context, (id: _selected!, days: _days)),
          child: const Text('Agregar'),
        ),
      ],
    );
  }
}
