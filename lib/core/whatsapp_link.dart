import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Número de WhatsApp argentino en formato internacional (549 + código de área + número).
///
/// En Argentina WhatsApp se usa con celulares, así que un número nacional completo
/// (código de área + número, con o sin 0 y 15) se toma como celular sin preguntar.
/// También corrige el +54 sin el 9. Un número sin código de área no se adivina: null.
/// `nationalMobileConfirmed: false` conserva el criterio estricto anterior (solo prefijos
/// móviles inequívocos), por si algún uso lo necesita.
String? normalizeArgentineWhatsApp(
  String? value, {
  bool nationalMobileConfirmed = true,
}) {
  final raw = value?.trim() ?? '';
  if (!RegExp(r'^\+?[\d\s().-]+$').hasMatch(raw)) return null;
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  bool isNational(String number) =>
      number.length == 10 && RegExp(r'^(?:11|[23]\d{2,3})\d+$').hasMatch(number);

  final international = RegExp(r'^549(\d+)$').firstMatch(digits);
  if (international != null && isNational(international[1]!)) return digits;
  // +54 sin el 9 (muy común al copiar): los códigos de área nunca empiezan con 5.
  final withoutNine = RegExp(r'^54(\d+)$').firstMatch(digits);
  if (nationalMobileConfirmed &&
      withoutNine != null &&
      isNational(withoutNine[1]!)) {
    return '549${withoutNine[1]}';
  }
  if (raw.startsWith('+')) return null;

  final withMobileMarker = RegExp(r'^9(\d+)$').firstMatch(digits);
  if (withMobileMarker != null &&
      digits.length == 11 &&
      isNational(withMobileMarker[1]!)) {
    return '54$digits';
  }

  final local = RegExp(r'^0?(11|[23]\d{2,3})15(\d+)$').firstMatch(digits);
  if (local != null) {
    final national = '${local[1]}${local[2]}';
    if (isNational(national)) return '549$national';
  }

  final national = digits.startsWith('0') ? digits.substring(1) : digits;
  if (nationalMobileConfirmed && isNational(national)) return '549$national';
  return null;
}

Uri whatsAppLink(String number, {String? text}) {
  return Uri.https(
    'wa.me',
    '/$number',
  ).replace(query: text == null ? null : 'text=${Uri.encodeComponent(text)}');
}

typedef WhatsAppLauncher = Future<bool> Function(Uri link);

Future<bool> launchWhatsAppLink(Uri link) =>
    launchUrl(link, mode: LaunchMode.externalApplication);

Future<void> openWhatsApp(
  BuildContext context,
  String number, {
  String? text,
  WhatsAppLauncher launch = launchWhatsAppLink,
}) async {
  try {
    if (await launch(whatsAppLink(number, text: text))) return;
  } catch (_) {
    // Treat unavailable platform handlers like a failed external launch.
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'No se pudo abrir WhatsApp. Revisá la aplicación o el navegador e intentá de nuevo.',
        ),
      ),
    );
  }
}
