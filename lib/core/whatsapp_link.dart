import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// A bare national number is usable only after the user confirms it is mobile.
String? normalizeArgentineWhatsApp(
  String? value, {
  bool nationalMobileConfirmed = false,
}) {
  final raw = value?.trim() ?? '';
  if (!RegExp(r'^\+?[\d\s().-]+$').hasMatch(raw)) return null;
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  final international = RegExp(
    r'^549((?:11|[23]\d{2,3})\d+)$',
  ).firstMatch(digits);
  if (international != null && digits.length == 13) return digits;
  if (raw.startsWith('+')) return null;

  final withMobileMarker = RegExp(
    r'^9((?:11|[23]\d{2,3})\d+)$',
  ).firstMatch(digits);
  if (withMobileMarker != null && digits.length == 11) return '54$digits';

  final local = RegExp(r'^0?(11|[23]\d{2,3})15(\d+)$').firstMatch(digits);
  if (local != null) {
    final national = '${local[1]}${local[2]}';
    if (national.length == 10) return '549$national';
  }

  final national = digits.startsWith('0') ? digits.substring(1) : digits;
  if (nationalMobileConfirmed &&
      national.length == 10 &&
      RegExp(r'^(?:11|[23]\d{2,3})\d+$').hasMatch(national)) {
    return '549$national';
  }
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
