import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_theme.dart';
import '../../core/desktop_records.dart';
import 'catalog_rules.dart';
import 'new_general_catalog_page.dart';

String _date(DateTime? date) {
  if (date == null) return '';
  String pad(int value) => value.toString().padLeft(2, '0');
  return '${pad(date.day)}/${pad(date.month)} ${pad(date.hour)}:${pad(date.minute)}';
}

/// Catálogo general: un enlace para muchos clientes, con pedidos por WhatsApp al preventista.
/// Lo usan el administrador y los preventistas que él habilita.
class GeneralCatalogPage extends StatefulWidget {
  const GeneralCatalogPage({super.key, required this.isAdmin});
  final bool isAdmin;
  @override
  State<GeneralCatalogPage> createState() => _GeneralCatalogPageState();
}

class _GeneralCatalogPageState extends State<GeneralCatalogPage> {
  List<Map<String, dynamic>> _catalogs = [];
  List<Map<String, dynamic>> _sellers = [];
  final _links = <String, String>{};
  String? _error;
  bool _loading = true;
  final _busy = <String>{};

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
      final catalogs = await db.rpc('listar_catalogos_generales');
      final sellers = widget.isAdmin
          ? await db
                .from('usuarios')
                .select('id,nombre,apellido,activo,puede_catalogo_general')
                .eq('rol', 'preventista')
                .eq('activo', true)
                .order('nombre')
          : const [];
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _catalogs = List<Map<String, dynamic>>.from(catalogs as List);
        _sellers = List<Map<String, dynamic>>.from(sellers);
        _links.clear();
        for (final c in _catalogs) {
          final id = c['id'].toString();
          final link = prefs.getString(generalCatalogLinkKey(id));
          if (link != null) _links[id] = link;
        }
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'No se pudieron cargar los catálogos. Verificá la conexión.',
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

  String _shareText(String link, DateTime? expiresAt) =>
      'Catálogo de Distribuidora Alberdi. Elegí tus productos y mandame el pedido por WhatsApp:\n$link'
      '${expiresAt == null ? '' : '\nPrecios válidos hasta el ${_date(expiresAt)}.'}';

  Future<void> _share(String link, DateTime? expiresAt) async {
    try {
      await SharePlus.instance.share(
        ShareParams(text: _shareText(link, expiresAt)),
      );
    } catch (_) {
      await _copy(link);
    }
  }

  Future<void> _copy(String link) async {
    await Clipboard.setData(ClipboardData(text: link));
    _message('Enlace copiado.');
  }

  Future<void> _open(String link) async {
    try {
      if (await launchUrl(
        Uri.parse(link),
        mode: LaunchMode.externalApplication,
      )) {
        return;
      }
    } catch (_) {
      /* Se avisa abajo. */
    }
    _message('No se pudo abrir el navegador. Copiá el enlace.');
  }

  Future<void> _create({Map<String, dynamic>? copyFrom}) async {
    final created = await Navigator.of(context).push<GeneratedGeneralCatalog>(
      MaterialPageRoute(
        builder: (_) => NewGeneralCatalogPage(copyFrom: copyFrom),
      ),
    );
    if (created == null || !mounted) return;
    await _load();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enlace listo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(created.link),
            const SizedBox(height: 12),
            Text(
              created.expiresAt == null
                  ? 'Dura 7 días.'
                  : 'Vale hasta el ${_date(created.expiresAt)}.',
            ),
            const Text(
              'Abrilo una vez para revisar los precios antes de compartirlo.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => _open(created.link),
            child: const Text('Ver'),
          ),
          TextButton(
            onPressed: () => _copy(created.link),
            child: const Text('Copiar'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _share(created.link, created.expiresAt);
            },
            icon: const Icon(Icons.share),
            label: const Text('Compartir'),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirm(String title, String text, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ==
      true;

  Future<void> _revoke(Map<String, dynamic> catalog) async {
    final id = catalog['id'].toString();
    if (!await _confirm(
      'Revocar catálogo',
      'El enlace «${catalog['nombre']}» deja de funcionar ahora para todos los que lo tengan.',
      'Revocar',
    )) {
      return;
    }
    setState(() => _busy.add(id));
    try {
      await Supabase.instance.client.rpc(
        'revocar_catalogo_general',
        params: {'p_id': id},
      );
      _message('Catálogo revocado.');
      await _load();
    } on PostgrestException catch (error) {
      _message(error.message);
    } catch (_) {
      _message('No se pudo revocar. Verificá la conexión.');
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<void> _setPermission(Map<String, dynamic> seller, bool enabled) async {
    final id = seller['id'].toString();
    if (!enabled &&
        !await _confirm(
          'Quitar permiso',
          'Los catálogos generales activos de ${seller['nombre']} dejan de funcionar ahora.',
          'Quitar',
        )) {
      return;
    }
    setState(() => _busy.add(id));
    try {
      await Supabase.instance.client.rpc(
        'habilitar_catalogo_general',
        params: {'p_usuario': id, 'p_habilitado': enabled},
      );
      await _load();
    } on PostgrestException catch (error) {
      _message(error.message);
    } catch (_) {
      _message('No se pudo guardar. Verificá la conexión.');
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  ({String text, Color color}) _status(String status) => switch (status) {
    'activo' => (text: 'Activo', color: AppColors.verde),
    'vencido' => (text: 'Vencido', color: AppColors.gris),
    'revocado' => (text: 'Revocado', color: AppColors.gris),
    _ => (text: 'Sin permiso', color: AppColors.rojo),
  };

  Widget _catalogCard(Map<String, dynamic> c) {
    final id = c['id'].toString();
    final status = c['estado']?.toString() ?? '';
    final active = status == 'activo';
    final link = _links[id];
    final expiresAt = DateTime.tryParse(
      c['vence_at']?.toString() ?? '',
    )?.toLocal();
    final createdAt = DateTime.tryParse(
      c['created_at']?.toString() ?? '',
    )?.toLocal();
    final exceptions =
        ((c['categorias'] as Map?)?.length ?? 0) +
        ((c['productos'] as Map?)?.length ?? 0);
    final label = _status(status);
    final busy = _busy.contains(id);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    c['nombre']?.toString() ?? 'Catálogo',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Chip(
                  label: Text(label.text),
                  labelStyle: TextStyle(
                    color: label.color,
                    fontWeight: FontWeight.w600,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            Text(
              'Lista ${catalogTypeLabel(c['base']?.toString() ?? '')}'
              '${exceptions == 0 ? '' : ' + $exceptions excepciones'}'
              '${widget.isAdmin ? ' · ${c['creador']}' : ''}',
            ),
            Text(
              active
                  ? 'Vence el ${_date(expiresAt)} · creado el ${_date(createdAt)}'
                  : 'Creado el ${_date(createdAt)}',
              style: const TextStyle(color: AppColors.gris),
            ),
            if (active && link == null)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'El enlace se ve solo en el teléfono donde se generó. Si no lo tenés, generá uno igual y revocá este.',
                  style: TextStyle(fontSize: 12, color: AppColors.gris),
                ),
              ),
            Wrap(
              spacing: 4,
              children: [
                if (active && link != null) ...[
                  TextButton.icon(
                    onPressed: () => _share(link, expiresAt),
                    icon: const Icon(Icons.share),
                    label: const Text('Compartir'),
                  ),
                  TextButton.icon(
                    onPressed: () => _copy(link),
                    icon: const Icon(Icons.copy),
                    label: const Text('Copiar'),
                  ),
                  TextButton.icon(
                    onPressed: () => _open(link),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Ver'),
                  ),
                ],
                TextButton.icon(
                  onPressed: busy ? null : () => _create(copyFrom: c),
                  icon: const Icon(Icons.copy_all),
                  label: const Text('Generar uno igual'),
                ),
                if (status == 'activo' || status == 'sin_permiso')
                  TextButton.icon(
                    onPressed: busy ? null : () => _revoke(c),
                    icon: const Icon(Icons.link_off),
                    label: const Text('Revocar'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.rojo,
                    ),
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
    final active = _catalogs.where((c) => c['estado'] == 'activo').toList();
    final others = _catalogs.where((c) => c['estado'] != 'activo').toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Catálogo general')),
      floatingActionButton: _loading || _error != null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _create(),
              icon: const Icon(Icons.add_link),
              label: const Text('Nuevo catálogo'),
            ),
      body: DesktopForm(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
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
              )
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  children: [
                    const Text(
                      'Un enlace para muchos clientes: ven productos y precios, y te mandan el pedido por WhatsApp. Dura 7 días o hasta que lo revoques.',
                    ),
                    const SizedBox(height: 12),
                    if (_catalogs.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'Todavía no generaste catálogos generales.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ...active.map(_catalogCard),
                    if (others.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Anteriores',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      ...others.map(_catalogCard),
                    ],
                    if (widget.isAdmin) ...[
                      const Divider(height: 36),
                      Text(
                        'Preventistas que pueden generar',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (_sellers.isEmpty)
                        const Text('No hay preventistas activos.'),
                      ..._sellers.map(
                        (s) => SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            '${s['nombre']} ${s['apellido'] ?? ''}'.trim(),
                          ),
                          value: s['puede_catalogo_general'] == true,
                          onChanged: _busy.contains(s['id'].toString())
                              ? null
                              : (value) => _setPermission(s, value),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}
