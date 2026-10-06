import '../../core/desktop_records.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'price_list_config.dart';
import 'price_list_pdf_service.dart';

class PriceListPage extends StatefulWidget {
  final List<Map<String, dynamic>> productos;
  final String usuarioId;
  const PriceListPage({
    super.key,
    required this.productos,
    required this.usuarioId,
  });
  @override
  State<PriceListPage> createState() => _PriceListPageState();
}

class _PriceListPageState extends State<PriceListPage> {
  String _modo = 'normal', _base = 'normal';
  Map<String, String> _excepciones = {};
  Map<String, PriceListConfig> _plantillas = {};
  bool _ocupado = false, _plantillasListas = false;
  String? _plantilla;
  String get _storageKey => 'listas_precios_v1_${widget.usuarioId}';
  PriceListConfig get _config => PriceListConfig(
    base: _modo == 'personalizada' ? _base : _modo,
    excepciones: _modo == 'personalizada' ? _excepciones : {},
  );
  List<Map<String, dynamic>> get _incluidos =>
      widget.productos.where(PriceListConfig.incluir).toList();
  Map<String, List<Map<String, dynamic>>> get _categorias {
    final result = <String, List<Map<String, dynamic>>>{};
    final sorted = _incluidos
      ..sort(
        (a, b) => a['nombre'].toString().compareTo(b['nombre'].toString()),
      );
    for (final p in sorted) {
      final key = PriceListConfig.claveCategoria(p['categoria'].toString());
      result.putIfAbsent(key, () => []).add(p);
    }
    return Map.fromEntries(
      result.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
  }

  String _label(String value) => {
    'normal': 'Normal',
    'promo': 'Promo',
    'interior': 'Interior',
    'personalizada': 'Personalizada',
  }[value]!;
  String _money(double value) => '\$${value.toStringAsFixed(2)}';
  void _mensaje(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  void initState() {
    super.initState();
    _cargarPlantillas();
  }

  Future<void> _cargarPlantillas() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      final json = raw == null
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(jsonDecode(raw));
      final templates = json.map(
        (k, v) =>
            MapEntry(k, PriceListConfig.fromJson(Map<String, dynamic>.from(v))),
      );
      if (!mounted) return;
      setState(() {
        _plantillas = templates;
        _plantillasListas = true;
      });
    } catch (_) {
      _mensaje(
        'No se pudieron cargar las plantillas. Podés generar la lista sin guardarla.',
      );
    }
  }

  Future<void> _guardarPlantilla() async {
    var nombre = _plantilla ?? '';
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Guardar combinación'),
        content: TextFormField(
          initialValue: nombre,
          onChanged: (value) => nombre = value,
          maxLength: 80,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nombre interno',
            helperText: 'No aparecerá en el PDF.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (nombre.trim().isNotEmpty) {
                Navigator.pop(context, nombre.trim());
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (name == null || !mounted) return;
    if (_plantillas.containsKey(name)) {
      final overwrite = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Actualizar plantilla'),
          content: Text('¿Reemplazar la combinación guardada como «$name»?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Reemplazar'),
            ),
          ],
        ),
      );
      if (overwrite != true || !mounted) return;
    }
    try {
      final next = {..._plantillas, name: _config};
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(
        _storageKey,
        jsonEncode(next.map((k, v) => MapEntry(k, v.toJson()))),
      )) {
        throw StateError('No se guardó');
      }
      if (!mounted) return;
      setState(() {
        _plantillas = next;
        _plantilla = name;
      });
      _mensaje('Combinación guardada en este dispositivo.');
    } catch (_) {
      _mensaje('No se pudo guardar la combinación.');
    }
  }

  Future<void> _generar() async {
    setState(() => _ocupado = true);
    try {
      final pdf = await PriceListPdfService.generarPdf(
        tipoPrecio: _modo == 'personalizada' ? _base : _modo,
        productos: widget.productos,
        configuracion: _modo == 'personalizada' ? _config : null,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PriceListPreviewPage(bytes: pdf)),
      );
    } catch (e) {
      _mensaje('No se pudo generar la lista: $e');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categorias = _categorias;
    final invalidos = <String>[];
    var ceros = 0;
    for (final p in _incluidos) {
      try {
        if (_config.precioPara(p) == 0) ceros++;
      } catch (_) {
        invalidos.add(p['nombre'].toString());
      }
    }
    final faltantes = _excepciones.keys
        .where((k) => !categorias.containsKey(k))
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Lista de precios')),
      body: DesktopForm(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Elegí los precios de la lista',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const Text(
              'Las modalidades y nombres de plantillas son internos. El cliente recibe solamente el producto y su precio final.',
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [...PriceListConfig.tipos, 'personalizada']
                  .map(
                    (m) => ChoiceChip(
                      label: Text(_label(m)),
                      selected: _modo == m,
                      onSelected: _ocupado
                          ? null
                          : (_) => setState(() => _modo = m),
                    ),
                  )
                  .toList(),
            ),
            if (_modo == 'personalizada') ...[
              const SizedBox(height: 20),
              if (_plantillas.isNotEmpty)
                DropdownButtonFormField<String>(
                  key: ValueKey(_plantilla),
                  initialValue: _plantilla,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Plantilla guardada en este dispositivo',
                  ),
                  items: _plantillas.keys
                      .map(
                        (name) => DropdownMenuItem(
                          value: name,
                          child: Text(name, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: _ocupado
                      ? null
                      : (name) {
                          if (name == null) return;
                          final c = _plantillas[name]!;
                          setState(() {
                            _plantilla = name;
                            _base = c.base;
                            _excepciones = Map.of(c.excepciones);
                          });
                        },
                ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: ValueKey('base_$_base'),
                initialValue: _base,
                decoration: const InputDecoration(
                  labelText: 'Precio base para todas las categorías',
                ),
                items: PriceListConfig.tipos
                    .map(
                      (t) => DropdownMenuItem(value: t, child: Text(_label(t))),
                    )
                    .toList(),
                onChanged: _ocupado
                    ? null
                    : (v) {
                        if (v != null) setState(() => _base = v);
                      },
              ),
              const SizedBox(height: 12),
              const Text(
                'Excepciones por categoría',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const Text('Las categorías nuevas usarán el precio base.'),
              if (faltantes.isNotEmpty)
                Text(
                  'Categorías guardadas que no están en esta lista: ${faltantes.join(', ')}.',
                ),
              ...categorias.entries.map(
                (e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('${e.key}_${_excepciones[e.key]}'),
                    initialValue: _excepciones[e.key] ?? '',
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: e.value.first['categoria'].toString().trim(),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: '',
                        child: Text('Usar base (${_label(_base)})'),
                      ),
                      ...PriceListConfig.tipos.map(
                        (t) =>
                            DropdownMenuItem(value: t, child: Text(_label(t))),
                      ),
                    ],
                    onChanged: _ocupado
                        ? null
                        : (v) => setState(() {
                            if (v == null || v.isEmpty) {
                              _excepciones.remove(e.key);
                            } else {
                              _excepciones[e.key] = v;
                            }
                          }),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _plantillasListas && !_ocupado
                      ? _guardarPlantilla
                      : null,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Guardar combinación'),
                ),
              ),
            ],
            const SizedBox(height: 20),
            Text(
              'Revisión interna · ${_incluidos.length} productos',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              'Se incluyen productos activos, visibles y con categoría. Excluidos: ${widget.productos.length - _incluidos.length}.',
            ),
            if (ceros > 0)
              Text(
                'Atención: $ceros productos figurarán con precio \$0. Revisalos antes de compartir.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (invalidos.isNotEmpty)
              Text(
                'Corregí los precios faltantes o inválidos: ${invalidos.join(', ')}.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ...categorias.entries.map(
              (e) => ExpansionTile(
                title: Text(e.value.first['categoria'].toString().trim()),
                subtitle: Text(
                  '${_label(_config.tipoPara(e.key))} · ${e.value.length} productos',
                ),
                children: e.value.map((p) {
                  String precio;
                  try {
                    precio = _money(_config.precioPara(p));
                  } catch (_) {
                    precio = 'Precio inválido';
                  }
                  return ListTile(
                    title: Text(p['nombre'].toString()),
                    subtitle: Text(precio),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _ocupado || _incluidos.isEmpty || invalidos.isNotEmpty
                  ? null
                  : _generar,
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: Text(_ocupado ? 'Preparando…' : 'Generar y revisar PDF'),
            ),
          ],
        ),
      ),
    );
  }
}

class PriceListPreviewPage extends StatefulWidget {
  final Uint8List bytes;
  const PriceListPreviewPage({super.key, required this.bytes});
  @override
  State<PriceListPreviewPage> createState() => _PriceListPreviewPageState();
}

class _PriceListPreviewPageState extends State<PriceListPreviewPage> {
  bool _ocupado = false;
  late final String _nombre =
      'Lista_Precios_${DateTime.now().toIso8601String().substring(0, 10)}.pdf';
  Future<void> _exportar(bool compartir) async {
    setState(() => _ocupado = true);
    try {
      if (compartir) {
        final box = context.findRenderObject() as RenderBox?;
        final origin = box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size;
        final dir = await Directory.systemTemp.createTemp('lista_precios_');
        final file = File('${dir.path}${Platform.pathSeparator}$_nombre');
        await file.writeAsBytes(widget.bytes, flush: true);
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path)],
            subject: 'Lista de precios',
            text: 'Lista de precios - Distribuidora Alberdi',
            sharePositionOrigin: origin,
          ),
        );
      } else {
        final path = await FilePicker.saveFile(
          dialogTitle: 'Guardar lista de precios',
          fileName: _nombre,
          bytes: widget.bytes,
          mimeType: 'application/pdf',
          type: FileType.custom,
          allowedExtensions: ['pdf'],
        );
        if (path != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('PDF guardado. Podés adjuntarlo en WhatsApp.'),
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              compartir
                  ? 'No se pudo compartir. Probá Guardar PDF y adjuntarlo en WhatsApp.'
                  : 'No se pudo guardar el PDF.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Vista previa del PDF')),
    body: DesktopForm(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _ocupado ? null : () => _exportar(true),
                  icon: const Icon(Icons.share),
                  label: const Text('Compartir PDF'),
                ),
                OutlinedButton.icon(
                  onPressed: _ocupado ? null : () => _exportar(false),
                  icon: const Icon(Icons.save_alt),
                  label: const Text('Guardar PDF'),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Elegí WhatsApp en las opciones para compartir. En Windows también podés guardar el PDF y adjuntarlo.',
            ),
          ),
          Expanded(
            child: PdfPreview(
              build: (_) async => widget.bytes,
              allowPrinting: false,
              allowSharing: false,
              canChangeOrientation: false,
              canChangePageFormat: false,
              canDebug: false,
            ),
          ),
        ],
      ),
    ),
  );
}
