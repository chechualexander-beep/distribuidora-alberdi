import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_config.dart';
import '../../core/desktop_records.dart';
import '../../core/whatsapp_link.dart';
import 'catalog_rules.dart';

/// Resultado de generar un catálogo general: el enlace solo existe en este dispositivo.
class GeneratedGeneralCatalog {
  const GeneratedGeneralCatalog(this.id, this.link, this.expiresAt);
  final String id;
  final String link;
  final DateTime? expiresAt;
}

String generalCatalogLinkKey(String id) =>
    appConfig.catalogPreferenceKey('general:link:$id');

String get _whatsappKey => appConfig.catalogPreferenceKey('general:whatsapp');

/// Enlace público a partir del token: `sitio del entorno` + `#general=` + token.
String generalCatalogLink(String token) {
  const override = String.fromEnvironment('CATALOGO_URL');
  // Sin barra antes del '#', igual que los enlaces de cliente: WhatsApp guardó la vista
  // previa vieja (sin imagen) de la dirección con barra.
  final base = Uri.parse(override.isNotEmpty ? override : appConfig.catalogUrl);
  final site = base.path == '/' ? base.replace(path: '') : base;
  return site.replace(fragment: 'general=$token').toString();
}

class NewGeneralCatalogPage extends StatefulWidget {
  const NewGeneralCatalogPage({super.key, this.copyFrom});

  /// Fila de listar_catalogos_generales para generar uno igual (por ejemplo, al vencer).
  final Map<String, dynamic>? copyFrom;

  @override
  State<NewGeneralCatalogPage> createState() => _NewGeneralCatalogPageState();
}

class _NewGeneralCatalogPageState extends State<NewGeneralCatalogPage> {
  final _name = TextEditingController(text: 'Catálogo general');
  final _whatsapp = TextEditingController();
  final _categoryRules = <String, String>{};
  final _productRules = <String, String>{};
  List<Map<String, dynamic>> _products = [];
  String? _base;
  String? _error;
  bool _loading = true, _saving = false;

  @override
  void initState() {
    super.initState();
    final from = widget.copyFrom;
    if (from != null) {
      _name.text = from['nombre']?.toString() ?? _name.text;
      _base = from['base']?.toString();
      _whatsapp.text = from['whatsapp']?.toString() ?? '';
      _categoryRules.addAll(
        Map<String, String>.from((from['categorias'] as Map?) ?? const {}),
      );
      _productRules.addAll(
        Map<String, String>.from((from['productos'] as Map?) ?? const {}),
      );
    }
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _whatsapp.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final products = await Supabase.instance.client
          .from('productos')
          .select('id,nombre,categoria')
          .eq('activo', true)
          .eq('visible_preventistas', true)
          .order('nombre');
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _products = List<Map<String, dynamic>>.from(products);
        if (_whatsapp.text.isEmpty) {
          _whatsapp.text = prefs.getString(_whatsappKey) ?? '';
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No se pudieron cargar los productos.');
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

  Future<void> _addRule(bool product) async {
    final rule = await askCatalogRule(context, _products, product: product);
    if (rule != null && mounted) {
      setState(
        () => (product ? _productRules : _categoryRules)[rule.key] = rule.value,
      );
    }
  }

  Future<void> _generate() async {
    if (_saving) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      _message('Poné un nombre al catálogo.');
      return;
    }
    if (_base == null) {
      _message('Elegí la lista base.');
      return;
    }
    final number = normalizeArgentineWhatsApp(
      _whatsapp.text,
      nationalMobileConfirmed: true,
    );
    if (number == null) {
      _message(
        'Revisá tu número de WhatsApp: código de área y número, sin 0 ni 15.',
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final response = await Supabase.instance.client.rpc(
        'crear_catalogo_general',
        params: {
          'p_nombre': name,
          'p_base': _base,
          'p_categorias': _categoryRules,
          'p_productos': _productRules,
          'p_whatsapp': number,
        },
      );
      final result = Map<String, dynamic>.from(response as Map);
      final id = result['id'].toString();
      final link = generalCatalogLink(result['token'].toString());
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(generalCatalogLinkKey(id), link);
        await prefs.setString(_whatsappKey, number);
      } catch (_) {
        /* El enlace igual se muestra al volver. */
      }
      if (!mounted) return;
      Navigator.of(context).pop(
        GeneratedGeneralCatalog(
          id,
          link,
          DateTime.tryParse(result['vence_at']?.toString() ?? '')?.toLocal(),
        ),
      );
    } on PostgrestException catch (error) {
      _message(error.message);
    } catch (_) {
      _message('No se pudo generar. Verificá la conexión.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = Theme.of(context).textTheme.titleMedium;
    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo catálogo general')),
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
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  TextField(
                    controller: _name,
                    enabled: !_saving,
                    maxLength: 60,
                    decoration: const InputDecoration(
                      labelText: 'Nombre (lo ve el cliente)',
                      hintText: 'Ej.: Ofertas de la semana',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _base,
                    decoration: const InputDecoration(
                      labelText: 'Lista base',
                      border: OutlineInputBorder(),
                    ),
                    items: catalogPriceTypes
                        .map(
                          (t) => DropdownMenuItem(
                            value: t,
                            child: Text(catalogTypeLabel(t)),
                          ),
                        )
                        .toList(),
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _base = value),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Lista única: elegí la base y no agregues excepciones. Personalizada: sumá excepciones. El cliente ve solo el precio final.',
                  ),
                  const SizedBox(height: 20),
                  Text('Excepciones por categoría', style: title),
                  CatalogRulesList(
                    rules: _categoryRules,
                    products: _products,
                    product: false,
                    onRemove: _saving
                        ? null
                        : (key) => setState(() => _categoryRules.remove(key)),
                  ),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : () => _addRule(false),
                    icon: const Icon(Icons.add),
                    label: const Text('Agregar categoría'),
                  ),
                  const SizedBox(height: 16),
                  Text('Excepciones por producto', style: title),
                  CatalogRulesList(
                    rules: _productRules,
                    products: _products,
                    product: true,
                    onRemove: _saving
                        ? null
                        : (key) => setState(() => _productRules.remove(key)),
                  ),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : () => _addRule(true),
                    icon: const Icon(Icons.add),
                    label: const Text('Agregar producto'),
                  ),
                  const Text(
                    'La excepción de producto tiene prioridad sobre la categoría.',
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _whatsapp,
                    enabled: !_saving,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Tu WhatsApp (ahí llegan los pedidos)',
                      hintText: 'Ej.: 3794 123456',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _saving ? null : _generate,
                    icon: const Icon(Icons.link),
                    label: Text(_saving ? 'Generando…' : 'Generar enlace'),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'El enlace dura 7 días o hasta que lo revoques. Quien lo tenga ve los productos y precios, y te manda el pedido por WhatsApp.',
                  ),
                ],
              ),
      ),
    );
  }
}
