import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'product_photo.dart';

class ProductPhotoDialog extends StatefulWidget {
  final Map<String, dynamic> product;
  const ProductPhotoDialog({super.key, required this.product});

  @override
  State<ProductPhotoDialog> createState() => _ProductPhotoDialogState();
}

class _ProductPhotoDialogState extends State<ProductPhotoDialog> {
  Uint8List? _bytes;
  bool _busy = false;
  String? _error;

  /// La cámara solo existe en el celular (Android/iOS); en Windows se elige un archivo.
  static bool get cameraAvailable =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> _pick({bool camera = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      Uint8List? raw;
      if (camera) {
        final shot = await ImagePicker().pickImage(
          source: ImageSource.camera,
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 90,
        );
        raw = await shot?.readAsBytes();
      } else {
        final file = await FilePicker.pickFile(
          type: FileType.custom,
          allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
        );
        if (file == null) return;
        if (await file.length() > 20 * 1024 * 1024) {
          throw const FormatException('La imagen supera los 20 MB.');
        }
        raw = await file.readAsBytes();
      }
      if (raw == null) return;
      final bytes = await compute(prepareProductPhoto, raw);
      if (mounted) {
        setState(() {
          _bytes = bytes;
        });
      }
    } on FormatException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'No se pudo abrir la imagen. Probá con un JPG o PNG.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _save({bool remove = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final db = Supabase.instance.client;
      String? path;
      if (!remove) {
        // A new path avoids displaying a cached previous image after replacement.
        path =
            '${widget.product['id']}/${DateTime.now().microsecondsSinceEpoch}.jpg';
        await db.storage
            .from(productPhotoBucket)
            .uploadBinary(
              path,
              _bytes!,
              fileOptions: const FileOptions(
                contentType: 'image/jpeg',
                cacheControl: '3600',
              ),
            );
      }
      // Solo cambia la foto (nunca precios ni costos) y queda registrado quién la cambió.
      // La foto anterior se conserva para poder deshacer el cambio.
      await db.rpc(
        'cambiar_foto_producto',
        params: {'p_producto': widget.product['id'], 'p_foto': path},
      );
      widget.product['foto_path'] = path;
      if (mounted) Navigator.pop(context, true);
    } on PostgrestException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error =
              'No se pudo guardar la foto. Verificá la conexión y volvé a intentar.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text('Foto: ${widget.product['nombre']}'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_bytes != null)
                Image.memory(
                  _bytes!,
                  width: 220,
                  height: 220,
                  fit: BoxFit.contain,
                )
              else
                ProductPhoto(
                  path: widget.product['foto_path']?.toString(),
                  size: 220,
                ),
              const SizedBox(height: 16),
              const Text(
                'La misma foto se verá en Alberdi y en el catálogo web. Se reduce automáticamente al guardarla.',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  if (cameraAvailable)
                    FilledButton.tonalIcon(
                      onPressed: _busy ? null : () => _pick(camera: true),
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('Sacar foto'),
                    ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _pick(),
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: Text(cameraAvailable ? 'Galería' : 'Elegir imagen'),
                  ),
                ],
              ),
              if (_busy) const LinearProgressIndicator(),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (_bytes != null)
                Text('Lista para subir: ${(_bytes!.length / 1024).ceil()} KB'),
              if (widget.product['foto_path'] != null)
                TextButton(
                  onPressed: _busy ? null : () => _save(remove: true),
                  child: const Text('Quitar foto del producto'),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _busy || _bytes == null ? null : _save,
          child: const Text('Guardar foto'),
        ),
      ],
    ),
  );
}
