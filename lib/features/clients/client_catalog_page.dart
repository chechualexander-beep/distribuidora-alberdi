import '../../core/desktop_records.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class ClientCatalogPage extends StatefulWidget {
  final Map<String, dynamic> cliente;
  const ClientCatalogPage({super.key, required this.cliente});
  @override
  State<ClientCatalogPage> createState() => _ClientCatalogPageState();
}

class _ClientCatalogPageState extends State<ClientCatalogPage> {
  static const _types = ['normal', 'promo', 'interior'];
  final _url = TextEditingController();
  final _categoryRules = <String, String>{};
  final _productRules = <String, String>{};
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _sellers = [];
  String _sellerId = '';
  String _savedSellerId = '';
  String? _base;
  String? _link;
  String? _error;
  DateTime? _expiresAt;
  bool get _expired =>
      _expiresAt != null && !DateTime.now().isBefore(_expiresAt!);
  bool _loading = true, _saving = false, _active = false, _hasToken = false;
  String get _expiryLabel {
    final date = _expiresAt!;
    String pad(int value) => value.toString().padLeft(2, '0');
    return '${pad(date.day)}/${pad(date.month)}/${date.year} ${pad(date.hour)}:${pad(date.minute)}';
  }

  String get _id => widget.cliente['id'].toString();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = Supabase.instance.client;
      final config = await db
          .from('catalogos_clientes')
          .select()
          .eq('cliente_id', _id)
          .maybeSingle();
      final products = await db
          .from('productos')
          .select(
            'id,nombre,categoria,descripcion,precio_normal,precio_promo,precio_interior',
          )
          .eq('activo', true)
          .eq('visible_preventistas', true)
          .order('nombre');
      final sellers = await db
          .from('usuarios')
          .select('id,nombre,apellido,activo')
          .eq('rol', 'preventista')
          .order('nombre');
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _products = List<Map<String, dynamic>>.from(products);
        _sellerId = config?['preventista_comision_id']?.toString() ?? '';
        _savedSellerId = _sellerId;
        _sellers = List<Map<String, dynamic>>.from(
          sellers,
        ).where((s) => s['activo'] == true || s['id'] == _sellerId).toList();
        _base =
            config?['base']?.toString() ??
            widget.cliente['tipo_precio_habitual']?.toString();
        _active = config?['activo'] == true;
        _expiresAt = DateTime.tryParse(
          config?['vence_at']?.toString() ?? '',
        )?.toLocal();
        _hasToken = config?['token_hash'] != null;
        _categoryRules.clear();
        _productRules.clear();
        if (config != null) {
          _categoryRules.addAll(
            Map<String, String>.from(config['categorias'] as Map),
          );
          _productRules.addAll(
            Map<String, String>.from(config['productos'] as Map),
          );
        }
        _url.text =
            prefs.getString('catalogo_url') ??
            const String.fromEnvironment(
              'CATALOGO_URL',
              defaultValue: 'https://distribuidora-alberdi.pages.dev',
            );
        final stored = prefs.getString('catalogo_link_$_id');
        // Solo se conserva localmente; otro dispositivo deberá renovar el enlace.
        _link =
            _hasToken &&
                prefs.getString('catalogo_hash_$_id') == config?['token_hash']
            ? stored
            : null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error =
              'No se pudo cargar el catálogo. Verificá la conexión y que esté instalada la migración de catálogo en Supabase.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Uri? _catalogUri() {
    final uri = Uri.tryParse(_url.text.trim());
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      return null;
    }
    if (uri.scheme == 'https' ||
        (uri.scheme == 'http' &&
            ['localhost', '127.0.0.1'].contains(uri.host))) {
      return uri;
    }
    return null;
  }

  Future<void> _save({bool renew = false, bool? active}) async {
    if (_saving) return;
    if (_base == null) {
      _message('Elegí la lista base antes de continuar.');
      return;
    }
    if (_hasToken && !renew && _sellerId != _savedSellerId) {
      _message('Usá «Renovar y habilitar enlace» para cambiar el preventista.');
      return;
    }
    final uri = _catalogUri();
    if (renew && uri == null) {
      _message(
        'Ingresá la dirección HTTPS donde se publicó el catálogo, sin parámetros.',
      );
      return;
    }
    if (renew && _hasToken) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Renovar enlace'),
          content: const Text(
            'El enlace anterior dejará de funcionar. Compartí el nuevo enlace con el cliente.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Renovar'),
            ),
          ],
        ),
      );
      if (accepted != true || !mounted) return;
    }
    setState(() {
      _saving = true;
    });
    try {
      final token = await Supabase.instance.client.rpc(
        'configurar_catalogo_cliente_v2',
        params: {
          'p_cliente_id': _id,
          'p_base': _base,
          'p_categorias': _categoryRules,
          'p_productos': _productRules,
          'p_renovar': renew,
          'p_activo': active ?? _active,
          'p_preventista_id': _sellerId.isEmpty ? null : _sellerId,
        },
      );
      if (!mounted) return;
      setState(() {
        _active = active ?? _active;
        _savedSellerId = _sellerId;
        _hasToken = true;
        if (token != null && uri != null) {
          _link = uri.replace(fragment: 'token=$token').toString();
        }
      });
      // La URL recién generada queda visible aunque falle el almacenamiento local.
      try {
        final prefs = await SharedPreferences.getInstance();
        if (uri != null) await prefs.setString('catalogo_url', uri.toString());
        if (_link != null) await prefs.setString('catalogo_link_$_id', _link!);
        if (token != null && _link != null) {
          final config = await Supabase.instance.client
              .from('catalogos_clientes')
              .select('token_hash,vence_at')
              .eq('cliente_id', _id)
              .single();
          if (mounted) {
            setState(() {
              _expiresAt = DateTime.tryParse(
                config['vence_at'].toString(),
              )?.toLocal();
            });
          }
          await prefs.setString(
            'catalogo_hash_$_id',
            config['token_hash'].toString(),
          );
        }
      } catch (_) {
        /* El enlace sigue disponible en esta pantalla. */
      }
      _message(
        renew
            ? 'Enlace generado por 12 horas. Revisá el catálogo antes de compartirlo.'
            : 'Configuración guardada.',
      );
    } on PostgrestException catch (error) {
      _message(error.message);
    } catch (_) {
      _message('No se pudo guardar. Verificá la conexión.');
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  String _typeLabel(String type) =>
      '${type[0].toUpperCase()}${type.substring(1)}';

  Future<void> _addRule(bool product) async {
    final choices = <String, String>{};
    for (final p in _products) {
      if (product) {
        choices[p['id'].toString()] = p['nombre'].toString();
      } else {
        final category = p['categoria']?.toString().trim() ?? '';
        if (category.isNotEmpty) choices[category.toLowerCase()] = category;
      }
    }
    final entries = choices.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    String? selected;
    String type = 'normal';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(
            product ? 'Excepción por producto' : 'Excepción por categoría',
          ),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: product ? 'Producto' : 'Categoría',
                  ),
                  items: entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => update(() {
                    selected = value;
                  }),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Lista'),
                  items: _types
                      .map(
                        (t) => DropdownMenuItem(
                          value: t,
                          child: Text(_typeLabel(t)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => update(() {
                    type = value!;
                  }),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: selected == null
                  ? null
                  : () => Navigator.pop(context, true),
              child: const Text('Agregar'),
            ),
          ],
        ),
      ),
    );
    if (accepted == true && mounted) {
      setState(() {
        (product ? _productRules : _categoryRules)[selected!] = type;
      });
    }
  }

  Widget _rules(Map<String, String> rules, bool product) => Column(
    children: rules.entries.map((e) {
      final match = _products.where((p) => p['id'].toString() == e.key);
      final name = product
          ? (match.isEmpty
                ? 'Producto no disponible (${e.key})'
                : match.first['nombre'].toString())
          : e.key;
      return ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(name),
        subtitle: Text(_typeLabel(e.value)),
        trailing: IconButton(
          tooltip: 'Quitar excepción',
          onPressed: _saving
              ? null
              : () => setState(() {
                  rules.remove(e.key);
                }),
          icon: const Icon(Icons.delete_outline),
        ),
      );
    }).toList(),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Catálogo del cliente')),
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
                Text(
                  widget.cliente['nombre_comercio']?.toString() ?? 'Cliente',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Estas reglas son internas. El cliente ve únicamente el precio final de cada producto.',
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  initialValue: _base,
                  decoration: const InputDecoration(
                    labelText: 'Lista base',
                    border: OutlineInputBorder(),
                  ),
                  items: _types
                      .map(
                        (t) => DropdownMenuItem(
                          value: t,
                          child: Text(_typeLabel(t)),
                        ),
                      )
                      .toList(),
                  onChanged: _saving
                      ? null
                      : (value) => setState(() {
                          _base = value;
                        }),
                ),
                const SizedBox(height: 20),
                Text(
                  'Excepciones por categoría',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                _rules(_categoryRules, false),
                OutlinedButton.icon(
                  onPressed: _saving ? null : () => _addRule(false),
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar categoría'),
                ),
                const SizedBox(height: 16),
                Text(
                  'Excepciones por producto',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                _rules(_productRules, true),
                OutlinedButton.icon(
                  onPressed: _saving ? null : () => _addRule(true),
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar producto'),
                ),
                const Text(
                  'La excepción de producto tiene prioridad sobre la categoría.',
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  initialValue: _sellerId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Preventista para pedidos de este enlace',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Sin preventista / sin comisión'),
                    ),
                    ..._sellers.map(
                      (seller) => DropdownMenuItem(
                        value: seller['id'].toString(),
                        enabled: seller['activo'] == true,
                        child: Text(
                          '${seller['nombre']} ${seller['apellido'] ?? ''}${seller['activo'] == true ? '' : ' (inactivo)'}',
                        ),
                      ),
                    ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() {
                          _sellerId = value ?? '';
                        }),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Opcional. Se aplica la comisión del producto según su lista de precio, sobre lo entregado. Cambiar el preventista requiere renovar el enlace y no modifica pedidos anteriores.',
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _saving ? null : () => _save(),
                  child: Text(_saving ? 'Guardando…' : 'Guardar reglas'),
                ),
                const Divider(height: 36),
                TextField(
                  controller: _url,
                  enabled: !_saving,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Dirección web del catálogo',
                    hintText: 'https://…',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _expired
                      ? 'Enlace vencido: renovalo para recibir pedidos'
                      : _active
                      ? 'Catálogo habilitado'
                      : 'Catálogo deshabilitado',
                ),
                if (_expiresAt != null) Text('Vence: $_expiryLabel'),
                const Text(
                  'Cada enlace dura 12 horas desde su generación. Guardar reglas no extiende el plazo.',
                ),
                OutlinedButton.icon(
                  onPressed: _saving
                      ? null
                      : () => _save(renew: true, active: true),
                  icon: const Icon(Icons.link),
                  label: Text(
                    _hasToken
                        ? 'Renovar y habilitar enlace'
                        : 'Generar y habilitar enlace',
                  ),
                ),
                if (_hasToken)
                  TextButton(
                    onPressed: _saving || (!_active && _expired)
                        ? null
                        : () => _save(active: !_active),
                    child: Text(
                      _active ? 'Deshabilitar catálogo' : 'Habilitar catálogo',
                    ),
                  ),
                if (_link != null) ...[
                  const SizedBox(height: 12),
                  SelectableText(_link!),
                  Wrap(
                    spacing: 12,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _saving || !_active || _expired
                            ? null
                            : () async {
                                try {
                                  final opened = await launchUrl(
                                    Uri.parse(_link!),
                                    mode: LaunchMode.externalApplication,
                                  );
                                  if (!opened) {
                                    _message(
                                      'No se pudo abrir el navegador. Copiá el enlace.',
                                    );
                                  }
                                } catch (_) {
                                  _message(
                                    'No se pudo abrir el navegador. Copiá el enlace.',
                                  );
                                }
                              },
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Ver catálogo'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _saving || !_active || _expired
                            ? null
                            : () async {
                                await Clipboard.setData(
                                  ClipboardData(text: _link!),
                                );
                                _message('Enlace copiado.');
                              },
                        icon: const Icon(Icons.copy),
                        label: const Text('Copiar enlace'),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                const Text(
                  'Quien tenga el enlace puede ver el catálogo y enviar pedidos. Si lo renovás, el enlace anterior deja de funcionar. Los pedidos ingresan pendientes. Si elegís un preventista, quedan a su nombre; de lo contrario, quedan a nombre del administrador, sin comisión.',
                ),
              ],
            ),
    ),
  );
}
