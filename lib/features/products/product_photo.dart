import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart';

const productPhotoBucket = 'productos-fotos';

/// Executed in an isolate; normalizes orientation and removes source metadata.
Uint8List prepareProductPhoto(Uint8List bytes) {
  if (bytes.length > 20 * 1024 * 1024) {
    throw const FormatException('La imagen supera los 20 MB.');
  }
  if (bytes.length < 12) {
    throw const FormatException('Elegí una imagen JPG, PNG o WebP válida.');
  }
  final img.Decoder? decoder = bytes[0] == 0xff && bytes[1] == 0xd8
      ? img.JpegDecoder()
      : bytes[0] == 0x89 &&
            bytes[1] == 0x50 &&
            bytes[2] == 0x4e &&
            bytes[3] == 0x47
      ? img.PngDecoder()
      : String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
            String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP'
      ? img.WebPDecoder()
      : null;
  final info = decoder?.startDecode(bytes);
  if (info == null || info.width < 1 || info.height < 1) {
    throw const FormatException('Elegí una imagen JPG, PNG o WebP válida.');
  }
  if (info.width * info.height > 40000000) {
    throw const FormatException(
      'La imagen es demasiado grande. Usá una de hasta 40 megapíxeles.',
    );
  }
  final decoded = decoder!.decodeFrame(0);
  if (decoded == null) {
    throw const FormatException('No se pudo leer la imagen.');
  }
  var photo = img.bakeOrientation(decoded);
  if (photo.width > 960 || photo.height > 960) {
    photo = img.copyResize(
      photo,
      width: photo.width >= photo.height ? 960 : null,
      height: photo.height > photo.width ? 960 : null,
      interpolation: img.Interpolation.average,
    );
  }
  // A fresh canvas drops EXIF/GPS metadata and gives transparency a white base.
  final clean = img.Image(width: photo.width, height: photo.height);
  img.fill(clean, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(clean, photo);
  for (final quality in [82, 70, 55, 40]) {
    final result = img.encodeJpg(clean, quality: quality);
    if (result.length <= 300 * 1024) return result;
  }
  throw const FormatException(
    'No se pudo reducir la foto. Probá con otra imagen.',
  );
}

class ProductPhoto extends StatelessWidget {
  final String? path;
  final double size;
  const ProductPhoto({super.key, this.path, this.size = 64});

  @override
  Widget build(BuildContext context) {
    Widget placeholder() => Container(
      width: size,
      height: size,
      color: const Color(0xffe1ebe4),
      child: const Icon(Icons.inventory_2_outlined, color: Color(0xff436550)),
    );
    final url = path == null || path!.isEmpty
        ? null
        : Supabase.instance.client.storage
              .from(productPhotoBucket)
              .getPublicUrl(path!);
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: url == null
          ? placeholder()
          : Tooltip(
              message: 'Ampliar foto',
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (_) => _ProductPhotoViewer(url: url),
                  ),
                  child: Image.network(
                    url,
                    width: size,
                    height: size,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => placeholder(),
                  ),
                ),
              ),
            ),
    );
  }
}

class _ProductPhotoViewer extends StatelessWidget {
  final String url;
  const _ProductPhotoViewer({required this.url});

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    child: SafeArea(
      child: Column(
        children: [
          AppBar(
            automaticallyImplyLeading: false,
            title: const Text('Foto del producto'),
            actions: [
              IconButton(
                tooltip: 'Cerrar foto',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text(
              'Usá dos dedos o la rueda del mouse para acercar la foto.',
            ),
          ),
          Expanded(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: SizedBox.expand(
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Center(
                    child: Text(
                      'No se pudo cargar la foto. Cerrá e intentá nuevamente.',
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
