import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_theme.dart';
import '../../core/desktop_records.dart';
import 'product_photo.dart';

/// Administrador: quién puede cargar fotos y revisión de las fotos cargadas por preventistas.
/// Las fotos se publican directo; acá se aprueban ("Está bien") o se deshacen.
class ProductPhotoReviewPage extends StatefulWidget {
  const ProductPhotoReviewPage({super.key});
  @override
  State<ProductPhotoReviewPage> createState() => _ProductPhotoReviewPageState();
}

class _ProductPhotoReviewPageState extends State<ProductPhotoReviewPage> {
  List<Map<String, dynamic>> _changes = [];
  List<Map<String, dynamic>> _sellers = [];
  final _busy = <String>{};
  String? _error;
  bool _loading = true;

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
      final changes = await db.rpc('listar_fotos_recientes');
      final sellers = await db
          .from('usuarios')
          .select('id,nombre,apellido,puede_cargar_fotos')
          .eq('rol', 'preventista')
          .eq('activo', true)
          .order('nombre');
      if (!mounted) return;
      setState(() {
        _changes = List<Map<String, dynamic>>.from(changes as List);
        _sellers = List<Map<String, dynamic>>.from(sellers);
      });
    } on PostgrestException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'No se pudo cargar. Verificá la conexión y que esté instalada la migración de fotos.',
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

  Future<void> _review(Map<String, dynamic> change, {required bool undo}) async {
    final id = change['id'].toString();
    setState(() => _busy.add(id));
    try {
      await Supabase.instance.client.rpc(
        'revisar_foto_producto',
        params: {'p_id': change['id'], 'p_deshacer': undo},
      );
      if (!mounted) return;
      setState(() => _changes.removeWhere((c) => c['id'].toString() == id));
      if (undo) _message('Listo: volvió la foto anterior.');
    } on PostgrestException catch (error) {
      _message(error.message);
    } catch (_) {
      _message('No se pudo guardar. Verificá la conexión.');
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<void> _approveAll() async {
    final pending = List<Map<String, dynamic>>.from(_changes);
    for (final change in pending) {
      if (!mounted) return;
      await _review(change, undo: false);
    }
  }

  Future<void> _setPermission(Map<String, dynamic> seller, bool enabled) async {
    final id = seller['id'].toString();
    setState(() => _busy.add(id));
    try {
      await Supabase.instance.client.rpc(
        'habilitar_carga_fotos',
        params: {'p_usuario': id, 'p_habilitado': enabled},
      );
      if (mounted) setState(() => seller['puede_cargar_fotos'] = enabled);
    } on PostgrestException catch (error) {
      _message(error.message);
    } catch (_) {
      _message('No se pudo guardar. Verificá la conexión.');
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  String _date(String? iso) {
    final d = DateTime.tryParse(iso ?? '')?.toLocal();
    if (d == null) return '';
    String pad(int value) => value.toString().padLeft(2, '0');
    return '${pad(d.day)}/${pad(d.month)} ${pad(d.hour)}:${pad(d.minute)}';
  }

  Widget _photo(String label, String? path) => Column(
    children: [
      Text(label, style: const TextStyle(fontSize: 12, color: AppColors.gris)),
      const SizedBox(height: 4),
      ProductPhoto(path: path, size: 96),
      if (path == null || path.isEmpty)
        const Text('Sin foto', style: TextStyle(fontSize: 12)),
    ],
  );

  Widget _changeCard(Map<String, dynamic> c) {
    final id = c['id'].toString();
    final busy = _busy.contains(id);
    final replacedAgain = c['foto_actual'] != c['foto_nueva'];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              c['producto']?.toString() ?? 'Producto',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text('${c['usuario']} · ${_date(c['created_at']?.toString())}'),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _photo('Antes', c['foto_anterior']?.toString()),
                const Icon(Icons.arrow_forward),
                _photo('Ahora', c['foto_nueva']?.toString()),
              ],
            ),
            if (replacedAgain)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Después se volvió a cambiar: revisá el cambio más reciente.',
                  style: TextStyle(color: AppColors.naranja),
                ),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              alignment: WrapAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: busy || replacedAgain
                      ? null
                      : () => _review(c, undo: true),
                  icon: const Icon(Icons.undo),
                  label: const Text('Deshacer'),
                  style: TextButton.styleFrom(foregroundColor: AppColors.rojo),
                ),
                FilledButton.icon(
                  onPressed: busy ? null : () => _review(c, undo: false),
                  icon: const Icon(Icons.check),
                  label: const Text('Está bien'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fotos de preventistas'),
        actions: [
          if (_changes.isNotEmpty && !_loading)
            TextButton(
              onPressed: _busy.isEmpty ? _approveAll : null,
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              child: const Text('Todo bien'),
            ),
        ],
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
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      'Quiénes pueden cargar fotos',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Text(
                      'Solo pueden poner o quitar la foto de un producto: no ven ni cambian costos y no editan productos.',
                    ),
                    if (_sellers.isEmpty)
                      const Text('No hay preventistas activos.'),
                    ..._sellers.map(
                      (s) => SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '${s['nombre']} ${s['apellido'] ?? ''}'.trim(),
                        ),
                        value: s['puede_cargar_fotos'] == true,
                        onChanged: _busy.contains(s['id'].toString())
                            ? null
                            : (value) => _setPermission(s, value),
                      ),
                    ),
                    const Divider(height: 32),
                    Text(
                      'Para revisar (${_changes.length})',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Text(
                      'Ya se ven en el catálogo. "Deshacer" vuelve a la foto anterior.',
                    ),
                    const SizedBox(height: 8),
                    if (_changes.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'No hay fotos nuevas para revisar.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ..._changes.map(_changeCard),
                  ],
                ),
              ),
      ),
    );
  }
}
